// fu_barrel_shift.sv -- Fabric FU for share group barrel_shift.
// op_list: arith.shli, arith.shrsi, arith.shrui
//   op_sel = 0 -> out = a << shamt          (arith.shli, logical left)
//   op_sel = 1 -> out = a >>> shamt (arith) (arith.shrsi, sign-fill right)
//   op_sel = 2 -> out = a >> shamt          (arith.shrui, logical right)
//   op_sel = 3 -> reserved (defaults to arith.shli)
//
// One shared barrel shifter; op_sel selects direction + arithmetic-vs-logical
// fill. op_sel is a held config input (no handshake). Combinational, latency 0.
//
// Shift amount = low log2(WIDTH) bits of operand B (RISC-V-style masking:
// shamt = b & (WIDTH-1); a shift of WIDTH wraps to 0). MLIR treats a shift
// amount >= WIDTH as poison, so this is a chosen deterministic behavior.
// Assumes WIDTH is a power of two.

module fu_barrel_shift #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]        op_sel,     // 0=arith.shli 1=arith.shrsi 2=arith.shrui

  input  logic [WIDTH-1:0]  in_data_0,  // value to shift (a)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,  // shift amount (b)
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

  // RISC-V-style shift-amount mask (full-width AND keeps every input bit read).
  logic [WIDTH-1:0] shamt;
  assign shamt = in_data_1 & WIDTH'(WIDTH - 1);

  // Shared barrel shifter: op_sel selects direction + fill.
  always_comb begin : shift_mux
    case (op_sel)
      2'd0:    out_data = in_data_0 << shamt;                       // shli  (logical left)
      2'd1:    out_data = $unsigned($signed(in_data_0) >>> shamt);  // shrsi (arithmetic right)
      2'd2:    out_data = in_data_0 >> shamt;                       // shrui (logical right)
      default: out_data = in_data_0 << shamt;                       // 2'd3 reserved -> shli
    endcase
  end : shift_mux

endmodule : fu_barrel_shift
