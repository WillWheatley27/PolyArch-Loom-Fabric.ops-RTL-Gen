// tb_fu_min_max_unsigned.sv -- Self-checking testbench for fu_min_max_unsigned
// (share group 7). Combinational DUT: drive operands + op_sel, settle, compare
// to an independent golden model (unsigned min/max). Directed corners (ordered,
// ties, 0/UMAX, MSB-set vectors that distinguish unsigned from signed) +
// handshake corners + randomized. Parameterized by WIDTH (verilator -GWIDTH=8).
// Testbench only.

`timescale 1ns/1ps

module tb_fu_min_max_unsigned #(
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

  fu_min_max_unsigned #(.WIDTH(WIDTH)) dut (
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

  // Independent golden model (unsigned min/max).
  function automatic logic [WIDTH-1:0] golden(input logic [WIDTH-1:0] a,
                                              input logic [WIDTH-1:0] b,
                                              input logic             sel);
    logic lt;
    begin : golden_body
      lt = a < b;   // unsigned
      // sel=0 -> minui (smaller); sel=1 -> maxui (larger)
      golden = sel ? (lt ? b : a) : (lt ? a : b);
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

  logic [WIDTH-1:0] UMAX, MSB;

  initial begin : main
    integer           iter_var0;
    logic [WIDTH-1:0] ra, rb;
    logic [31:0]      rt0, rt1, rts;
    logic             rs;

    UMAX = {WIDTH{1'b1}};
    MSB  = {1'b1, {(WIDTH-1){1'b0}}};

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Ordered pairs (both taps)
    check_vec(WIDTH'(5),  WIDTH'(3),  1'b0); // min = 3
    check_vec(WIDTH'(5),  WIDTH'(3),  1'b1); // max = 5
    check_vec(WIDTH'(3),  WIDTH'(5),  1'b0); // min = 3
    check_vec(WIDTH'(3),  WIDTH'(5),  1'b1); // max = 5

    // Extremes
    check_vec(WIDTH'(0),  UMAX,       1'b0); // min = 0
    check_vec(WIDTH'(0),  UMAX,       1'b1); // max = UMAX
    check_vec(UMAX,       WIDTH'(0),  1'b0); // min = 0
    check_vec(UMAX,       UMAX,       1'b1); // UMAX

    // Ties
    check_vec(WIDTH'(7),  WIDTH'(7),  1'b0); // 7
    check_vec(WIDTH'(7),  WIDTH'(7),  1'b1); // 7

    // MSB-set: as UNSIGNED, MSB (0x80..0) is the LARGEST, not smallest.
    // (A signed-compare bug would flip these.)
    check_vec(MSB,        WIDTH'(1),  1'b0); // minui = 1
    check_vec(MSB,        WIDTH'(1),  1'b1); // maxui = MSB
    check_vec(MSB,        UMAX,       1'b0); // minui = MSB
    check_vec(MSB,        UMAX,       1'b1); // maxui = UMAX

    // op_sel toggle on identical operands
    check_vec(MSB, WIDTH'(4), 1'b0);
    check_vec(MSB, WIDTH'(4), 1'b1);

    // Handshake corners
    check_backpressure(WIDTH'(5), WIDTH'(3), 1'b0);
    check_input_invalid();

    // Randomized (op_sel in {0,1})
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rt0 = $random; rt1 = $random; rts = $random;
      ra = WIDTH'(rt0); rb = WIDTH'(rt1); rs = rts[0];
      check_vec(ra, rb, rs);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_min_max_unsigned WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_min_max_unsigned WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_min_max_unsigned
