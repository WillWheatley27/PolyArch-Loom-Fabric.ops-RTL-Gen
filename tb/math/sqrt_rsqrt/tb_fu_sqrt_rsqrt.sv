// tb_fu_sqrt_rsqrt.sv -- Self-checking testbench for fu_sqrt_rsqrt (group 18).
// Unary, latency-1 DUT (approximate sqrt/rsqrt via shared LUT). TOLERANCE-based:
// |dut - ref| <= 1e-3*|ref| + 1e-9, ref = $sqrt(x) / 1.0/$sqrt(x). Positive x over
// a wide range (even/odd exponents, <1 and >1); directed perfect squares +
// specials by exact bits. Reports worst-case relative error. WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_sqrt_rsqrt #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 5000
);

  logic              clk, rst_n, op_sel;
  logic [WIDTH-1:0]  in_data_0;
  logic              in_valid_0, in_ready_0;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;
  real               max_rel;

  fu_sqrt_rsqrt #(.WIDTH(WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init clk = 1'b0; end
  always begin : clk_toggle #5 clk = ~clk; end

  function automatic real pow2i(input integer k);
    real r; integer i;
    begin r = 1.0;
      if (k >= 0) for (i = 0; i < k;  i++) r = r * 2.0;
      else        for (i = 0; i < -k; i++) r = r / 2.0;
      pow2i = r;
    end
  endfunction

  function automatic real decode_f32(input logic [31:0] b);
    logic [7:0] e; logic [22:0] m; real val;
    begin
      e = b[30:23]; m = b[22:0];
      if (e == 8'd0)        val = 0.0;
      else if (e == 8'd255) val = 1.0e39;
      else                  val = (1.0 + real'(m) / 8388608.0) * pow2i(int'(e) - 127);
      decode_f32 = b[31] ? -val : val;
    end
  endfunction

  function automatic logic [31:0] real_to_f32(input real v);
    real av, tmp; integer ex; logic sgn; logic [23:0] sig; integer biased;
    begin
      sgn = (v < 0.0); av = sgn ? -v : v;
      if (av == 0.0) real_to_f32 = {sgn, 31'd0};
      else begin
        ex = 0; tmp = av;
        while (tmp >= 2.0) begin tmp = tmp / 2.0; ex = ex + 1; end
        while (tmp <  1.0) begin tmp = tmp * 2.0; ex = ex - 1; end
        sig = $rtoi((tmp - 1.0) * 8388608.0 + 0.5);
        biased = ex + 127;
        real_to_f32 = {sgn, biased[7:0], sig[22:0]};
      end
    end
  endfunction

  task automatic drive_get(input logic [31:0] xb, input logic op, output logic [31:0] result);
    begin
      @(negedge clk);
      in_data_0 = xb; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin
        $display("FAIL latency: out_valid low (x=%h op=%0b)", xb, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);
    end
  endtask

  task automatic check_tol(input logic [31:0] xb, input logic op);
    logic [31:0] got; real xr, rv, dr, ad, aref, rel;
    begin
      drive_get(xb, op, got);
      xr = decode_f32(xb);
      rv = op ? (1.0 / $sqrt(xr)) : $sqrt(xr);
      dr = decode_f32(got);
      ad = dr - rv; if (ad < 0.0) ad = -ad;
      aref = rv < 0.0 ? -rv : rv;
      rel = ad / (aref + 1.0e-12); if (rel > max_rel) max_rel = rel;
      if (ad > 1.0e-3 * aref + 1.0e-9) begin
        $display("FAIL tol: op=%0b x=%h (%.6g) got=%h (%.6g) ref=%.6g err=%.3e",
                 op, xb, xr, got, dr, rv, ad);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_bits(input logic [31:0] xb, input logic op, input logic [31:0] e);
    logic [31:0] got;
    begin
      drive_get(xb, op, got);
      if (got !== e) begin
        $display("FAIL bits: op=%0b x=%h got=%h exp=%h", op, xb, got, e);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_real(input real v, input logic op); check_tol(real_to_f32(v), op); endtask

  initial begin : main
    integer i; logic [31:0] t0, t1; real r; logic op;

    error_count = 0; max_rel = 0.0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed perfect squares / known values ----
    check_real(1.0, 1'b0); check_real(1.0, 1'b1);     // sqrt1=1, rsqrt1=1
    check_real(4.0, 1'b0); check_real(4.0, 1'b1);     // 2, 0.5
    check_real(9.0, 1'b0); check_real(9.0, 1'b1);     // 3, 0.3333
    check_real(2.0, 1'b0); check_real(2.0, 1'b1);     // 1.414, 0.707
    check_real(0.25, 1'b0); check_real(0.25, 1'b1);   // 0.5, 2
    check_real(0.5, 1'b0); check_real(0.5, 1'b1);
    check_real(8.0, 1'b0); check_real(8.0, 1'b1);     // odd exponent
    check_real(100.0, 1'b0); check_real(100.0, 1'b1);
    check_real(1000000.0, 1'b0); check_real(1000000.0, 1'b1);
    check_real(0.001, 1'b0); check_real(0.001, 1'b1);
    check_real(1.5, 1'b0); check_real(3.7, 1'b1);

    // ---- specials (exact bits) ----
    check_bits(32'h00000000, 1'b0, 32'h00000000);  // sqrt(+0)=+0
    check_bits(32'h80000000, 1'b0, 32'h80000000);  // sqrt(-0)=-0
    check_bits(32'h00000000, 1'b1, 32'h7F800000);  // rsqrt(+0)=+Inf
    check_bits(32'h80000000, 1'b1, 32'hFF800000);  // rsqrt(-0)=-Inf
    check_bits(32'hBF800000, 1'b0, 32'h7FC00000);  // sqrt(-1)=NaN
    check_bits(32'hC0800000, 1'b1, 32'h7FC00000);  // rsqrt(-4)=NaN
    check_bits(32'h7F800000, 1'b0, 32'h7F800000);  // sqrt(+Inf)=+Inf
    check_bits(32'h7F800000, 1'b1, 32'h00000000);  // rsqrt(+Inf)=+0
    check_bits(32'h7FC00000, 1'b0, 32'h7FC00000);  // sqrt(NaN)=NaN

    // ---- randomized positive x, both ops ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      t0 = $random; t1 = $random;
      // positive float with exponent in [100,150] -> wide magnitude range
      r  = decode_f32({1'b0, (8'd100 + (t0[7:0] % 8'd50)), t0[22:0]});
      op = t1[0];
      check_tol(real_to_f32(r), op);
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_sqrt_rsqrt WIDTH=%0d, %0d random vectors, max_rel=%.3e", WIDTH, NRAND, max_rel);
    else begin
      $display("FAIL: fu_sqrt_rsqrt WIDTH=%0d, %0d mismatches, max_rel=%.3e", WIDTH, error_count, max_rel);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_sqrt_rsqrt
