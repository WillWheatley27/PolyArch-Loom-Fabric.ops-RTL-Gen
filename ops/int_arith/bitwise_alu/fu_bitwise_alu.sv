// fu_bitwise_alu.sv -- Fabric FU for share group bitwise_alu.
// op_list: arith.andi, arith.ori, arith.xori
//   op_sel = 0 -> out = a & b   (arith.andi)
//   op_sel = 1 -> out = a | b   (arith.ori)
//   op_sel = 2 -> out = a ^ b   (arith.xori)
//   op_sel = 3 -> reserved (defaults to arith.andi)
//
// One shared bit-wise ALU; op_sel selects the per-bit function. op_sel is a held
// config input (no handshake). Combinational, latency 0. No edge cases (bit-wise
// ops are total functions).

module fu_bitwise_alu #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]        op_sel,     // 0=arith.andi 1=arith.ori 2=arith.xori

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

  // Shared bit-wise ALU: op_sel selects the per-bit function.
  always_comb begin : alu_mux
    case (op_sel)
      2'd0:    out_data = in_data_0 & in_data_1;   // andi
      2'd1:    out_data = in_data_0 | in_data_1;   // ori
      2'd2:    out_data = in_data_0 ^ in_data_1;   // xori
      default: out_data = in_data_0 & in_data_1;   // 2'd3 reserved -> andi
    endcase
  end : alu_mux

endmodule : fu_bitwise_alu
