// fu_approx_tanh_erf.sv -- Fabric FU for share group approx_tanh_erf.
// op_list: math.tanh, math.erf
//   op_sel = 0 -> out = tanh(x)   (math.tanh)
//   op_sel = 1 -> out = erf(x)    (math.erf)
//
// One shared LUT + linear-interpolation core; op_sel selects the tanh vs erf
// table (addressing/interp shared). op_sel held config. Unary op. Latency 1.
//
// APPROXIMATE. tanh/erf are stiff sigmoids (poly-hostile), so a COMPILE-TIME-
// GENERATED LUT is used (tables baked per format): 129 entries at x = k/32
// (k=0..128) over [0,4], value*2^MANT_W. Odd symmetry: compute f(|x|), apply
// sign. |x| >= 4 saturates to T[128]. PARAMETERIZED (EXP_W, MANT_W). FTZ.

module fu_approx_tanh_erf #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned BIAS   = (1 << (EXP_W - 1)) - 1,
  localparam int unsigned SIG_W  = MANT_W + 1,
  localparam int unsigned TW     = MANT_W + 1,          // table entry width (value*2^MANT_W)
  localparam int unsigned RCONST = BIAS + MANT_W - 21,  // decode: u = sig << (e - RCONST)
  localparam int unsigned UW     = 24,                  // FIXED decode field: idx[22:16], frac[15:0]
  localparam int unsigned CLZ_W  = MANT_W + 9           // clz field (mantissa + guard/sticky)
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = math.tanh (tanh), 1 = math.erf (erf)

  input  logic [WIDTH-1:0]  in_data_0,  // x
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,   // tanh(x) or erf(x)
  output logic              out_valid,
  input  logic              out_ready
);

  // ---- f(k/32) tables (value * 2^MANT_W), k = 0..128 ----
  localparam logic [TW-1:0] TANH_T [0:128] = '{ 24'd0, 24'd262059, 24'd523606, 24'd784136, 24'd1043149, 24'd1300156, 24'd1554688, 24'd1806288, 24'd2054527, 24'd2298995, 24'd2539313, 24'd2775129, 24'd3006120, 24'd3231996, 24'd3452500, 24'd3667405, 24'd3876520, 24'd4079682, 24'd4276764, 24'd4467666, 24'd4652320, 24'd4830684, 24'd5002744, 24'd5168510, 24'd5328016, 24'd5481314, 24'd5628480, 24'd5769602, 24'd5904788, 24'd6034156, 24'd6157838, 24'd6275975, 24'd6388715, 24'd6496215, 24'd6598637, 24'd6696146, 24'd6788909, 24'd6877098, 24'd6960883, 24'd7040433, 24'd7115919, 24'd7187507, 24'd7255363, 24'd7319648, 24'd7380521, 24'd7438138, 24'd7492649, 24'd7544200, 24'd7592934, 24'd7638987, 24'd7682493, 24'd7723579, 24'd7762367, 24'd7798975, 24'd7833517, 24'd7866101, 24'd7896830, 24'd7925804, 24'd7953116, 24'd7978857, 24'd8003112, 24'd8025963, 24'd8047488, 24'd8067760, 24'd8086849, 24'd8104823, 24'd8121743, 24'd8137670, 24'd8152659, 24'd8166766, 24'd8180040, 24'd8192528, 24'd8204278, 24'd8215330, 24'd8225727, 24'd8235505, 24'd8244702, 24'd8253350, 24'd8261483, 24'd8269130, 24'd8276321, 24'd8283081, 24'd8289437, 24'd8295412, 24'd8301029, 24'd8306309, 24'd8311272, 24'd8315937, 24'd8320322, 24'd8324444, 24'd8328317, 24'd8331958, 24'd8335379, 24'd8338595, 24'd8341616, 24'd8344456, 24'd8347124, 24'd8349632, 24'd8351988, 24'd8354202, 24'd8356283, 24'd8358238, 24'd8360075, 24'd8361801, 24'd8363422, 24'd8364946, 24'd8366378, 24'd8367723, 24'd8368987, 24'd8370174, 24'd8371290, 24'd8372338, 24'd8373323, 24'd8374248, 24'd8375118, 24'd8375934, 24'd8376702, 24'd8377423, 24'd8378100, 24'd8378736, 24'd8379334, 24'd8379896, 24'd8380423, 24'd8380919, 24'd8381384, 24'd8381822, 24'd8382233, 24'd8382619, 24'd8382982 };
  localparam logic [TW-1:0] ERF_T  [0:128] = '{ 24'd0, 24'd295702, 24'd590826, 24'd884801, 24'd1177058, 24'd1467041, 24'd1754206, 24'd2038027, 24'd2317994, 24'd2593621, 24'd2864447, 24'd3130035, 24'd3389978, 24'd3643902, 24'd3891460, 24'd4132341, 24'd4366269, 24'd4593001, 24'd4812330, 24'd5024083, 24'd5228123, 24'd5424348, 24'd5612689, 24'd5793110, 24'd5965606, 24'd6130204, 24'd6286960, 24'd6435955, 24'd6577298, 24'd6711120, 24'd6837575, 24'd6956833, 24'd7069087, 24'd7174540, 24'd7273412, 24'd7365932, 24'd7452341, 24'd7532883, 24'd7607811, 24'd7677380, 24'd7741847, 24'd7801471, 24'd7856507, 24'd7907209, 24'd7953827, 24'd7996607, 24'd8035788, 24'd8071603, 24'd8104277, 24'd8134028, 24'd8161064, 24'd8185585, 24'd8207781, 24'd8227834, 24'd8245915, 24'd8262187, 24'd8276802, 24'd8289903, 24'd8301623, 24'd8312089, 24'd8321416, 24'd8329711, 24'd8337075, 24'd8343599, 24'd8349368, 24'd8354460, 24'd8358944, 24'd8362886, 24'd8366344, 24'd8369373, 24'd8372020, 24'd8374328, 24'd8376338, 24'd8378084, 24'd8379598, 24'd8380908, 24'd8382040, 24'd8383016, 24'd8383855, 24'd8384576, 24'd8385194, 24'd8385723, 24'd8386174, 24'd8386558, 24'd8386885, 24'd8387163, 24'd8387398, 24'd8387596, 24'd8387764, 24'd8387905, 24'd8388024, 24'd8388123, 24'd8388207, 24'd8388276, 24'd8388334, 24'd8388383, 24'd8388423, 24'd8388456, 24'd8388484, 24'd8388506, 24'd8388525, 24'd8388540, 24'd8388553, 24'd8388563, 24'd8388572, 24'd8388579, 24'd8388584, 24'd8388589, 24'd8388593, 24'd8388596, 24'd8388598, 24'd8388600, 24'd8388602, 24'd8388603, 24'd8388604, 24'd8388605, 24'd8388606, 24'd8388606, 24'd8388606, 24'd8388607, 24'd8388607, 24'd8388607, 24'd8388607, 24'd8388608, 24'd8388608, 24'd8388608, 24'd8388608, 24'd8388608, 24'd8388608 };

  function automatic logic [$clog2(CLZ_W+1)-1:0] clz(input logic [CLZ_W-1:0] x);
    logic [$clog2(CLZ_W+1)-1:0] n; logic f; integer i;
    begin n = '0; f = 1'b0;
      for (i = CLZ_W-1; i >= 0; i = i-1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 1'b1; end
      clz = n;
    end
  endfunction

  logic        s_in, sat;
  logic [EXP_W-1:0]  e_in;
  logic [MANT_W-1:0] m_in;
  logic [SIG_W-1:0]  sig_in;
  logic signed [15:0] sh;
  // verilator lint_off UNUSEDSIGNAL
  logic [UW-1:0]     u;               // |x|*32 in fixed Q8.16 (idx=u[22:16], frac=u[15:0])
  logic [15+TW:0]    prod;            // frac(16) * delta(TW); low 16 dropped
  logic [CLZ_W-1:0]  magpad, norm_e;
  // verilator lint_on UNUSEDSIGNAL
  logic [7:0]  idx, idx1;
  logic [15:0] frac;
  logic [TW-1:0] t0, t1, ts, delta, interp, mag_val;
  logic [$clog2(CLZ_W+1)-1:0] clz_e;
  logic [MANT_W-1:0] mant_e, mant_fe;
  logic        guard_e, sticky_e, roundup_e, rsign;
  logic [MANT_W:0] mant24_e;
  logic signed [15:0] exp_be;
  logic [WIDTH-1:0] conv_result;

  always_comb begin : datapath
    s_in = in_data_0[WIDTH-1]; e_in = in_data_0[WIDTH-2:MANT_W]; m_in = in_data_0[MANT_W-1:0];
    sig_in = {1'b1, m_in};

    // decode |x| -> u = |x|*32 in a FIXED Q8.16 field (idx=u[22:16], frac=u[15:0]);
    // sat purely by exponent (|x| >= 4 <=> unbiased exp >= 2). u = sig << (e - RCONST),
    // handling both shift directions (small formats like bf16 need a left shift).
    sh = signed'(16'(e_in)) - signed'(16'(RCONST));
    if (e_in == '0)                    begin u = '0; sat = 1'b0; end
    else if (32'(e_in) >= (BIAS + 2))  begin u = '0; sat = 1'b1; end   // |x| >= 4
    else if (sh >= 0)                  begin u = UW'(sig_in) << sh[4:0]; sat = 1'b0; end  // MANT_W<=22
    else                               begin u = UW'(sig_in >> (-sh));  sat = 1'b0; end   // MANT_W>=23
    idx  = {1'b0, u[22:16]};
    frac = u[15:0];
    idx1 = idx + 8'd1;

    // table select + linear interpolation
    t0 = op_sel ? ERF_T[idx]  : TANH_T[idx];
    t1 = op_sel ? ERF_T[idx1] : TANH_T[idx1];
    ts = op_sel ? ERF_T[8'd128] : TANH_T[8'd128];
    delta   = t1 - t0;
    prod    = {{TW{1'b0}}, frac} * {16'd0, delta};
    interp  = t0 + prod[15+TW -: TW];
    mag_val = sat ? ts : interp;

    // encode magnitude (value = mag_val * 2^-MANT_W) -> binary32, RNE
    rsign    = s_in;
    magpad   = {{(CLZ_W-TW){1'b0}}, mag_val};
    clz_e    = clz(magpad);
    norm_e   = magpad << clz_e;
    mant_e   = norm_e[CLZ_W-2 -: MANT_W];
    guard_e  = norm_e[7];
    sticky_e = |norm_e[6:0];
    roundup_e = guard_e & (sticky_e | mant_e[0]);
    mant24_e = {1'b0, mant_e} + (MANT_W+1)'(roundup_e);
    exp_be   = signed'(16'(BIAS + 8)) - signed'(16'(clz_e))
               + (mant24_e[MANT_W] ? 16'sd1 : 16'sd0);
    mant_fe  = mant24_e[MANT_W] ? '0 : mant24_e[MANT_W-1:0];

    if (mag_val == '0)          conv_result = {rsign, {(WIDTH-1){1'b0}}};
    else if (exp_be <= 0)       conv_result = {rsign, {EXP_W{1'b0}}, {MANT_W{1'b0}}};
    else                        conv_result = {rsign, exp_be[EXP_W-1:0], mant_fe};
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

endmodule : fu_approx_tanh_erf
