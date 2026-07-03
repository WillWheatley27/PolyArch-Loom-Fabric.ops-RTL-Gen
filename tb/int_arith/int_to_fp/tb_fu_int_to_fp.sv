// tb_fu_int_to_fp.sv -- Self-checking testbench for fu_int_to_fp (group 8).
// Latency-1 DUT: INT_WIDTH integer -> (EXP_W, MANT_W) float, RNE.
// PARAMETERIZED: run at fp32 (8,23) and fp64 (11,52) via -G. Reference = the
// integer's exact real value; correctness = |dut - ref| <= 0.5 ULP (definition
// of correct rounding). INT_WIDTH=32 here (int32 values are exact in double).

`timescale 1ns/1ps

module tb_fu_int_to_fp #(
  parameter int unsigned INT_WIDTH = 32,
  parameter int unsigned EXP_W     = 8,
  parameter int unsigned MANT_W    = 23,
  parameter int unsigned NRAND     = 20000
);

  localparam int unsigned FP_WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS     = (1 << (EXP_W - 1)) - 1;

  logic                 clk, rst_n, op_sel;
  logic [INT_WIDTH-1:0] in_data_0;
  logic                 in_valid_0, in_ready_0;
  logic [FP_WIDTH-1:0]  out_data;
  logic                 out_valid, out_ready;
  integer               error_count;

  fu_int_to_fp #(.INT_WIDTH(INT_WIDTH), .EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init clk = 1'b0; end
  always begin : clk_toggle #5 clk = ~clk; end

  function automatic real pow2(input integer k);
    real r; integer i;
    begin r = 1.0;
      if (k >= 0) for (i = 0; i < k;  i++) r = r * 2.0;
      else        for (i = 0; i < -k; i++) r = r / 2.0;
      pow2 = r;
    end
  endfunction

  function automatic real decode_fp(input logic [FP_WIDTH-1:0] b);
    logic sgn; logic [EXP_W-1:0] e; logic [MANT_W-1:0] m; real val;
    begin
      sgn = b[FP_WIDTH-1]; e = b[FP_WIDTH-2:MANT_W]; m = b[MANT_W-1:0];
      if (e == '0) val = (real'(m) / pow2(MANT_W)) * pow2(1 - int'(BIAS));
      else         val = (1.0 + real'(m) / pow2(MANT_W)) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

  // unsigned INT_WIDTH bits -> real (exact for magnitudes <= 2^53)
  function automatic real uint_to_real(input logic [INT_WIDTH-1:0] a);
    real v; integer i;
    begin v = 0.0;
      for (i = 0; i < INT_WIDTH; i++) if (a[i]) v = v + pow2(i);
      uint_to_real = v;
    end
  endfunction

  // reference real value of the operand under the current signedness
  function automatic real int_ref(input logic [INT_WIDTH-1:0] a, input logic op);
    begin
      if (op == 1'b0 && a[INT_WIDTH-1]) int_ref = -(pow2(INT_WIDTH) - uint_to_real(a)); // signed neg
      else                              int_ref = uint_to_real(a);
    end
  endfunction

  task automatic check(input logic [INT_WIDTH-1:0] a, input logic op);
    logic [FP_WIDTH-1:0] got; real rv, dv, diff, ulp; logic [EXP_W-1:0] e;
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      got = out_data;
      if (out_valid !== 1'b1) begin $display("FAIL valid low a=%h", a); error_count++; end
      rv = int_ref(a, op);
      dv = decode_fp(got);
      diff = dv - rv; if (diff < 0.0) diff = -diff;
      e = got[FP_WIDTH-2:MANT_W];
      ulp = (e == '0) ? pow2(1 - int'(BIAS) - int'(MANT_W))
                      : pow2(int'(e) - int'(BIAS) - int'(MANT_W));
      if (diff > 0.5 * ulp * 1.0000001) begin   // correct rounding => within half ULP
        $display("FAIL: op=%0b a=%h got=%h dv=%.10g rv=%.10g diff=%.3g ulp=%.3g",
                 op, a, got, dv, rv, diff, ulp);
        error_count++;
      end
      @(posedge clk);
    end
  endtask

  initial begin : main
    integer i; logic [63:0] r;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check(32'd0, 1'b0);                        // 0 -> +0
    check(32'd1, 1'b0); check(32'd1, 1'b1);    // 1.0
    check(32'hFFFFFFFF, 1'b0);                 // signed -1
    check(32'hFFFFFFFF, 1'b1);                 // unsigned 4294967295
    check(32'h7FFFFFFF, 1'b0);                 // INT_MAX
    check(32'h80000000, 1'b0);                 // INT_MIN
    check(32'd16777216, 1'b0);                 // 2^24
    check(32'd16777217, 1'b0);                 // 2^24 + 1 (fp32 rounds)
    check(32'd33554435, 1'b0);                 // 2^25 + 3 (fp32 tie region)

    // ---- randomized ----
    for (i = 0; i < NRAND; i++) begin : rl
      r = {$random, $random};
      check(r[INT_WIDTH-1:0], r[63]);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_int_to_fp INT_WIDTH=%0d EXP_W=%0d MANT_W=%0d, %0d vectors, 0 mismatches",
               INT_WIDTH, EXP_W, MANT_W, NRAND);
    else begin
      $display("FAIL: fu_int_to_fp EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_int_to_fp
