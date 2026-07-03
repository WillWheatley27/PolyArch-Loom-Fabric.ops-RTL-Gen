// fu_fp_min_max.sv -- Fabric FU for share group fp_min_max.
// op_list: arith.minimumf, arith.maximumf
//   op_sel = 0 -> out = minimumf(a, b)   (arith.minimumf)
//   op_sel = 1 -> out = maximumf(a, b)   (arith.maximumf)
//
// One shared FP comparator; op_sel selects min vs max as an output mux. op_sel is
// a held config input. Combinational, latency 0.
//
// PARAMETERIZED IEEE-754 format via (EXP_W, MANT_W): fp32 (8,23) default,
// fp64 (11,52), bf16 (8,7). All field slices and constants derive from the params.
//
// IEEE-754-2019 minimum/maximum: NaN-propagating (either NaN -> NaN), and
// -0.0 < +0.0. The result is one input operand returned VERBATIM (no arithmetic,
// no rounding, no FTZ) -- subnormals and Inf pass through; only NaN is special.
//
// Total order via a monotonic unsigned key: negatives inverted, others sign-flipped.

module fu_fp_min_max #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,     // 0 = arith.minimumf (min), 1 = arith.maximumf (max)

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

  // Quiet NaN for this format: sign 0, exponent all ones, mantissa MSB set.
  localparam logic [WIDTH-1:0] QNAN = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // NaN detection: exponent field all ones AND mantissa nonzero.
  logic a_nan, b_nan;
  assign a_nan = (&in_data_0[WIDTH-2:MANT_W]) & (|in_data_0[MANT_W-1:0]);
  assign b_nan = (&in_data_1[WIDTH-2:MANT_W]) & (|in_data_1[MANT_W-1:0]);

  // Monotonic unsigned key -> one unsigned compare gives the IEEE total order,
  // including -0 < +0 and -Inf < ... < +Inf.
  logic [WIDTH-1:0] key_a, key_b;
  logic             a_lt_b;
  assign key_a  = in_data_0 ^ (in_data_0[WIDTH-1] ? {WIDTH{1'b1}} : {1'b1, {(WIDTH-1){1'b0}}});
  assign key_b  = in_data_1 ^ (in_data_1[WIDTH-1] ? {WIDTH{1'b1}} : {1'b1, {(WIDTH-1){1'b0}}});
  assign a_lt_b = key_a < key_b;

  // NaN-propagating; op_sel selects min vs max as an output mux.
  assign out_data = (a_nan | b_nan) ? QNAN
                  : op_sel ? (a_lt_b ? in_data_1 : in_data_0)   // maximumf
                           : (a_lt_b ? in_data_0 : in_data_1);  // minimumf

endmodule : fu_fp_min_max
