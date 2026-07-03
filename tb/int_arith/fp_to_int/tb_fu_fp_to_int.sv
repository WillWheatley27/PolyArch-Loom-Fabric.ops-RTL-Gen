// tb_fu_fp_to_int.sv -- Self-checking testbench for fu_fp_to_int (group 9).
// Latency-1 DUT: (EXP_W, MANT_W) float -> INT_WIDTH int, truncate toward zero,
// RISC-V FCVT saturation. PARAMETERIZED: run at fp32 (8,23) and fp64 (11,52) via
// -G (INT_WIDTH=32). Directed exact vectors (specials/saturation) + randomized
// in-range oracle (decode -> truncate). TB only.

`timescale 1ns/1ps

module tb_fu_fp_to_int #(
  parameter int unsigned EXP_W     = 8,
  parameter int unsigned MANT_W    = 23,
  parameter int unsigned INT_WIDTH = 32,
  parameter int unsigned NRAND     = 20000
);

  localparam int unsigned FP_WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS     = (1 << (EXP_W - 1)) - 1;

  logic                 clk, rst_n, op_sel;
  logic [FP_WIDTH-1:0]  in_data_0;
  logic                 in_valid_0, in_ready_0;
  logic [INT_WIDTH-1:0] out_data;
  logic                 out_valid, out_ready;
  integer               error_count;

  fu_fp_to_int #(.EXP_W(EXP_W), .MANT_W(MANT_W), .INT_WIDTH(INT_WIDTH)) dut (
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

  function automatic logic [FP_WIDTH-1:0] make_fp(input logic sgn, input integer exp_unb,
                                                  input logic [MANT_W-1:0] m);
    logic [EXP_W-1:0] e;
    begin e = (exp_unb + int'(BIAS)); make_fp = {sgn, e, m}; end
  endfunction

  task automatic check_bits(input logic [FP_WIDTH-1:0] a, input logic op, input logic [INT_WIDTH-1:0] e);
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_data !== e) begin
        $display("FAIL bits: op=%0b a=%h got=%h exp=%h", op, a, out_data, e);
        error_count++;
      end
      if (out_valid !== 1'b1) begin $display("FAIL valid low"); error_count++; end
      @(posedge clk);
    end
  endtask

  task automatic check_rand(input logic [FP_WIDTH-1:0] a, input logic op);
    real rv; logic [INT_WIDTH-1:0] got, e; integer t;
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      got = out_data;
      rv  = decode_fp(a);
      t   = $rtoi(rv);                       // truncate toward zero (|rv| < 2^29 here)
      if (op == 1'b0) e = t;                 // signed
      else            e = a[FP_WIDTH-1] ? '0 : t;   // unsigned: negative -> 0
      if (got !== e) begin
        $display("FAIL rand: op=%0b a=%h got=%h exp=%h (rv=%.6g)", op, a, got, e, rv);
        error_count++;
      end
      @(posedge clk);
    end
  endtask

  initial begin : main
    integer i, eu; logic [63:0] r; logic [FP_WIDTH-1:0] a;
    localparam logic [INT_WIDTH-1:0] IMAX = {1'b0, {(INT_WIDTH-1){1'b1}}};
    localparam logic [INT_WIDTH-1:0] IMIN = {1'b1, {(INT_WIDTH-1){1'b0}}};
    localparam logic [INT_WIDTH-1:0] UMAX = {INT_WIDTH{1'b1}};

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed exact (specials / saturation) ----
    check_bits(make_fp(1'b0, 0, {1'b1, {(MANT_W-1){1'b0}}}), 1'b0, 32'sd1);  // 1.5 -> 1 signed
    check_bits(make_fp(1'b1, 0, {1'b1, {(MANT_W-1){1'b0}}}), 1'b0, -32'sd1); // -1.5 -> -1 signed
    check_bits(make_fp(1'b1, 0, {1'b1, {(MANT_W-1){1'b0}}}), 1'b1, '0);      // -1.5 -> 0 unsigned
    check_bits(make_fp(1'b0, -1, '0), 1'b0, '0);                             // 0.5 -> 0
    check_bits({FP_WIDTH{1'b0}}, 1'b0, '0);                                  // +0 -> 0
    check_bits(make_fp(1'b0, 31, '0), 1'b0, IMAX);                           // 2^31 signed overflow
    check_bits(make_fp(1'b0, 31, '0), 1'b1, {1'b1, {(INT_WIDTH-1){1'b0}}});  // 2^31 unsigned = 0x8000_0000
    check_bits(make_fp(1'b1, 31, '0), 1'b0, IMIN);                           // -2^31 -> INT_MIN
    check_bits(make_fp(1'b0, 32, '0), 1'b1, UMAX);                           // 2^32 unsigned overflow
    check_bits(make_fp(1'b0, 32, '0), 1'b0, IMAX);                           // 2^32 signed overflow
    check_bits({1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}}, 1'b0, IMAX);           // +Inf signed
    check_bits({1'b1, {EXP_W{1'b1}}, {MANT_W{1'b0}}}, 1'b0, IMIN);           // -Inf signed
    check_bits({1'b1, {EXP_W{1'b1}}, {MANT_W{1'b0}}}, 1'b1, '0);             // -Inf unsigned -> 0
    check_bits({1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}}, 1'b1, UMAX);           // +Inf unsigned
    check_bits({1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}}, 1'b0, IMAX); // NaN signed
    check_bits({1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}}, 1'b1, UMAX); // NaN unsigned

    // ---- randomized in-range (E in [-4, 28] -> |trunc| < 2^29) ----
    for (i = 0; i < NRAND; i++) begin : rl
      r  = {$random, $random};
      eu = -4 + (r[15:0] % 33);              // unbiased exponent in [-4, 28]
      a  = make_fp(r[63], eu, r[MANT_W-1:0]);
      check_rand(a, r[62]);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_fp_to_int EXP_W=%0d MANT_W=%0d INT_WIDTH=%0d, %0d vectors, 0 mismatches",
               EXP_W, MANT_W, INT_WIDTH, NRAND);
    else begin
      $display("FAIL: fu_fp_to_int EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_to_int
