// tb_fu_exp_series.sv -- Self-checking testbench for fu_exp_series (group 15).
// Unary, latency-1 DUT (approximate exp/exp2/expm1 via compile-time polynomial).
// PARAMETERIZED by (EXP_W, MANT_W): RTL is GENERATED per format (coeffs baked);
// compile the matching file with -GEXP_W/-GMANT_W. TOLERANCE: |dut - ref| <=
// 1e-3*|ref| + 1e-4. References: $exp, $pow(2,x), $exp(x)-1. Bounded x.

`timescale 1ns/1ps

module tb_fu_exp_series #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 5000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;

  logic             clk, rst_n;
  logic [1:0]       op_sel;
  logic [WIDTH-1:0] in_data_0;
  logic             in_valid_0, in_ready_0;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;
  real              max_rel;

  fu_exp_series #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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

  function automatic real decode_fp(input logic [WIDTH-1:0] b);
    logic sgn; logic [EXP_W-1:0] e; logic [MANT_W-1:0] m; real val;
    begin
      sgn = b[WIDTH-1]; e = b[WIDTH-2:MANT_W]; m = b[MANT_W-1:0];
      if (e == '0)      val = 0.0;
      else if (&e)      val = 1.0e300;
      else              val = (1.0 + real'(m) / pow2(MANT_W)) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

  function automatic logic [WIDTH-1:0] real_to_fp(input real v);
    real tmp; integer ex; logic sgn; logic [MANT_W-1:0] m; logic [EXP_W-1:0] be;
    begin
      sgn = (v < 0.0); tmp = sgn ? -v : v;
      if (tmp == 0.0) real_to_fp = '0;
      else begin
        ex = 0;
        while (tmp >= 2.0) begin tmp = tmp/2.0; ex++; end
        while (tmp <  1.0) begin tmp = tmp*2.0; ex--; end
        m  = $rtoi((tmp - 1.0) * pow2(MANT_W) + 0.5);
        be = ex + int'(BIAS);
        real_to_fp = {sgn, be, m};
      end
    end
  endfunction

  task automatic drive_get(input logic [WIDTH-1:0] a, input logic [1:0] op, output logic [WIDTH-1:0] r);
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low a=%h op=%0d", a, op); error_count++; end
      r = out_data; @(posedge clk);
    end
  endtask

  task automatic check_tol(input logic [WIDTH-1:0] a, input logic [1:0] op);
    logic [WIDTH-1:0] got; real xr, rv, dr, ad, aref, rel;
    begin
      drive_get(a, op, got);
      xr = decode_fp(a);
      case (op) 2'd0: rv = $exp(xr); 2'd1: rv = $pow(2.0, xr); default: rv = $exp(xr) - 1.0; endcase
      dr = decode_fp(got);
      ad = dr - rv; if (ad < 0.0) ad = -ad;
      aref = rv < 0.0 ? -rv : rv;
      rel = ad / (aref + 1.0e-12); if (rel > max_rel) max_rel = rel;
      if (ad > 1.0e-3 * aref + 1.0e-4) begin
        $display("FAIL tol: op=%0d x=%h (%.6g) got=%h (%.8g) ref=%.8g rel=%.3e", op, a, xr, got, dr, rv, rel);
        error_count++;
      end
    end
  endtask

  task automatic check_real(input real v, input logic [1:0] op); check_tol(real_to_fp(v), op); endtask

  initial begin : main
    integer i; logic [63:0] r; real x; logic [1:0] op;

    error_count = 0; max_rel = 0.0;
    op_sel = 2'd0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check_real(0.0, 2'd0); check_real(0.0, 2'd1); check_real(0.0, 2'd2);
    check_real(1.0, 2'd0); check_real(1.0, 2'd1); check_real(1.0, 2'd2);
    check_real(-1.0, 2'd0); check_real(-1.0, 2'd1); check_real(-1.0, 2'd2);
    check_real(2.0, 2'd0); check_real(3.0, 2'd1); check_real(0.5, 2'd0);
    check_real(10.0, 2'd0); check_real(-10.0, 2'd0); check_real(8.0, 2'd1);
    check_real(0.001, 2'd2); check_real(-0.001, 2'd2);

    // ---- randomized x in [-16, 16] ----
    for (i = 0; i < NRAND; i++) begin : rl
      r = {$random, $random};
      x = (real'($signed(r[31:0])) / 2147483648.0) * 16.0;   // [-16, 16]
      op = (r[33:32] == 2'd3) ? 2'd0 : r[33:32];
      check_real(x, op);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_exp_series EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, max_rel=%.3e",
               EXP_W, MANT_W, WIDTH, NRAND, max_rel);
    else begin
      $display("FAIL: fu_exp_series EXP_W=%0d MANT_W=%0d, %0d mismatches, max_rel=%.3e", EXP_W, MANT_W, error_count, max_rel);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_exp_series
