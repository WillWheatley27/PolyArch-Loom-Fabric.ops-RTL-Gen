// fu_cordic_hyp.sv -- Fabric FU for share group cordic_hyp.
// op_list: math.sinh, math.cosh
//   op_sel = 0 -> out = sinh(x)   (math.sinh)
//   op_sel = 1 -> out = cosh(x)   (math.cosh)
//
// One shared HYPERBOLIC CORDIC rotator: X = cosh, Y = sinh. op_sel taps which.
// Unary op. Intrinsic latency 1.
//
// APPROXIMATE, NOT bit-exact. No loom reference. Fixed-point Q(QINT.QFRAC),
// NITER hyperbolic steps (indices generated per format, with 4,13,40,... REPEATED
// for convergence); constants (1/Ah, atanh table, shift indices) baked per format.
// No fold: cosh even, sinh odd, both from z0=x. ASSUMES |x| <= ~1.118 (hyperbolic
// convergence range). Subnormals FTZ. PARAMETERIZED (EXP_W, MANT_W): fp32/fp64/bf16.

module fu_cordic_hyp #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned BIAS   = (1 << (EXP_W - 1)) - 1,
  localparam int unsigned SIG_W  = MANT_W + 1,
  localparam int unsigned QFRAC  = 28,
  localparam int unsigned FXW    = 32,
  localparam int unsigned NITER  = 24,
  localparam int unsigned CLZW   = $clog2(FXW + 1)
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = math.sinh (sinh), 1 = math.cosh (cosh)

  input  logic [WIDTH-1:0]  in_data_0,  // x
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,   // sinh(x) or cosh(x)
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic signed [FXW-1:0] X0 = 32'sd324135026;   // 1/A_h seeds cosh
  localparam logic [6:0] SHIFT [0:NITER-1] = '{ 7'd1, 7'd2, 7'd3, 7'd4, 7'd4, 7'd5, 7'd6, 7'd7, 7'd8, 7'd9, 7'd10, 7'd11, 7'd12, 7'd13, 7'd13, 7'd14, 7'd15, 7'd16, 7'd17, 7'd18, 7'd19, 7'd20, 7'd21, 7'd22 };
  localparam logic signed [FXW-1:0] ATANH [0:NITER-1] = '{ 32'sd147453245, 32'sd68561855, 32'sd33730852, 32'sd16799113, 32'sd16799113, 32'sd8391340, 32'sd4194645, 32'sd2097195, 32'sd1048581, 32'sd524289, 32'sd262144, 32'sd131072, 32'sd65536, 32'sd32768, 32'sd32768, 32'sd16384, 32'sd8192, 32'sd4096, 32'sd2048, 32'sd1024, 32'sd512, 32'sd256, 32'sd128, 32'sd64 };

  function automatic logic [CLZW-1:0] clz(input logic [FXW-1:0] x);
    logic [CLZW-1:0] n; logic f; integer i;
    begin n = '0; f = 1'b0;
      for (i = FXW-1; i >= 0; i = i-1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 1'b1; end
      clz = n;
    end
  endfunction

  logic        s_in;
  logic [EXP_W-1:0]  e_in;
  logic [MANT_W-1:0] m_in;
  logic [SIG_W-1:0]  sig_in;
  logic signed [15:0] shamt;
  // verilator lint_off UNUSEDSIGNAL
  logic [FXW-1:0]        mag_fx;
  logic signed [FXW-1:0] ang_fx;
  logic signed [FXW-1:0] cx [0:NITER];
  logic signed [FXW-1:0] cy [0:NITER];
  logic signed [FXW-1:0] cz [0:NITER];
  logic signed [FXW-1:0] res_fx;
  logic [FXW-1:0]        rmag, norm_e;
  logic [MANT_W-1:0]     mant_e;
  logic [MANT_W:0]       mant24_e;
  logic signed [15:0]    exp_be;
  // verilator lint_on UNUSEDSIGNAL
  logic        rsign, guard_e, sticky_e, roundup_e;
  logic [CLZW-1:0] clz_e;
  logic [MANT_W-1:0] mant_fe;
  logic [WIDTH-1:0] conv_result;
  integer      ii;

  always_comb begin : datapath
    // decode binary32 -> Q(QINT.QFRAC) (FTZ)
    s_in = in_data_0[WIDTH-1]; e_in = in_data_0[WIDTH-2:MANT_W]; m_in = in_data_0[MANT_W-1:0];
    sig_in = {1'b1, m_in};
    shamt = signed'(16'(e_in)) - signed'(16'(BIAS)) + signed'(16'(QFRAC - MANT_W));
    if (e_in == '0)          mag_fx = '0;
    else if (shamt >= 0)     mag_fx = FXW'(sig_in) << shamt[5:0];
    else                     mag_fx = FXW'(sig_in) >> (-shamt);
    ang_fx = s_in ? -signed'(mag_fx) : signed'(mag_fx);

    // hyperbolic CORDIC (NITER steps, unrolled; x->cosh, y->sinh)
    cx[0] = X0; cy[0] = '0; cz[0] = ang_fx;
    for (ii = 0; ii < NITER; ii = ii + 1) begin : cordic
      if (!cz[ii][FXW-1]) begin                 // z >= 0, d = +1
        cx[ii+1] = cx[ii] + (cy[ii] >>> SHIFT[ii]);
        cy[ii+1] = cy[ii] + (cx[ii] >>> SHIFT[ii]);
        cz[ii+1] = cz[ii] - ATANH[ii];
      end else begin                            // z < 0, d = -1
        cx[ii+1] = cx[ii] - (cy[ii] >>> SHIFT[ii]);
        cy[ii+1] = cy[ii] - (cx[ii] >>> SHIFT[ii]);
        cz[ii+1] = cz[ii] + ATANH[ii];
      end
    end : cordic

    res_fx = op_sel ? cx[NITER] : cy[NITER];    // 1=cosh (X), 0=sinh (Y)

    // encode Q(QINT.QFRAC) (value = res_fx * 2^-QFRAC) -> binary32, RNE
    rsign = res_fx[FXW-1];
    rmag  = rsign ? (~res_fx + 1'b1) : res_fx;
    clz_e = clz(rmag);
    norm_e = rmag << clz_e;
    mant_e = norm_e[FXW-2 -: MANT_W];
    guard_e = norm_e[FXW-2-MANT_W];
    sticky_e = |norm_e[FXW-3-MANT_W : 0];
    roundup_e = guard_e & (sticky_e | mant_e[0]);
    mant24_e = {1'b0, mant_e} + (MANT_W+1)'(roundup_e);
    exp_be = signed'(16'(BIAS + 3)) - signed'(16'(clz_e))
             + (mant24_e[MANT_W] ? 16'sd1 : 16'sd0);
    mant_fe = mant24_e[MANT_W] ? '0 : mant24_e[MANT_W-1:0];

    if (rmag == '0)            conv_result = {rsign, {(WIDTH-1){1'b0}}};
    else if (exp_be <= 0)      conv_result = {rsign, {EXP_W{1'b0}}, {MANT_W{1'b0}}};
    else                       conv_result = {rsign, exp_be[EXP_W-1:0], mant_fe};
  end : datapath

  // ---- latency-1 handshake (unary) ----
  logic fire;
  assign fire       = in_valid_0 & (~out_valid | out_ready);
  assign in_ready_0 = fire;

  always_ff @(posedge clk) begin : pipe
    if (!rst_n) begin
      out_valid <= 1'b0; out_data <= {WIDTH{1'b0}};
    end else begin
      if (fire)           begin out_data <= conv_result; out_valid <= 1'b1; end
      else if (out_ready) out_valid <= 1'b0;
    end
  end : pipe

endmodule : fu_cordic_hyp
