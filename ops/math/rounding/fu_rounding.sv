// fu_rounding.sv -- Fabric FU for share group rounding.
// op_list: math.floor, math.ceil, math.round, math.trunc, math.roundeven
//   op_sel = 0 -> floor(x)      (math.floor)  toward -Inf
//   op_sel = 1 -> ceil(x)       (math.ceil)  toward +Inf
//   op_sel = 2 -> round(x)      (math.round)  nearest, ties away from zero
//   op_sel = 3 -> trunc(x)      (math.trunc)  toward zero
//   op_sel = 4 -> roundeven(x)  (math.roundeven)  nearest, ties to even
//
// One shared rounding network; op_sel selects the mode. op_sel held config.
// Unary op. Intrinsic latency 1. binary32. EXACT (bit-accurate, no LUT/approx):
// pure exponent/mantissa manipulation. Subnormals FTZ -> signed zero (documented
// deviation: e.g. floor of a tiny negative subnormal gives -0, not -1).

module fu_rounding #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic [2:0]        op_sel,     // 0=floor 1=ceil 2=round 3=trunc 4=roundeven

  input  logic [WIDTH-1:0]  in_data_0,  // x (binary32)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  logic        s;
  logic [7:0]  e_in;
  logic [22:0] m_in;
  logic [23:0] sig;

  // general fractional case (127 <= E <= 149)
  logic [4:0]  fb;
  // verilator lint_off UNUSEDSIGNAL
  logic [24:0] onefb, mask, half;   // bit 24 never set (fb <= 23)
  logic [24:0] sigr;                // sigr[23] is the implicit leading 1 (unused)
  // verilator lint_on UNUSEDSIGNAL
  logic [23:0] fracb, sigt;
  logic        intlsb, roundup;
  logic [7:0]  e_out;
  logic [22:0] mant_out;
  logic [31:0] gen_res;

  // |x| < 1 case
  logic        ge_half, gt_half;
  logic [31:0] sub_res;

  logic [31:0] conv_result;

  always_comb begin : datapath
    s = in_data_0[31]; e_in = in_data_0[30:23]; m_in = in_data_0[22:0];
    sig = {1'b1, m_in};

    // ---- general fractional (fb = 150 - E dropped bits; in [1,23] when used) ----
    fb     = 5'(8'd150 - e_in);
    onefb  = 25'd1 << fb;
    mask   = onefb - 25'd1;
    half   = onefb >> 1;
    fracb  = sig & mask[23:0];
    sigt   = sig & ~mask[23:0];
    intlsb = sig[fb];
    case (op_sel)
      3'd0:    roundup = s & (|fracb);                              // floor
      3'd1:    roundup = (~s) & (|fracb);                           // ceil
      3'd2:    roundup = (fracb >= half[23:0]);                     // round (ties away)
      3'd4:    roundup = (fracb > half[23:0]) | ((fracb == half[23:0]) & intlsb); // roundeven
      default: roundup = 1'b0;                                      // trunc / reserved
    endcase
    sigr = {1'b0, sigt} + (roundup ? onefb : 25'd0);
    if (sigr[24]) begin e_out = e_in + 8'd1; mant_out = 23'd0;     end
    else          begin e_out = e_in;        mant_out = sigr[22:0]; end
    gen_res = {s, e_out, mant_out};

    // ---- |x| < 1 (E in [1,126]) ----
    ge_half = (e_in == 8'd126);                 // |x| >= 0.5
    gt_half = (e_in == 8'd126) & (|m_in);       // |x| > 0.5
    case (op_sel)
      3'd0:    sub_res = s ? {1'b1, 8'd127, 23'd0} : 32'd0;         // floor: -1 / +0
      3'd1:    sub_res = s ? {1'b1, 31'd0} : {1'b0, 8'd127, 23'd0}; // ceil: -0 / +1
      3'd2:    sub_res = ge_half ? {s, 8'd127, 23'd0} : {s, 31'd0}; // round
      3'd4:    sub_res = gt_half ? {s, 8'd127, 23'd0} : {s, 31'd0}; // roundeven
      default: sub_res = {s, 31'd0};                               // trunc: +/-0
    endcase

    // ---- top selection ----
    if (e_in == 8'd0)        conv_result = {s, 31'd0};   // FTZ subnormal/zero -> signed 0
    else if (e_in >= 8'd150) conv_result = in_data_0;    // already integer, or Inf/NaN
    else if (e_in < 8'd127)  conv_result = sub_res;      // |x| < 1
    else                     conv_result = gen_res;      // mixed integer+fraction
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
