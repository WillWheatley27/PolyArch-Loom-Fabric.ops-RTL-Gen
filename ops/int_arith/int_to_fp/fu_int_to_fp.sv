// fu_int_to_fp.sv -- Fabric FU for share group int_to_fp.
// op_list: arith.sitofp, arith.uitofp
//   op_sel = 0 -> out = f32(signed(a))     (arith.sitofp)
//   op_sel = 1 -> out = f32(unsigned(a))   (arith.uitofp)
//
// One shared int->IEEE-754-binary32 encoder; op_sel only selects the
// absolute-value preprocessor (signed vs unsigned). op_sel is a held config
// input. Unary op (one data input). Intrinsic latency 1 (registered output).
//
// Structural (leading-zero count -> normalize -> round-to-nearest-even). This
// DIVERGES from loom's behavioral $itor/$shortrealtobits model, which Verilator
// cannot simulate (shortreal unsupported). int32 never overflows f32 to Inf and
// never yields NaN/subnormals, so no special-case encoding is needed.
//
// NOTE: the encoder targets INT_WIDTH = 32 -> binary32 (FP_WIDTH = 32):
// 1 sign + 8 exponent (bias 127) + 23 mantissa.

module fu_int_to_fp #(
  parameter int unsigned INT_WIDTH = 32,
  parameter int unsigned FP_WIDTH  = 32
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  op_sel,       // 0 = arith.sitofp (signed), 1 = arith.uitofp (unsigned)

  input  logic [INT_WIDTH-1:0]  in_data_0,    // integer operand
  input  logic                  in_valid_0,
  output logic                  in_ready_0,

  output logic [FP_WIDTH-1:0]   out_data,     // IEEE-754 binary32 bits
  output logic                  out_valid,
  input  logic                  out_ready
);

  // Count leading zeros of a 32-bit value (0..31 for a nonzero input).
  function automatic logic [5:0] clz32(input logic [31:0] x);
    logic [5:0] n;
    logic       found;
    integer     i;
    begin : clz_body
      n     = 6'd0;
      found = 1'b0;
      for (i = 31; i >= 0; i = i - 1) begin : clz_loop
        if (!found) begin : clz_step
          if (x[i]) found = 1'b1;
          else      n     = n + 6'd1;
        end : clz_step
      end : clz_loop
      clz32 = n;
    end : clz_body
  endfunction

  // ---- combinational int -> binary32 conversion ----
  logic        sign;
  logic [31:0] mag;
  logic [5:0]  lz;
  // verilator lint_off UNUSEDSIGNAL
  logic [31:0] shifted;     // bit 31 is the implicit leading 1 (unused below)
  // verilator lint_on UNUSEDSIGNAL
  logic [22:0] frac;
  logic        guard, sticky, lsb, round_up;
  logic [23:0] mant24;
  logic [7:0]  exp8;
  logic [7:0]  exp_final;
  logic [22:0] mant_final;
  logic [31:0] conv_result;

  always_comb begin : convert
    // signedness preprocessor: op_sel=0 signed (abs), op_sel=1 unsigned
    if (op_sel == 1'b0) begin : as_signed
      sign = in_data_0[INT_WIDTH-1];
      mag  = in_data_0[INT_WIDTH-1] ? (~in_data_0 + 32'd1) : in_data_0;
    end : as_signed
    else begin : as_unsigned
      sign = 1'b0;
      mag  = in_data_0;
    end : as_unsigned

    // defaults (avoid latches)
    lz         = 6'd0;
    shifted    = 32'd0;
    frac       = 23'd0;
    lsb        = 1'b0;
    guard      = 1'b0;
    sticky     = 1'b0;
    round_up   = 1'b0;
    mant24     = 24'd0;
    exp8       = 8'd0;
    exp_final  = 8'd0;
    mant_final = 23'd0;

    if (mag == 32'd0) begin : zero_case
      conv_result = 32'h0000_0000;            // +0.0
    end : zero_case
    else begin : normal_case
      lz       = clz32(mag);
      shifted  = mag << lz;                    // leading 1 now at bit 31
      frac     = shifted[30:8];
      lsb      = shifted[8];
      guard    = shifted[7];
      sticky   = |shifted[6:0];
      round_up = guard & (sticky | lsb);       // round to nearest even
      mant24   = {1'b0, frac} + {23'd0, round_up};
      exp8     = 8'd158 - {2'd0, lz};           // (31 - lz) + 127
      if (mant24[23]) begin : round_overflow
        exp_final  = exp8 + 8'd1;
        mant_final = 23'd0;
      end : round_overflow
      else begin : no_overflow
        exp_final  = exp8;
        mant_final = mant24[22:0];
      end : no_overflow
      conv_result = {sign, exp_final, mant_final};
    end : normal_case
  end : convert

  // ---- latency-1 handshake (mirrors loom FP FU) ----
  logic fire;
  assign fire       = in_valid_0 & (~out_valid | out_ready);
  assign in_ready_0 = fire;

  always_ff @(posedge clk) begin : pipe_reg
    if (!rst_n) begin : pipe_rst
      out_valid <= 1'b0;
      out_data  <= {FP_WIDTH{1'b0}};
    end : pipe_rst
    else begin : pipe_upd
      if (fire) begin : pipe_fire
        out_data  <= conv_result;
        out_valid <= 1'b1;
      end : pipe_fire
      else if (out_ready) begin : pipe_drain
        out_valid <= 1'b0;
      end : pipe_drain
    end : pipe_upd
  end : pipe_reg

endmodule : fu_int_to_fp
