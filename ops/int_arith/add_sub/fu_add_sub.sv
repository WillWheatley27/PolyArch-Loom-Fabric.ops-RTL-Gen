// fu_add_sub.sv -- Fabric FU for share group add_sub.
// STUB: interface only, datapath intentionally wrong (replaced in Task 2).

module fu_add_sub #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,

  input  logic [WIDTH-1:0]  in_data_0,
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // verilator lint_off UNUSEDSIGNAL
  logic unused_op_sel;
  assign unused_op_sel = op_sel;
  // verilator lint_on UNUSEDSIGNAL
  assign out_data = {WIDTH{1'b0}};   // STUB wrong

endmodule : fu_add_sub
