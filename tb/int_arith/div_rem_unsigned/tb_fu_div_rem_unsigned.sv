// tb_fu_div_rem_unsigned.sv -- Self-checking testbench for fu_div_rem_unsigned
// (share group 3). Multi-cycle DUT: drive operands + op_sel, accept handshake,
// wait for out_valid, compare to an independent golden model (native unsigned
// / and %, with the RISC-V divide-by-zero result substituted). Operands are
// scrambled after accept to confirm the DUT captured them. Directed corners +
// handshake corners + randomized. Parameterized by WIDTH (verilator -GWIDTH=8).
// Testbench only.

`timescale 1ns/1ps

module tb_fu_div_rem_unsigned #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 5000
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

  fu_div_rem_unsigned #(.WIDTH(WIDTH)) dut (
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

  // Independent golden model (unsigned).
  function automatic logic [WIDTH-1:0] golden(input logic [WIDTH-1:0] a,
                                              input logic [WIDTH-1:0] b,
                                              input logic             sel);
    logic [WIDTH-1:0] q, r;
    begin : golden_body
      if (b == {WIDTH{1'b0}}) begin : by_zero
        q = {WIDTH{1'b1}};   // RISC-V: quotient = all-ones (max unsigned)
        r = a;               // RISC-V: remainder = dividend
      end : by_zero
      else begin : normal
        q = a / b;           // unsigned division
        r = a % b;           // unsigned remainder
      end : normal
      golden = sel ? r : q;
    end : golden_body
  endfunction

  // Drive one operation through the full handshake and check the result.
  task automatic run_one(input logic [WIDTH-1:0] a,
                         input logic [WIDTH-1:0] b,
                         input logic             sel);
    logic [WIDTH-1:0] exp;
    integer           guard;
    begin : run_one_body
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = sel;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;

      // In ST_IDLE with both operands valid, in_ready must be asserted.
      #1;  // settle combinational in_ready before sampling
      if (in_ready_0 !== 1'b1 || in_ready_1 !== 1'b1) begin : ready_low
        $display("FAIL accept: in_ready low while idle+valid (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : ready_low

      @(posedge clk);            // operands captured on this edge
      @(negedge clk);
      in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      in_data_0  = ~a;  in_data_1  = ~b;   // scramble: result must not change

      guard = 0;
      while (out_valid !== 1'b1) begin : wait_done
        @(negedge clk);
        guard = guard + 1;
        if (guard > (WIDTH + 10)) begin : timeout
          $display("FAIL timeout: out_valid never asserted (a=%h b=%h)", a, b);
          error_count = error_count + 1;
          $finish;
        end : timeout
      end : wait_done

      exp = golden(a, b, sel);
      if (out_data !== exp) begin : data_mismatch
        $display("FAIL data: op_sel=%0b a=%h b=%h got=%h exp=%h", sel, a, b, out_data, exp);
        error_count = error_count + 1;
      end : data_mismatch

      @(posedge clk);            // out_ready high -> ST_DONE -> ST_IDLE
    end : run_one_body
  endtask

  // Backpressure: hold out_ready low in ST_DONE; out_valid/out_data must hold
  // and in_ready must stay low.
  task automatic check_backpressure(input logic [WIDTH-1:0] a,
                                    input logic [WIDTH-1:0] b,
                                    input logic             sel);
    logic [WIDTH-1:0] exp;
    integer           guard;
    integer           i;
    begin : bp_body
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = sel;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;  // never drain
      @(posedge clk);
      @(negedge clk);
      in_valid_0 = 1'b0; in_valid_1 = 1'b0;

      guard = 0;
      while (out_valid !== 1'b1) begin : wait_done
        @(negedge clk);
        guard = guard + 1;
        if (guard > (WIDTH + 10)) begin : timeout
          $display("FAIL bp timeout (a=%h b=%h)", a, b);
          error_count = error_count + 1;
          $finish;
        end : timeout
      end : wait_done

      exp = golden(a, b, sel);
      for (i = 0; i < 3; i = i + 1) begin : hold_loop
        @(negedge clk);
        if (out_valid !== 1'b1) begin : v_drop
          $display("FAIL bp: out_valid dropped while out_ready=0");
          error_count = error_count + 1;
        end : v_drop
        if (out_data !== exp) begin : d_change
          $display("FAIL bp: out_data changed while out_ready=0 (got=%h exp=%h)", out_data, exp);
          error_count = error_count + 1;
        end : d_change
        if (in_ready_0 !== 1'b0 || in_ready_1 !== 1'b0) begin : r_high
          $display("FAIL bp: in_ready high while busy/done");
          error_count = error_count + 1;
        end : r_high
      end : hold_loop

      @(negedge clk); out_ready = 1'b1;
      @(posedge clk);            // drain -> ST_IDLE
    end : bp_body
  endtask

  // No accept while an operand is invalid.
  task automatic check_no_accept;
    begin : na_body
      @(negedge clk);
      in_data_0 = '0; in_data_1 = '0; op_sel = 1'b0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1;
      @(negedge clk);
      if (out_valid !== 1'b0) begin : v_high
        $display("FAIL: out_valid high without accept");
        error_count = error_count + 1;
      end : v_high
      if (in_ready_0 !== 1'b0 || in_ready_1 !== 1'b0) begin : r_high
        $display("FAIL: in_ready high while in_valid_0 low");
        error_count = error_count + 1;
      end : r_high
      in_valid_1 = 1'b0;
    end : na_body
  endtask

  logic [WIDTH-1:0] UMAX;

  initial begin : main
    integer           iter_var0;
    logic [WIDTH-1:0] ra, rb;
    logic [31:0]      rt0, rt1, rts;
    logic             rs;

    UMAX = {WIDTH{1'b1}};

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Directed: normal division
    run_one(WIDTH'(7),   WIDTH'(3),  1'b0);  // 7 / 3 = 2
    run_one(WIDTH'(7),   WIDTH'(3),  1'b1);  // 7 % 3 = 1
    run_one(WIDTH'(5),   WIDTH'(10), 1'b0);  // 0
    run_one(WIDTH'(5),   WIDTH'(10), 1'b1);  // 5
    run_one(WIDTH'(100), WIDTH'(7),  1'b0);  // 14
    run_one(WIDTH'(100), WIDTH'(7),  1'b1);  // 2

    // Max-unsigned corners
    run_one(UMAX, WIDTH'(1), 1'b0);          // UMAX
    run_one(UMAX, WIDTH'(1), 1'b1);          // 0
    run_one(UMAX, UMAX,      1'b0);          // 1
    run_one(UMAX, UMAX,      1'b1);          // 0
    run_one(UMAX, WIDTH'(2), 1'b0);          // UMAX >> 1
    run_one(UMAX, WIDTH'(2), 1'b1);          // 1
    run_one(WIDTH'(0), WIDTH'(5), 1'b0);     // 0
    run_one(WIDTH'(0), WIDTH'(5), 1'b1);     // 0

    // Divide-by-zero (RISC-V): q = all-ones, r = dividend
    run_one(WIDTH'(0),  WIDTH'(0), 1'b0);    // UMAX
    run_one(WIDTH'(0),  WIDTH'(0), 1'b1);    // 0
    run_one(WIDTH'(5),  WIDTH'(0), 1'b0);    // UMAX
    run_one(WIDTH'(5),  WIDTH'(0), 1'b1);    // 5
    run_one(UMAX,       WIDTH'(0), 1'b1);    // UMAX (dividend)

    // Handshake corners
    check_backpressure(WIDTH'(7), WIDTH'(2), 1'b0);
    check_backpressure(WIDTH'(9), WIDTH'(4), 1'b1);
    check_no_accept();

    // Randomized
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rt0 = $random; rt1 = $random; rts = $random;
      ra = WIDTH'(rt0); rb = WIDTH'(rt1); rs = rts[0];
      run_one(ra, rb, rs);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_div_rem_unsigned WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_div_rem_unsigned WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_div_rem_unsigned
