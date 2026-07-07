// tb_fu_approx_tanh_erf.sv -- Self-checking testbench for fu_approx_tanh_erf (19).
// Unary, latency-1 DUT (approximate tanh/erf via compile-time-generated LUT+interp).
// PARAMETERIZED by (EXP_W, MANT_W): RTL is generated per format (tables baked);
// compile the matching file with -GEXP_W/-GMANT_W. TOLERANCE |result - ref| < TOL:
// ref = $tanh (native) / Abramowitz-Stegun 7.1.26 for erf (~1.5e-7, no $erf).
// Inputs in [-5,5]. Reports worst-case abs error.

`timescale 1ns/1ps

module tb_fu_approx_tanh_erf #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 4000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;
  real TOL;   // LUT step (~5.8e-4) + format ULP; set in main

  logic             clk, rst_n, op_sel;
  logic [WIDTH-1:0] in_data_0;
  logic             in_valid_0, in_ready_0;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;
  real              max_err;

  fu_approx_tanh_erf #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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

  // Build the mantissa bit-by-bit (NOT $rtoi, which is 32-bit and overflows the
  // 52-bit fp64 mantissa) so the encoded input is exact at any format.
  function automatic logic [WIDTH-1:0] real_to_fp(input real v);
    real tmp, fr; integer ex, i; logic sgn; logic [MANT_W-1:0] m; logic [EXP_W-1:0] be;
    begin
      sgn = (v < 0.0); tmp = sgn ? -v : v;
      if (tmp == 0.0) real_to_fp = '0;
      else begin
        ex = 0;
        while (tmp >= 2.0) begin tmp = tmp/2.0; ex++; end
        while (tmp <  1.0) begin tmp = tmp*2.0; ex--; end
        fr = tmp - 1.0; m = '0;
        for (i = 0; i < MANT_W; i++) begin
          fr = fr * 2.0;
          if (fr >= 1.0) begin m = (m << 1) | 1'b1; fr = fr - 1.0; end
          else           m = m << 1;
        end
        be = ex + int'(BIAS);
        real_to_fp = {sgn, be, m};
      end
    end
  endfunction

  // Abramowitz-Stegun 7.1.26 erf approximation (~1.5e-7), independent of the DUT.
  function automatic real erf_ref(input real x);
    real ax, t, y, s;
    begin
      s = (x < 0.0) ? -1.0 : 1.0; ax = (x < 0.0) ? -x : x;
      t = 1.0 / (1.0 + 0.3275911 * ax);
      y = 1.0 - (((((1.061405429*t - 1.453152027)*t) + 1.421413741)*t - 0.284496736)*t + 0.254829592)*t*$exp(-ax*ax);
      erf_ref = s * y;
    end
  endfunction

  task automatic check(input real xv, input logic op);
    logic [WIDTH-1:0] got; real rv, dr, ad, xr;
    begin
      @(negedge clk);
      in_data_0 = real_to_fp(xv); op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low x=%g op=%0b", xv, op); error_count++; end
      got = out_data;
      xr  = decode_fp(in_data_0);          // reference from the ACTUAL encoded input
      rv  = op ? erf_ref(xr) : $tanh(xr);
      dr  = decode_fp(got);
      ad  = dr - rv; if (ad < 0.0) ad = -ad;
      if (ad > max_err) max_err = ad;
      if (ad > TOL) begin
        $display("FAIL: op=%0b x=%.6g got=%h (%.8g) ref=%.8g err=%.3e", op, xv, got, dr, rv, ad);
        error_count++;
      end
      @(posedge clk);
    end
  endtask

  initial begin : main
    integer i; logic [31:0] t; real x;

    error_count = 0; max_err = 0.0;
    TOL = 2.0e-3 + 16.0 * pow2(-int'(MANT_W));   // step-limited + format ULP (bf16 ~0.127)
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check(0.0, 1'b0); check(0.0, 1'b1);
    check(0.5, 1'b0); check(0.5, 1'b1);
    check(1.0, 1'b0); check(-1.0, 1'b1);
    check(2.0, 1'b0); check(-2.0, 1'b1);
    check(3.0, 1'b0); check(4.0, 1'b1);
    check(5.0, 1'b0); check(-5.0, 1'b1);   // saturation region
    check(0.01, 1'b0); check(0.01, 1'b1);

    // ---- randomized x in [-5, 5] ----
    for (i = 0; i < NRAND; i++) begin : rl
      t = $random;
      x = (real'($signed(t)) / 2147483648.0) * 5.0;
      check(x, t[0] ^ t[1]);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_approx_tanh_erf EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, max_err=%.3e",
               EXP_W, MANT_W, WIDTH, NRAND, max_err);
    else begin
      $display("FAIL: fu_approx_tanh_erf EXP_W=%0d MANT_W=%0d, %0d mismatches, max_err=%.3e", EXP_W, MANT_W, error_count, max_err);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_approx_tanh_erf
