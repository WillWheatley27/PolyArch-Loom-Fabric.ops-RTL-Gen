// tb_fu_cordic_hyp.sv -- Self-checking testbench for fu_cordic_hyp (group 14).
// Unary, latency-1 DUT (approximate sinh/cosh via hyperbolic CORDIC). TOLERANCE-
// based (~16-bit, not bit-exact): decode the DUT output to real and require
// |result - $sinh/$cosh(decode(x))| < TOL. Inputs in [-1.1, 1.1] (within the
// hyperbolic convergence range ~1.118). Reports worst-case error. WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_cordic_hyp #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 4000
);

  logic              clk, rst_n, op_sel;
  logic [WIDTH-1:0]  in_data_0;
  logic              in_valid_0, in_ready_0;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;
  real               max_err;

  localparam real TOL  = 0.001;     // ~2^-10 absolute
  localparam real RMAX = 1.1;       // within convergence range ~1.118

  fu_cordic_hyp #(.WIDTH(WIDTH)) dut (
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

  function automatic real decode_f32(input logic [31:0] b);
    logic [7:0] e; logic [22:0] m; real val;
    begin
      e = b[30:23]; m = b[22:0];
      if (e == 8'd0) val = 0.0;
      else           val = (1.0 + real'(m) / 8388608.0) * pow2(int'(e) - 127);
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
        $display("FAIL latency: out_valid low after fire (x=%h op=%0b)", xb, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);
    end
  endtask

  task automatic check(input logic [31:0] xb, input logic op);
    logic [31:0] got; real xr, expv, dr, err;
    begin
      drive_get(xb, op, got);
      xr   = decode_f32(xb);
      expv = op ? $cosh(xr) : $sinh(xr);
      dr   = decode_f32(got);
      err  = dr - expv; if (err < 0.0) err = -err;
      if (err > max_err) max_err = err;
      if (err > TOL) begin
        $display("FAIL: op=%0b x=%h (%.6f) got=%h (%.6f) expect=%.6f err=%.6e",
                 op, xb, xr, got, dr, expv, err);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_real(input real v, input logic op); check(real_to_f32(v), op); endtask

  initial begin : main
    integer i; logic [31:0] t0, t1; real r;

    error_count = 0; max_err = 0.0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed (both sinh and cosh) ----
    check_real(0.0, 1'b0); check_real(0.0, 1'b1);
    check_real(0.5, 1'b0); check_real(0.5, 1'b1);
    check_real(-0.5, 1'b0); check_real(-0.5, 1'b1);
    check_real(1.0, 1'b0); check_real(1.0, 1'b1);
    check_real(-1.0, 1'b0); check_real(-1.0, 1'b1);
    check_real(1.1, 1'b0); check_real(1.1, 1'b1);
    check_real(-1.1, 1'b0); check_real(-1.1, 1'b1);
    check_real(0.1, 1'b0); check_real(0.1, 1'b1);
    check_real(0.25, 1'b0); check_real(0.25, 1'b1);
    check_real(0.01, 1'b0); check_real(0.01, 1'b1);

    // ---- randomized x in [-1.1, 1.1] ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      t0 = $random; t1 = $random;
      r  = (real'($signed(t0)) / 2147483648.0) * RMAX;
      check(real_to_f32(r), t1[0]);
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_cordic_hyp WIDTH=%0d, %0d random vectors, max_err=%.3e (TOL=%.3e)",
               WIDTH, NRAND, max_err, TOL);
    else begin
      $display("FAIL: fu_cordic_hyp WIDTH=%0d, %0d mismatches, max_err=%.3e", WIDTH, error_count, max_err);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_cordic_hyp
