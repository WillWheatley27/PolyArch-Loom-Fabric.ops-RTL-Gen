// tb_fu_log_core.sv -- Self-checking testbench for fu_log_core (group 16).
// Unary, latency-1 DUT (approximate log/log2/log10/log1p). TOLERANCE-based:
// |dut - ref| <= 1e-3*|ref| + 1e-4. References: $ln, $ln/ln2, $log10, $ln(1+x).
// Random x in (0, 1e6] for log*, (-0.9, 1e3] for log1p; directed specials by
// exact bits. Reports worst-case relative error. WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_log_core #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 4000
);

  logic              clk, rst_n;
  logic [1:0]        op_sel;
  logic [WIDTH-1:0]  in_data_0;
  logic              in_valid_0, in_ready_0;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;
  real               max_rel;

  localparam real LN2R = 0.69314718055994531;

  fu_log_core #(.WIDTH(WIDTH)) dut (
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

  task automatic drive_get(input logic [31:0] xb, input logic [1:0] op, output logic [31:0] result);
    begin
      @(negedge clk);
      in_data_0 = xb; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin
        $display("FAIL latency: out_valid low (x=%h op=%0d)", xb, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);
    end
  endtask

  task automatic check_tol(input logic [31:0] xb, input logic [1:0] op);
    logic [31:0] got; real xr, rv, dr, ad, aref, rel;
    begin
      drive_get(xb, op, got);
      xr = decode_f32(xb);
      case (op)
        2'd0:    rv = $ln(xr);
        2'd1:    rv = $ln(xr) / LN2R;
        2'd2:    rv = $log10(xr);
        default: rv = $ln(1.0 + xr);
      endcase
      dr = decode_f32(got);
      ad = dr - rv; if (ad < 0.0) ad = -ad;
      aref = rv < 0.0 ? -rv : rv;
      rel = ad / (aref + 1.0e-12); if (rel > max_rel) max_rel = rel;
      if (ad > 1.0e-3 * aref + 1.0e-4) begin
        $display("FAIL tol: op=%0d x=%h (%.6g) got=%h (%.6g) ref=%.6g err=%.3e",
                 op, xb, xr, got, dr, rv, ad);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_bits(input logic [31:0] xb, input logic [1:0] op, input logic [31:0] e);
    logic [31:0] got;
    begin
      drive_get(xb, op, got);
      if (got !== e) begin
        $display("FAIL bits: op=%0d x=%h got=%h exp=%h", op, xb, got, e);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_real(input real v, input logic [1:0] op); check_tol(real_to_f32(v), op); endtask

  initial begin : main
    integer i; logic [31:0] t0, t1; real r; logic [1:0] op;

    error_count = 0; max_rel = 0.0;
    op_sel = 2'd0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed in-range ----
    check_real(1.0, 2'd0); check_real(1.0, 2'd1); check_real(1.0, 2'd2);   // log*(1) = 0
    check_real(2.0, 2'd1);                  // log2(2) = 1
    check_real(8.0, 2'd1);                  // log2(8) = 3
    check_real(0.5, 2'd1);                  // log2(0.5) = -1
    check_real(2.718281828, 2'd0);          // ln(e) ~ 1
    check_real(100.0, 2'd2);                // log10(100) = 2
    check_real(1000.0, 2'd2);               // log10(1000) = 3
    check_real(10.0, 2'd0);                 // ln(10)
    check_real(0.1, 2'd0);                  // ln(0.1) < 0
    check_real(0.0, 2'd3);                  // log1p(0) = 0
    check_real(1.0, 2'd3);                  // log1p(1) = ln 2
    check_real(-0.5, 2'd3);                 // log1p(-0.5) = ln 0.5 < 0

    // ---- directed specials (exact bits) ----
    check_bits(32'h00000000, 2'd0, 32'hFF800000); // log(+0) = -Inf
    check_bits(32'h80000000, 2'd0, 32'hFF800000); // log(-0) = -Inf
    check_bits(32'hBF800000, 2'd0, 32'h7FC00000); // log(-1) = NaN
    check_bits(32'h7F800000, 2'd0, 32'h7F800000); // log(+Inf) = +Inf
    check_bits(32'h7FC00000, 2'd1, 32'h7FC00000); // log2(NaN) = NaN
    check_bits(32'hBF800000, 2'd3, 32'hFF800000); // log1p(-1) = -Inf
    check_bits(32'hC0000000, 2'd3, 32'h7FC00000); // log1p(-2) = NaN

    // ---- randomized ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      t0 = $random; t1 = $random;
      op = t1[1:0];
      if (op == 2'd3) begin
        r = (real'($signed(t0)) / 2147483648.0);   // (-1,1)
        if (r <= -0.9) r = -0.9;
        check_real(r, 2'd3);
      end else begin
        r = (real'({1'b0, t0[30:0]}) / 2147483648.0) * 1000.0 + 0.001;  // (0, 1000]
        check_real(r, op);
      end
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_log_core WIDTH=%0d, %0d random vectors, max_rel=%.3e", WIDTH, NRAND, max_rel);
    else begin
      $display("FAIL: fu_log_core WIDTH=%0d, %0d mismatches, max_rel=%.3e", WIDTH, error_count, max_rel);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_log_core
