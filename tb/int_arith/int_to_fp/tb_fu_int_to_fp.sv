// tb_fu_int_to_fp.sv -- Self-checking testbench for fu_int_to_fp (share group 8).
// Unary, latency-1 DUT (int32 -> IEEE-754 binary32). Three layers:
//   1. Directed exact vectors with hand-computed binary32 bit patterns.
//   2. Randomized correct-rounding property: decode the DUT's f32 output to real
//      and require |decoded - true_value| <= half_ULP (independent real math; no
//      shortreal, no DPI). Exact because all quantities are dyadic.
//   3. Handshake corners: latency-1 timing, backpressure, no-accept.
// INT_WIDTH=32 -> binary32 (FP is format-specific; no width sweep). TB only.

`timescale 1ns/1ps

module tb_fu_int_to_fp #(
  parameter int unsigned INT_WIDTH = 32,
  parameter int unsigned NRAND     = 5000
);

  logic              clk;
  logic              rst_n;
  logic              op_sel;
  logic [INT_WIDTH-1:0] in_data_0;
  logic              in_valid_0;
  logic              in_ready_0;
  logic [31:0]       out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_int_to_fp #(.INT_WIDTH(INT_WIDTH), .FP_WIDTH(32)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  // Decode IEEE-754 binary32 bits to a real (exact; our results are 0 or normal).
  function automatic real decode_f32(input logic [31:0] b);
    logic        s;
    logic [7:0]  e;
    logic [22:0] m;
    real         val, p;
    integer      k;
    begin : dec
      s = b[31]; e = b[30:23]; m = b[22:0];
      if (e == 8'd0) begin : is_zero
        val = 0.0;
      end : is_zero
      else begin : is_normal
        p = 1.0;
        if (int'(e) >= 127) begin : pos_exp
          for (k = 0; k < (int'(e) - 127); k = k + 1) p = p * 2.0;
        end : pos_exp
        else begin : neg_exp
          for (k = 0; k < (127 - int'(e)); k = k + 1) p = p / 2.0;
        end : neg_exp
        val = (1.0 + real'(m) / 8388608.0) * p;   // 8388608 = 2^23
      end : is_normal
      decode_f32 = s ? -val : val;
    end : dec
  endfunction

  // Drive one value through the latency-1 pipe and return the registered output.
  task automatic drive_get(input logic [31:0] x, input logic op, output logic [31:0] result);
    begin : dg
      @(negedge clk);
      in_data_0  = x[INT_WIDTH-1:0];
      op_sel     = op;
      in_valid_0 = 1'b1;
      out_ready  = 1'b1;
      @(posedge clk);            // fire -> register conversion
      @(negedge clk);
      in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin : lat_fail
        $display("FAIL latency: out_valid not high 1 cycle after fire (x=%h op=%0b)", x, op);
        error_count = error_count + 1;
      end : lat_fail
      result = out_data;
      @(posedge clk);            // drain
    end : dg
  endtask

  // Directed: compare to a hand-computed exact bit pattern.
  task automatic check_exact(input logic [31:0] x, input logic op, input logic [31:0] exp);
    logic [31:0] got;
    begin : ce
      drive_get(x, op, got);
      if (got !== exp) begin : mm
        $display("FAIL exact: op=%0b x=%h got=%h exp=%h", op, x, got, exp);
        error_count = error_count + 1;
      end : mm
    end : ce
  endtask

  // Random: correct-rounding property |decoded - true| <= half_ULP.
  task automatic check_prop(input logic [31:0] x, input logic op);
    logic [31:0]       got;
    logic [31:0]       magv;
    longint unsigned   xu;
    real               true_val, dec, half_ulp, diff, pmsb;
    integer            msb, k;
    begin : cp
      drive_get(x, op, got);
      magv = op ? x : (x[31] ? (~x + 32'd1) : x);
      if (magv == 32'd0) begin : zero_chk
        if (got !== 32'h0000_0000) begin
          $display("FAIL prop zero: x=%h op=%0b got=%h", x, op, got);
          error_count = error_count + 1;
        end
      end : zero_chk
      else begin : prop_chk
        xu       = {32'h0, x};
        true_val = op ? real'(xu) : real'($signed(x));
        msb = 0;
        for (k = 0; k < 32; k = k + 1) if (magv[k]) msb = k;
        pmsb = 1.0;
        for (k = 0; k < msb; k = k + 1) pmsb = pmsb * 2.0;
        half_ulp = pmsb / 16777216.0;          // 2^(msb-24)
        dec  = decode_f32(got);
        diff = dec - true_val;
        if (diff < 0.0) diff = -diff;
        if (diff > half_ulp) begin : prop_fail
          $display("FAIL prop: x=%h op=%0b got=%h dec=%f true=%f diff=%e ulp/2=%e",
                   x, op, got, dec, true_val, diff, half_ulp);
          error_count = error_count + 1;
        end : prop_fail
      end : prop_chk
    end : cp
  endtask

  // No accept while input invalid; output stays idle.
  task automatic check_no_accept;
    begin : na
      @(negedge clk); in_valid_0 = 1'b0; out_ready = 1'b1;
      @(negedge clk);
      if (out_valid !== 1'b0) begin
        $display("FAIL: out_valid high with no input"); error_count = error_count + 1;
      end
      if (in_ready_0 !== 1'b0) begin
        $display("FAIL: in_ready high with in_valid low"); error_count = error_count + 1;
      end
    end : na
  endtask

  // Backpressure: full output (out_valid=1) with out_ready=0 must hold value and
  // refuse new input (in_ready=0).
  task automatic check_backpressure;
    logic [31:0] held;
    integer      r;
    begin : bp
      @(negedge clk);
      in_data_0 = 32'd5; op_sel = 1'b0; in_valid_0 = 1'b1; out_ready = 1'b0;
      @(posedge clk);             // out_valid=0 initially -> fire -> capture
      @(negedge clk);
      in_data_0 = 32'd9;          // a new input waiting (in_valid_0 still 1)
      if (out_valid !== 1'b1) begin
        $display("FAIL bp: out_valid not set after fire"); error_count = error_count + 1;
      end
      held = out_data;
      for (r = 0; r < 3; r = r + 1) begin : hold_loop
        @(negedge clk);
        if (out_valid !== 1'b1) begin
          $display("FAIL bp: out_valid dropped while stalled"); error_count = error_count + 1;
        end
        if (out_data !== held) begin
          $display("FAIL bp: out_data changed while stalled"); error_count = error_count + 1;
        end
        if (in_ready_0 !== 1'b0) begin
          $display("FAIL bp: in_ready high while full and stalled"); error_count = error_count + 1;
        end
      end : hold_loop
      @(negedge clk); out_ready = 1'b1; in_valid_0 = 1'b0;
      @(posedge clk);             // drain
    end : bp
  endtask

  initial begin : main
    integer       iter_var0;
    logic [31:0]  rx;
    logic [31:0]  ro;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;
    @(posedge clk);

    // ---- Directed exact (hand-computed binary32) ----
    check_exact(32'h00000000, 1'b0, 32'h00000000); // sitofp(0)  = +0.0
    check_exact(32'h00000000, 1'b1, 32'h00000000); // uitofp(0)  = +0.0
    check_exact(32'h00000001, 1'b0, 32'h3F800000); // sitofp(1)  = 1.0
    check_exact(32'h00000001, 1'b1, 32'h3F800000); // uitofp(1)  = 1.0
    check_exact(32'hFFFFFFFF, 1'b0, 32'hBF800000); // sitofp(-1) = -1.0
    check_exact(32'h00000002, 1'b0, 32'h40000000); // sitofp(2)  = 2.0
    check_exact(32'hFFFFFFFE, 1'b0, 32'hC0000000); // sitofp(-2) = -2.0
    check_exact(32'h00000005, 1'b0, 32'h40A00000); // sitofp(5)  = 5.0
    check_exact(32'hFFFFFFFB, 1'b0, 32'hC0A00000); // sitofp(-5) = -5.0
    check_exact(32'h00800000, 1'b1, 32'h4B000000); // uitofp(2^23)
    check_exact(32'h01000000, 1'b1, 32'h4B800000); // uitofp(2^24)
    check_exact(32'h01000001, 1'b1, 32'h4B800000); // uitofp(2^24+1) RNE -> 2^24 (tie to even)
    check_exact(32'h01000003, 1'b1, 32'h4B800002); // uitofp(2^24+3) RNE -> 2^24+4 (tie to even)
    check_exact(32'h80000000, 1'b0, 32'hCF000000); // sitofp(INT_MIN = -2^31)
    check_exact(32'h80000000, 1'b1, 32'h4F000000); // uitofp(2^31)
    check_exact(32'h7FFFFFFF, 1'b1, 32'h4F000000); // uitofp(2^31-1) RNE -> 2^31
    check_exact(32'hFFFFFFFF, 1'b1, 32'h4F800000); // uitofp(2^32-1) RNE -> 2^32
    check_exact(32'h7FFFFFFF, 1'b0, 32'h4F000000); // sitofp(INT_MAX) RNE -> 2^31

    // ---- Handshake corners ----
    check_no_accept();
    check_backpressure();

    // ---- Randomized correct-rounding property ----
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rx = $random; ro = $random;
      check_prop(rx, ro[0]);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_int_to_fp INT_WIDTH=%0d, %0d random vectors, 0 mismatches", INT_WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_int_to_fp INT_WIDTH=%0d, %0d mismatches", INT_WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_int_to_fp
