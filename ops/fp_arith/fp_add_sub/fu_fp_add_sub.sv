// fu_fp_add_sub.sv -- Fabric FU for share group fp_add_sub.
// op_list: arith.addf, arith.subf
//   op_sel = 0 -> out = a + b   (arith.addf)
//   op_sel = 1 -> out = a - b   (arith.subf)  [add with operand B sign flipped]
//
// One shared IEEE-754 adder; op_sel only flips operand B's sign. op_sel is a held
// config input. 2-input join, intrinsic latency 1.
//
// PARAMETERIZED IEEE-754 format via (EXP_W, MANT_W): fp32 (8,23) default,
// fp64 (11,52), bf16 (8,7). Round-to-nearest-even. Subnormals FLUSHED TO ZERO
// (FTZ): subnormal inputs treated as signed zero; subnormal results underflow to
// signed zero. NaN/Inf/signed-zero handled. Datapath uses 3 guard bits (GRS).

module fu_fp_add_sub #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned SIG_W  = MANT_W + 1,        // significand incl. leading 1
  localparam int unsigned NORM_W = MANT_W + 4,        // significand + guard/round/sticky
  localparam int unsigned ALN_W  = MANT_W + 5,        // + carry bit
  localparam int unsigned LZW    = $clog2(NORM_W + 1),
  localparam int unsigned ES_W   = EXP_W + 2          // signed exponent working width
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = arith.addf, 1 = arith.subf (B sign flipped)

  input  logic [WIDTH-1:0]  in_data_0,  // operand A
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,  // operand B
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic [WIDTH-1:0] QNAN    = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};
  localparam int unsigned      EXP_MAX = (1 << EXP_W) - 1;

  // Leading-zero count over NORM_W bits (x assumed nonzero).
  function automatic logic [LZW-1:0] lzc(input logic [NORM_W-1:0] x);
    logic [LZW-1:0] n; logic found; integer i;
    begin
      n = '0; found = 1'b0;
      for (i = NORM_W - 1; i >= 0; i = i - 1)
        if (!found) begin if (x[i]) found = 1'b1; else n = n + 1'b1; end
      lzc = n;
    end
  endfunction

  // ---- unpack (operand B sign flipped for subf) ----
  logic              sa, sb;
  logic [EXP_W-1:0]  ea, eb;
  logic [MANT_W-1:0] ma, mb;
  logic              a_nan, b_nan, a_inf, b_inf, a_zero, b_zero;
  logic [SIG_W-1:0]  sig_a, sig_b;

  // ---- both-normal datapath ----
  logic              big_sign, small_sign, add_op;
  logic [EXP_W-1:0]  big_exp, diff;
  logic [SIG_W-1:0]  big_sig, small_sig;
  // verilator lint_off UNUSEDSIGNAL
  logic [ALN_W-1:0]  big_m, small_m, small_aligned, raw;  // top bit = add carry
  logic [NORM_W-1:0] norm;                                // top bit = implicit leading 1
  // verilator lint_on UNUSEDSIGNAL
  logic              sticky_shift, sticky;
  logic [LZW-1:0]    nsh;
  logic [MANT_W-1:0] mant23, mant_final;
  logic              guard, round_up;
  logic [SIG_W-1:0]  mant_r;
  logic signed [ES_W-1:0] exp_s, exp_s2;
  logic [WIDTH-1:0]  result;

  always_comb begin : fadd
    sa = in_data_0[WIDTH-1]; ea = in_data_0[WIDTH-2:MANT_W]; ma = in_data_0[MANT_W-1:0];
    sb = op_sel ? ~in_data_1[WIDTH-1] : in_data_1[WIDTH-1];
    eb = in_data_1[WIDTH-2:MANT_W]; mb = in_data_1[MANT_W-1:0];

    a_nan = (&ea) & (|ma); b_nan = (&eb) & (|mb);
    a_inf = (&ea) & (~|ma); b_inf = (&eb) & (~|mb);
    a_zero = (ea == '0); b_zero = (eb == '0);       // FTZ: subnormal or zero -> zero
    sig_a = {1'b1, ma}; sig_b = {1'b1, mb};

    big_sign = 1'b0; small_sign = 1'b0; add_op = 1'b0;
    big_exp = '0; big_sig = '0; small_sig = '0; diff = '0;
    big_m = '0; small_m = '0; small_aligned = '0; raw = '0; norm = '0;
    sticky_shift = 1'b0; sticky = 1'b0; nsh = '0;
    mant23 = '0; mant_final = '0; guard = 1'b0; round_up = 1'b0; mant_r = '0;
    exp_s = '0; exp_s2 = '0; result = {WIDTH{1'b0}};

    if (a_nan | b_nan)         result = QNAN;
    else if (a_inf & b_inf)    result = (sa == sb) ? {sa, {EXP_W{1'b1}}, {MANT_W{1'b0}}} : QNAN;
    else if (a_inf)            result = {sa, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    else if (b_inf)            result = {sb, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    else if (a_zero & b_zero)  result = {sa & sb, {(WIDTH-1){1'b0}}};   // +0 unless both -0
    else if (a_zero)           result = {sb, eb, mb};
    else if (b_zero)           result = {sa, ea, ma};
    else begin : both_normal
      if ((ea > eb) | ((ea == eb) & (ma >= mb))) begin
        big_sign = sa; big_exp = ea; big_sig = sig_a; small_sign = sb; small_sig = sig_b; diff = ea - eb;
      end else begin
        big_sign = sb; big_exp = eb; big_sig = sig_b; small_sign = sa; small_sig = sig_a; diff = eb - ea;
      end
      add_op = (big_sign == small_sign);

      big_m   = {1'b0, big_sig,   3'b000};
      small_m = {1'b0, small_sig, 3'b000};
      if (32'(diff) >= ALN_W) begin
        small_aligned = '0;
        sticky_shift  = |small_sig;
      end else begin
        small_aligned = small_m >> diff;
        sticky_shift  = |(small_m & ((ALN_W'(1) << diff) - ALN_W'(1)));
      end
      // fold far-sticky into the LSB before the op so subtraction borrows correctly
      small_aligned[0] = small_aligned[0] | sticky_shift;

      raw = add_op ? (big_m + small_aligned) : (big_m - small_aligned);

      if (!add_op & (raw == '0)) begin
        result = {WIDTH{1'b0}};                                   // exact cancellation -> +0
      end else begin
        if (add_op & raw[ALN_W-1]) begin
          norm   = raw[ALN_W-1:1];
          exp_s  = signed'(ES_W'(big_exp)) + signed'(ES_W'(1));
          sticky = raw[0];
        end else if (add_op) begin
          norm   = raw[NORM_W-1:0];
          exp_s  = signed'(ES_W'(big_exp));
          sticky = 1'b0;
        end else begin
          nsh    = lzc(raw[NORM_W-1:0]);
          norm   = raw[NORM_W-1:0] << nsh;
          exp_s  = signed'(ES_W'(big_exp)) - signed'(ES_W'(nsh));
          sticky = 1'b0;
        end

        mant23   = norm[MANT_W+2 : 3];
        guard    = norm[2];
        sticky   = sticky | norm[1] | norm[0];
        round_up = guard & (sticky | mant23[0]);
        mant_r   = {1'b0, mant23} + SIG_W'(round_up);
        if (mant_r[SIG_W-1]) begin
          mant_final = '0;
          exp_s2     = exp_s + signed'(ES_W'(1));
        end else begin
          mant_final = mant_r[MANT_W-1:0];
          exp_s2     = exp_s;
        end

        if (exp_s2 >= signed'(ES_W'(EXP_MAX))) result = {big_sign, {EXP_W{1'b1}}, {MANT_W{1'b0}}}; // Inf
        else if (exp_s2 <= 0)                  result = {big_sign, {EXP_W{1'b0}}, {MANT_W{1'b0}}}; // FTZ 0
        else                                   result = {big_sign, exp_s2[EXP_W-1:0], mant_final};
      end
    end : both_normal
  end : fadd

  // ---- latency-1 handshake (2-input join) ----
  logic fire;
  assign fire       = in_valid_0 & in_valid_1 & (~out_valid | out_ready);
  assign in_ready_0 = fire;
  assign in_ready_1 = fire;

  always_ff @(posedge clk) begin : pipe_reg
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_data  <= {WIDTH{1'b0}};
    end else begin
      if (fire) begin
        out_data  <= result;
        out_valid <= 1'b1;
      end else if (out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end : pipe_reg

endmodule : fu_fp_add_sub
