// tb_fu_sqrt_rsqrt.sv -- Self-checking testbench for fu_sqrt_rsqrt (group 18).
// Unary, latency-1 DUT (approximate sqrt/rsqrt via compile-time minimax polynomial).
// PARAMETERIZED by (EXP_W, MANT_W): the RTL is GENERATED per format (coeffs baked),
// so compile the matching generated file with -GEXP_W/-GMANT_W. TOLERANCE-based:
// |dut - ref| <= TOL_REL*|ref|, ref = $sqrt(x) / 1.0/$sqrt(x). Directed perfect
// squares + specials by exact bits. TOL_REL scales with the format's precision.

`timescale 1ns/1ps

module tb_fu_sqrt_rsqrt #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 5000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;
  // polynomial degree grows with format; tolerance tracks the achievable accuracy.
  localparam real TOL_REL = (MANT_W >= 40) ? 1.0e-7 : 1.0e-5;

  logic             clk, rst_n, op_sel;
  logic [WIDTH-1:0] in_data_0;
  logic             in_valid_0, in_ready_0;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;
  real              max_rel;

  fu_sqrt_rsqrt #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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

  function automatic logic [WIDTH-1:0] make_fp(input logic sgn, input integer eu,
                                               input logic [MANT_W-1:0] m);
    logic [EXP_W-1:0] e;
    begin e = (eu + int'(BIAS)); make_fp = {sgn, e, m}; end
  endfunction

  task automatic drive_get(input logic [WIDTH-1:0] a, input logic op, output logic [WIDTH-1:0] r);
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low a=%h op=%0b", a, op); error_count++; end
      r = out_data; @(posedge clk);
    end
  endtask

  task automatic check_tol(input logic [WIDTH-1:0] a, input logic op);
    logic [WIDTH-1:0] got; real xr, rv, dr, ad, rel;
    begin
      drive_get(a, op, got);
      xr = decode_fp(a); rv = op ? (1.0 / $sqrt(xr)) : $sqrt(xr); dr = decode_fp(got);
      ad = dr - rv; if (ad < 0.0) ad = -ad;
      rel = ad / (rv + 1.0e-300); if (rel > max_rel) max_rel = rel;
      if (ad > TOL_REL * rv) begin
        $display("FAIL tol: op=%0b a=%h (%.6g) got=%h (%.10g) ref=%.10g rel=%.3e",
                 op, a, xr, got, dr, rv, rel);
        error_count++;
      end
    end
  endtask

  task automatic check_bits(input logic [WIDTH-1:0] a, input logic op, input logic [WIDTH-1:0] e);
    logic [WIDTH-1:0] got;
    begin drive_get(a, op, got);
      if (got !== e) begin $display("FAIL bits: op=%0b a=%h got=%h exp=%h", op, a, got, e); error_count++; end
    end
  endtask

  task automatic check_real(input real v, input logic op); check_tol(make_fp_from_real(v), op); endtask
  function automatic logic [WIDTH-1:0] make_fp_from_real(input real v);
    real tmp; integer ex; logic [MANT_W-1:0] m;
    begin
      ex = 0; tmp = v;
      while (tmp >= 2.0) begin tmp = tmp/2.0; ex++; end
      while (tmp <  1.0) begin tmp = tmp*2.0; ex--; end
      m = $rtoi((tmp - 1.0) * pow2(MANT_W) + 0.5);
      make_fp_from_real = make_fp(1'b0, ex, m);
    end
  endfunction

  initial begin : main
    integer i; logic [63:0] r; logic op;
    localparam logic [WIDTH-1:0] PINF = {1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    localparam logic [WIDTH-1:0] QNAN = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};

    error_count = 0; max_rel = 0.0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed known values ----
    check_real(1.0, 1'b0); check_real(1.0, 1'b1);
    check_real(4.0, 1'b0); check_real(4.0, 1'b1);
    check_real(2.0, 1'b0); check_real(2.0, 1'b1);
    check_real(0.25, 1'b0); check_real(0.25, 1'b1);
    check_real(9.0, 1'b0); check_real(9.0, 1'b1);
    check_real(1000000.0, 1'b0); check_real(1000000.0, 1'b1);
    check_real(0.001, 1'b0); check_real(0.001, 1'b1);
    // ---- specials ----
    check_bits('0, 1'b0, '0);                       // sqrt(+0)=+0
    check_bits({1'b1,{(WIDTH-1){1'b0}}}, 1'b1, {1'b1,{EXP_W{1'b1}},{MANT_W{1'b0}}}); // rsqrt(-0)=-Inf
    check_bits('0, 1'b1, PINF);                     // rsqrt(+0)=+Inf
    check_bits(make_fp(1'b1,1,'0), 1'b0, QNAN);     // sqrt(-2)=NaN
    check_bits(PINF, 1'b0, PINF);                   // sqrt(+Inf)=+Inf
    check_bits(PINF, 1'b1, '0);                     // rsqrt(+Inf)=+0

    // ---- randomized positive x, both ops (bounded exponent, double-representable) ----
    for (i = 0; i < NRAND; i++) begin : rl
      r = {$random, $random};
      in_data_0 = make_fp(1'b0, -60 + (r[15:0] % 121), r[MANT_W-1:0]); op = r[63];
      check_tol(in_data_0, op);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_sqrt_rsqrt EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, max_rel=%.3e",
               EXP_W, MANT_W, WIDTH, NRAND, max_rel);
    else begin
      $display("FAIL: fu_sqrt_rsqrt EXP_W=%0d MANT_W=%0d, %0d mismatches, max_rel=%.3e", EXP_W, MANT_W, error_count, max_rel);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_sqrt_rsqrt
