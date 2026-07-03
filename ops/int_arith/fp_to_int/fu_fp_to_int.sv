// fu_fp_to_int.sv -- Fabric FU for share group fp_to_int.
// op_list: arith.fptosi, arith.fptoui
//   op_sel = 0 -> out = signed-int(a)     (arith.fptosi)
//   op_sel = 1 -> out = unsigned-int(a)   (arith.fptoui)
//
// One shared IEEE-754 -> integer extractor; op_sel selects signed vs unsigned
// post-processing. Truncates toward zero. op_sel is a held config input. Unary
// op. Intrinsic latency 1 (registered output).
//
// PARAMETERIZED: (EXP_W, MANT_W) float -> INT_WIDTH integer. fp32 (8,23) default,
// fp64 (11,52), bf16 (8,7); INT_WIDTH independent (e.g. 32 or 64). Structural
// (decode exponent/mantissa -> shift -> truncate). Out-of-range / NaN / Inf use
// RISC-V FCVT saturation:
//   fptosi: NaN/+overflow -> INT_MAX; -overflow/-Inf -> INT_MIN.
//   fptoui: NaN/+overflow -> UINT_MAX; negative -> 0.

module fu_fp_to_int #(
  parameter  int unsigned EXP_W     = 8,
  parameter  int unsigned MANT_W    = 23,
  parameter  int unsigned INT_WIDTH = 32,
  localparam int unsigned FP_WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned BIAS      = (1 << (EXP_W - 1)) - 1
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  op_sel,       // 0 = arith.fptosi (signed), 1 = arith.fptoui (unsigned)

  input  logic [FP_WIDTH-1:0]   in_data_0,    // IEEE-754 float bits
  input  logic                  in_valid_0,
  output logic                  in_ready_0,

  output logic [INT_WIDTH-1:0]  out_data,     // integer result
  output logic                  out_valid,
  input  logic                  out_ready
);

  localparam logic [INT_WIDTH-1:0] INT_MAX  = {1'b0, {(INT_WIDTH-1){1'b1}}};
  localparam logic [INT_WIDTH-1:0] INT_MIN  = {1'b1, {(INT_WIDTH-1){1'b0}}};
  localparam logic [INT_WIDTH-1:0] UINT_MAX = {INT_WIDTH{1'b1}};

  logic                 sign, all_ones, is_nan;
  logic [EXP_W-1:0]     exp;
  logic [MANT_W-1:0]    mant;
  logic [MANT_W:0]      signif;
  logic [31:0]          eint;          // unbiased exponent E = exp - BIAS (E >= 0 path)
  logic [INT_WIDTH-1:0] mag;           // truncated integer magnitude
  logic [INT_WIDTH-1:0] result;

  always_comb begin : convert
    sign     = in_data_0[FP_WIDTH-1];
    exp      = in_data_0[FP_WIDTH-2:MANT_W];
    mant     = in_data_0[MANT_W-1:0];
    signif   = {1'b1, mant};
    all_ones = &exp;
    is_nan   = all_ones & (|mant);

    // truncated magnitude (right shift drops fractional bits = toward zero)
    if (32'(exp) < 32'(BIAS)) begin
      eint = 32'd0;
      mag  = '0;
    end else begin
      eint = 32'(exp) - 32'(BIAS);
      if (eint >= MANT_W) mag = INT_WIDTH'(signif) << (eint - MANT_W);
      else                mag = INT_WIDTH'(signif >> (MANT_W - eint));
    end

    result = '0;
    if (op_sel == 1'b0) begin : to_signed
      if (is_nan)                    result = INT_MAX;                    // NaN -> INT_MAX
      else if (all_ones)             result = sign ? INT_MIN : INT_MAX;   // +/-Inf
      else if (32'(exp) < 32'(BIAS)) result = '0;                         // |v| < 1
      else if (eint >= INT_WIDTH-1)  result = sign ? INT_MIN : INT_MAX;   // overflow
      else                           result = sign ? (-mag) : mag;
    end : to_signed
    else begin : to_unsigned
      if (is_nan)                    result = UINT_MAX;                   // NaN -> UINT_MAX
      else if (sign)                 result = '0;                         // negative -> 0
      else if (all_ones)             result = UINT_MAX;                   // +Inf
      else if (32'(exp) < 32'(BIAS)) result = '0;                         // |v| < 1
      else if (eint >= INT_WIDTH)    result = UINT_MAX;                   // overflow
      else                           result = mag;
    end : to_unsigned
  end : convert

  // ---- latency-1 handshake ----
  logic fire;
  assign fire       = in_valid_0 & (~out_valid | out_ready);
  assign in_ready_0 = fire;

  always_ff @(posedge clk) begin : pipe_reg
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_data  <= {INT_WIDTH{1'b0}};
    end else begin
      if (fire) begin
        out_data  <= result;
        out_valid <= 1'b1;
      end else if (out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end : pipe_reg

endmodule : fu_fp_to_int
