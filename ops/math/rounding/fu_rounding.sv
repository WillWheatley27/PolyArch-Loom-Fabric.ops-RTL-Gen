// fu_rounding.sv -- Fabric FU for share group rounding.
// op_list: math.floor, math.ceil, math.round, math.trunc, math.roundeven
//   op_sel = 0 -> floor(x)      (math.floor)  toward -Inf
//   op_sel = 1 -> ceil(x)       (math.ceil)  toward +Inf
//   op_sel = 2 -> round(x)      (math.round)  nearest, ties away from zero
//   op_sel = 3 -> trunc(x)      (math.trunc)  toward zero
//   op_sel = 4 -> roundeven(x)  (math.roundeven)  nearest, ties to even
//
// One shared rounding network; op_sel selects the mode. op_sel held config.
// Unary op. Intrinsic latency 1. EXACT (bit-accurate, no LUT/approx): pure
// exponent/mantissa manipulation. Subnormals FTZ -> signed zero.
//
// PARAMETERIZED IEEE-754 format via (EXP_W, MANT_W): fp32 (8,23) default,
// fp64 (11,52), bf16 (8,7). All boundary constants derive from the format:
// BIAS, integer threshold BIAS+MANT_W, and the 0.5 boundary BIAS-1.

module fu_rounding #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned SIG_W  = MANT_W + 1,
  localparam int unsigned ONE_W  = MANT_W + 2,               // holds 2^fb and carry
  localparam int unsigned BIAS   = (1 << (EXP_W - 1)) - 1,
  localparam int unsigned INTTH  = BIAS + MANT_W,            // E >= INTTH -> already integer
  localparam int unsigned IDXW   = $clog2(SIG_W)             // bit-index width into sig
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic [2:0]        op_sel,     // 0=floor 1=ceil 2=round 3=trunc 4=roundeven

  input  logic [WIDTH-1:0]  in_data_0,  // x
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic [WIDTH-1:0] POS1 = {1'b0, EXP_W'(BIAS), {MANT_W{1'b0}}};   // +1.0
  localparam logic [WIDTH-1:0] NEG1 = {1'b1, EXP_W'(BIAS), {MANT_W{1'b0}}};   // -1.0

  logic              s;
  logic [EXP_W-1:0]  e_in;
  logic [MANT_W-1:0] m_in;
  logic [SIG_W-1:0]  sig;

  // general fractional case (BIAS <= E < INTTH): drop fb = INTTH - E bits
  logic [EXP_W-1:0]  fb;
  // verilator lint_off UNUSEDSIGNAL
  logic [ONE_W-1:0]  onefb, mask, half;   // top bit unused for the masks
  logic [ONE_W-1:0]  sigr;                // sigr[SIG_W-1] is the implicit leading 1
  // verilator lint_on UNUSEDSIGNAL
  logic [SIG_W-1:0]  fracb, sigt;
  logic              intlsb, roundup;
  logic [EXP_W-1:0]  e_out;
  logic [MANT_W-1:0] mant_out;
  logic [WIDTH-1:0]  gen_res;

  // |x| < 1 case
  logic              ge_half, gt_half;
  logic [WIDTH-1:0]  sub_res;

  logic [WIDTH-1:0]  conv_result;

  always_comb begin : datapath
    s = in_data_0[WIDTH-1]; e_in = in_data_0[WIDTH-2:MANT_W]; m_in = in_data_0[MANT_W-1:0];
    sig = {1'b1, m_in};

    // ---- general fractional (fb = INTTH - E dropped bits; in [1,MANT_W] when used) ----
    fb     = EXP_W'(INTTH) - e_in;
    onefb  = ONE_W'(1) << fb;
    mask   = onefb - ONE_W'(1);
    half   = onefb >> 1;
    fracb  = sig & mask[SIG_W-1:0];
    sigt   = sig & ~mask[SIG_W-1:0];
    intlsb = sig[fb[IDXW-1:0]];
    case (op_sel)
      3'd0:    roundup = s & (|fracb);                                               // floor
      3'd1:    roundup = (~s) & (|fracb);                                            // ceil
      3'd2:    roundup = (fracb >= half[SIG_W-1:0]);                                 // round (ties away)
      3'd4:    roundup = (fracb > half[SIG_W-1:0]) | ((fracb == half[SIG_W-1:0]) & intlsb); // roundeven
      default: roundup = 1'b0;                                                       // trunc / reserved
    endcase
    sigr = {1'b0, sigt} + (roundup ? onefb : ONE_W'(0));
    if (sigr[SIG_W]) begin e_out = e_in + EXP_W'(1); mant_out = '0;             end
    else             begin e_out = e_in;             mant_out = sigr[MANT_W-1:0]; end
    gen_res = {s, e_out, mant_out};

    // ---- |x| < 1 (E in [1, BIAS-1]) ----
    ge_half = (e_in == EXP_W'(BIAS - 1));                 // |x| >= 0.5
    gt_half = (e_in == EXP_W'(BIAS - 1)) & (|m_in);       // |x| > 0.5
    case (op_sel)
      3'd0:    sub_res = s ? NEG1 : {WIDTH{1'b0}};                     // floor: -1 / +0
      3'd1:    sub_res = s ? {1'b1, {(WIDTH-1){1'b0}}} : POS1;         // ceil: -0 / +1
      3'd2:    sub_res = ge_half ? {s, EXP_W'(BIAS), {MANT_W{1'b0}}} : {s, {(WIDTH-1){1'b0}}}; // round
      3'd4:    sub_res = gt_half ? {s, EXP_W'(BIAS), {MANT_W{1'b0}}} : {s, {(WIDTH-1){1'b0}}}; // roundeven
      default: sub_res = {s, {(WIDTH-1){1'b0}}};                       // trunc: +/-0
    endcase

    // ---- top selection ----
    if (e_in == '0)                    conv_result = {s, {(WIDTH-1){1'b0}}}; // FTZ subnormal/zero
    else if (e_in >= EXP_W'(INTTH))    conv_result = in_data_0;             // integer, or Inf/NaN
    else if (e_in < EXP_W'(BIAS))      conv_result = sub_res;               // |x| < 1
    else                               conv_result = gen_res;               // mixed integer+fraction
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

endmodule : fu_rounding
