// tb_fu_cordic_trig.sv -- Self-checking testbench for fu_cordic_trig (group 13).
// Unary, latency-1 DUT (approximate sin/cos via CORDIC). PARAMETERIZED by
// (EXP_W, MANT_W): RTL generated per format (constants baked); compile the
// matching file with -GEXP_W/-GMANT_W. TOLERANCE: |dut - $sin/$cos(decode(x))| <
// TOL. Inputs in [-pi, pi]. real_to_fp builds the mantissa bit-by-bit (NOT $rtoi,
// which is 32-bit). Reports worst-case abs error.

`timescale 1ns/1ps

module tb_fu_cordic_trig #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 4000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;
  real TOL;   // format-aware (~16 ULP of the mantissa); set in main

  logic             clk, rst_n, op_sel;
  logic [WIDTH-1:0] in_data_0;
  logic             in_valid_0, in_ready_0;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;
  real              max_err;

  fu_cordic_trig #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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
      if (e == '0) val = 0.0;
      else         val = (1.0 + real'(m) / pow2(MANT_W)) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

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

  task automatic check(input real xv, input logic op);
    logic [WIDTH-1:0] got; real xr, rv, dr, ad;
    begin
      @(negedge clk);
      in_data_0 = real_to_fp(xv); op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low x=%g op=%0b", xv, op); error_count++; end
      got = out_data;
      xr  = decode_fp(in_data_0);
      rv  = op ? $cos(xr) : $sin(xr);
      dr  = decode_fp(got);
      ad  = dr - rv; if (ad < 0.0) ad = -ad;
      if (ad > max_err) max_err = ad;
      if (ad > TOL) begin
        $display("FAIL: op=%0b x=%.6g got=%h (%.8g) ref=%.8g err=%.3e", op, xr, got, dr, rv, ad);
        error_count++;
      end
      @(posedge clk);
    end
  endtask

  initial begin : main
    integer i; logic [31:0] t; real x; real PI;
    PI = 3.14159265358979;

    error_count = 0; max_err = 0.0;
    TOL = 16.0 * pow2(-int'(MANT_W));   // ~16 ULP: fp32 1.9e-6, fp64 3.6e-15, bf16 0.125
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check(0.0, 1'b0); check(0.0, 1'b1);
    check(PI/6.0, 1'b0); check(PI/6.0, 1'b1);
    check(PI/4.0, 1'b0); check(PI/4.0, 1'b1);
    check(PI/2.0, 1'b0); check(PI/2.0, 1'b1);
    check(-PI/3.0, 1'b0); check(-PI/3.0, 1'b1);
    check(1.0, 1'b0); check(1.0, 1'b1);
    check(3.0, 1'b0); check(-3.0, 1'b1);

    // ---- randomized x in [-pi, pi] ----
    for (i = 0; i < NRAND; i++) begin : rl
      t = $random;
      x = (real'($signed(t)) / 2147483648.0) * PI;
      check(x, t[0]);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_cordic_trig EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, max_err=%.3e",
               EXP_W, MANT_W, WIDTH, NRAND, max_err);
    else begin
      $display("FAIL: fu_cordic_trig EXP_W=%0d MANT_W=%0d, %0d mismatches, max_err=%.3e", EXP_W, MANT_W, error_count, max_err);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_cordic_trig
