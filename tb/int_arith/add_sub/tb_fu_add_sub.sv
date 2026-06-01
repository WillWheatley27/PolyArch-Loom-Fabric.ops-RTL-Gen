// tb_fu_add_sub.sv -- Self-checking testbench for fu_add_sub (share group 1).
// Combinational DUT: drive operands + op_sel, settle, compare to an independent
// golden model (uses +/- directly). Directed corners + randomized. Parameterized
// by WIDTH; override per run (verilator -GWIDTH=8, VCS -pvalue+...WIDTH=8).
// Testbench only.

`timescale 1ns/1ps

module tb_fu_add_sub #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 10000
);

  logic              clk;
  logic              rst_n;
  logic              op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1;
  logic              in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_add_sub #(.WIDTH(WIDTH)) dut (
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

  function automatic logic [WIDTH-1:0] golden(input logic [WIDTH-1:0] a,
                                              input logic [WIDTH-1:0] b,
                                              input logic             sel);
    begin : golden_body
      golden = sel ? (a - b) : (a + b);
    end : golden_body
  endfunction

  task automatic check_vec(input logic [WIDTH-1:0] a,
                           input logic [WIDTH-1:0] b,
                           input logic             sel);
    logic [WIDTH-1:0] exp;
    begin : check_vec_body
      op_sel = sel; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(a, b, sel);
      if (out_data !== exp) begin : data_mismatch
        $display("FAIL data: op_sel=%0b a=%h b=%h got=%h exp=%h", sel, a, b, out_data, exp);
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
                                    input logic             sel);
    begin : check_bp_body
      op_sel = sel; in_data_0 = a; in_data_1 = b;
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
      op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
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

  initial begin : main
    integer            iter_var0;
    logic [WIDTH-1:0]  ra, rb;
    logic [31:0]       rt0, rt1, rts;
    logic              rs;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Directed: addition (op_sel = 0)
    check_vec({WIDTH{1'b0}},             {WIDTH{1'b0}}, 1'b0); // 0 + 0
    check_vec({WIDTH{1'b1}},             {WIDTH{1'b0}}, 1'b0); // a + 0
    check_vec({{(WIDTH-1){1'b0}}, 1'b1}, {WIDTH{1'b1}}, 1'b0); // 1 + max -> wrap
    check_vec({WIDTH{1'b1}},             {WIDTH{1'b1}}, 1'b0); // max + max

    // Directed: subtraction (op_sel = 1)
    check_vec(WIDTH'(32'd5), WIDTH'(32'd3),             1'b1); // 5 - 3
    check_vec(WIDTH'(32'd3), WIDTH'(32'd5),             1'b1); // 3 - 5 -> wrap
    check_vec({WIDTH{1'b0}}, {{(WIDTH-1){1'b0}}, 1'b1}, 1'b1); // 0 - 1 -> all ones
    check_vec({1'b1, {(WIDTH-1){1'b0}}}, {{(WIDTH-1){1'b0}}, 1'b1}, 1'b1); // min - 1
    check_vec({WIDTH{1'b1}}, {WIDTH{1'b1}},            1'b1); // a - a -> 0

    // op_sel toggle on identical operands
    check_vec(WIDTH'(32'hDEAD_BEEF), WIDTH'(32'h0000_0001), 1'b0);
    check_vec(WIDTH'(32'hDEAD_BEEF), WIDTH'(32'h0000_0001), 1'b1);

    // Handshake corners
    check_backpressure(WIDTH'(32'd7), WIDTH'(32'd2), 1'b0);
    check_input_invalid();

    // Randomized
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rt0 = $random; rt1 = $random; rts = $random;
      ra = WIDTH'(rt0); rb = WIDTH'(rt1); rs = rts[0];
      check_vec(ra, rb, rs);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_add_sub WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_add_sub WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_add_sub
