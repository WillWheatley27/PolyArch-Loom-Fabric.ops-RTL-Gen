// fu_min_max_unsigned.sv -- Fabric FU for share group min_max_unsigned.
// op_list: arith.minui, arith.maxui
//   op_sel = 0 -> out = unsigned-min(a, b)   (arith.minui)
//   op_sel = 1 -> out = unsigned-max(a, b)   (arith.maxui)
//
// One shared unsigned comparator; min vs max is a single output mux on the
// result. op_sel is a held config input (no handshake). Combinational, latency 0.
// No edge cases (unsigned min/max are total functions). Unsigned counterpart of
// fu_min_max_signed (comparator is unsigned -- no $signed).

module fu_min_max_unsigned #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,     // 0 = arith.minui (min), 1 = arith.maxui (max)

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

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // One shared unsigned comparator; op_sel selects min vs max as an output mux.
  logic a_lt_b;
  assign a_lt_b   = in_data_0 < in_data_1;
  assign out_data = op_sel ? (a_lt_b ? in_data_1 : in_data_0)   // maxui: larger operand
                           : (a_lt_b ? in_data_0 : in_data_1);  // minui: smaller operand

endmodule : fu_min_max_unsigned
