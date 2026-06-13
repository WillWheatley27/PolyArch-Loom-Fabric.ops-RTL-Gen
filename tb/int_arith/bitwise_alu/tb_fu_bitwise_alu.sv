// tb_fu_bitwise_alu.sv -- Self-checking testbench for fu_bitwise_alu
// (share group 5). Combinational DUT: drive operands + 2-bit op_sel, settle,
// compare to an independent golden model (native &, |, ^). Directed corners +
// handshake corners + randomized. Parameterized by WIDTH (verilator -GWIDTH=8).
// Testbench only.

`timescale 1ns/1ps

module tb_fu_bitwise_alu #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 10000
);

  logic              clk;
  logic              rst_n;
  logic [1:0]        op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1;
  logic              in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_bitwise_alu #(.WIDTH(WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  // Independent golden model.
  function automatic logic [WIDTH-1:0] golden(input logic [WIDTH-1:0] a,
                                              input logic [WIDTH-1:0] b,
                                              input logic [1:0]       op);
    begin : golden_body
      case (op)
        2'd0:    golden = a & b;
        2'd1:    golden = a | b;
        2'd2:    golden = a ^ b;
        default: golden = a & b;
      endcase
    end : golden_body
  endfunction

  task automatic check_vec(input logic [WIDTH-1:0] a,
                           input logic [WIDTH-1:0] b,
                           input logic [1:0]       op);
    logic [WIDTH-1:0] exp;
    begin : check_vec_body
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(a, b, op);
      if (out_data !== exp) begin : data_mismatch
        $display("FAIL data: op_sel=%0d a=%h b=%h got=%h exp=%h", op, a, b, out_data, exp);
        error_count = error_count + 1;
      end : data_mismatch
      if (out_valid !== 1'b1) begin : valid_low
        $display("FAIL out_valid low with both operands valid (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : valid_low
      if ((in_ready_0 !== 1'b1) || (in_ready_1 !== 1'b1)) begin : ready_low
        $display("FAIL in_ready low with out_ready & out_valid high (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : ready_low
    end : check_vec_body
  endtask

  task automatic check_backpressure(input logic [WIDTH-1:0] a,
                                    input logic [WIDTH-1:0] b,
                                    input logic [1:0]       op);
    begin : check_bp_body
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      #1;
      if (out_valid !== 1'b1) begin : bp_valid
        $display("FAIL backpressure: out_valid must stay high (indep of out_ready)");
        error_count = error_count + 1;
      end : bp_valid
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin : bp_ready
        $display("FAIL backpressure: in_ready must be low when out_ready=0");
        error_count = error_count + 1;
      end : bp_ready
    end : check_bp_body
  endtask

  task automatic check_input_invalid;
    begin : check_inv_body
      op_sel = 2'd0; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : inv_valid
        $display("FAIL: out_valid high when in_valid_0 low");
        error_count = error_count + 1;
      end : inv_valid
      if (in_ready_1 !== 1'b0) begin : inv_ready
        $display("FAIL: in_ready_1 high when join incomplete");
        error_count = error_count + 1;
      end : inv_ready
    end : check_inv_body
  endtask

  logic [WIDTH-1:0] ZERO, ALLONES, AAAA, FIVE5;

  initial begin : main
    integer           iter_var0;
    logic [WIDTH-1:0] ra, rb;
    logic [31:0]      rt0, rt1, rts;
    logic [1:0]       rop;

    ZERO    = {WIDTH{1'b0}};
    ALLONES = {WIDTH{1'b1}};
    AAAA    = {(WIDTH/2){2'b10}};   // 1010...10
    FIVE5   = {(WIDTH/2){2'b01}};   // 0101...01

    error_count = 0;
    op_sel = 2'd0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // andi (op_sel = 0)
    check_vec(ALLONES, ALLONES, 2'd0); // all ones
    check_vec(ALLONES, ZERO,    2'd0); // 0 (annihilator)
    check_vec(AAAA,    FIVE5,   2'd0); // 0 (disjoint bits)
    check_vec(AAAA,    AAAA,    2'd0); // idempotent -> AAAA
    check_vec(WIDTH'(7), WIDTH'(3), 2'd0); // 3

    // ori (op_sel = 1)
    check_vec(ZERO,    ALLONES, 2'd1); // all ones
    check_vec(ZERO,    ZERO,    2'd1); // 0
    check_vec(AAAA,    FIVE5,   2'd1); // all ones (complementary)
    check_vec(WIDTH'(7), WIDTH'(3), 2'd1); // 7

    // xori (op_sel = 2)
    check_vec(ALLONES, ALLONES, 2'd2); // 0 (self-inverse)
    check_vec(ALLONES, ZERO,    2'd2); // all ones
    check_vec(AAAA,    AAAA,    2'd2); // 0
    check_vec(AAAA,    FIVE5,   2'd2); // all ones
    check_vec(WIDTH'(7), WIDTH'(3), 2'd2); // 4

    // op_sel toggle on identical operands
    check_vec(AAAA, FIVE5, 2'd0);
    check_vec(AAAA, FIVE5, 2'd1);
    check_vec(AAAA, FIVE5, 2'd2);

    // Handshake corners
    check_backpressure(AAAA, FIVE5, 2'd1);
    check_input_invalid();

    // Randomized (op_sel in {0,1,2})
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rt0 = $random; rt1 = $random; rts = $random;
      ra = WIDTH'(rt0); rb = WIDTH'(rt1);
      rop = rts[1:0];
      if (rop == 2'd3) rop = 2'd0;
      check_vec(ra, rb, rop);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_bitwise_alu WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_bitwise_alu WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_bitwise_alu
