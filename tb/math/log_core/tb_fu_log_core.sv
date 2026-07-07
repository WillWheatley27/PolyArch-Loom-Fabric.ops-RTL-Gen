// tb_fu_log_core.sv -- Self-checking testbench for fu_log_core (group 16).
// Unary, latency-1 DUT (approximate log/log2/log10/log1p via compile-time poly).
// PARAMETERIZED by (EXP_W, MANT_W): RTL is GENERATED per format (coeffs baked);
// compile the matching file with -GEXP_W/-GMANT_W. TOLERANCE |dut - ref| <=
// 1e-3*|ref| + 1e-4. Refs: $ln, $ln/ln2, $log10, $ln(1+x). Directed specials.

`timescale 1ns/1ps

module tb_fu_log_core #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 5000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;
  localparam real LN2R = 0.69314718055994531;

  logic             clk, rst_n;
  logic [1:0]       op_sel;
  logic [WIDTH-1:0] in_data_0;
  logic             in_valid_0, in_ready_0;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;
  real              max_rel;
  real              TABS;   // format-aware absolute floor (set in main)

  fu_log_core #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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
      case (op) 2'd0: rv = $ln(xr); 2'd1: rv = $ln(xr)/LN2R; 2'd2: rv = $log10(xr); default: rv = $ln(1.0+xr); endcase
      dr = decode_fp(got);
      ad = dr - rv; if (ad < 0.0) ad = -ad;
      aref = rv < 0.0 ? -rv : rv;
      rel = ad / (aref + 1.0e-12);
      if ((aref > 1.0e-3) && (rel > max_rel)) max_rel = rel;   // rel is meaningless near log's zero at x=1
      if (ad > 1.0e-3 * aref + TABS) begin
        $display("FAIL tol: op=%0d x=%h (%.6g) got=%h (%.8g) ref=%.8g rel=%.3e", op, a, xr, got, dr, rv, rel);
        error_count++;
      end
    end
  endtask

  task automatic check_bits(input logic [WIDTH-1:0] a, input logic [1:0] op, input logic [WIDTH-1:0] e);
    logic [WIDTH-1:0] got;
    begin drive_get(a, op, got);
      if (got !== e) begin $display("FAIL bits: op=%0d a=%h got=%h exp=%h", op, a, got, e); error_count++; end
    end
  endtask

  task automatic check_real(input real v, input logic [1:0] op); check_tol(real_to_fp(v), op); endtask

  initial begin : main
    integer i; logic [63:0] r; real x;
    localparam logic [WIDTH-1:0] PINF = {1'b0,{EXP_W{1'b1}},{MANT_W{1'b0}}};
    localparam logic [WIDTH-1:0] QN   = {1'b0,{EXP_W{1'b1}},1'b1,{(MANT_W-1){1'b0}}};

    error_count = 0; max_rel = 0.0;
    TABS = 1.0e-4; if (32.0*pow2(-int'(MANT_W)) > TABS) TABS = 32.0*pow2(-int'(MANT_W));   // bf16 0.25, else 1e-4
    op_sel = 2'd0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check_real(1.0, 2'd0); check_real(1.0, 2'd1); check_real(1.0, 2'd2);   // log*(1)=0
    check_real(2.0, 2'd1);                     // log2(2)=1
    check_real(8.0, 2'd1);                     // log2(8)=3
    check_real(2.718281828, 2'd0);             // ln(e)~1
    check_real(100.0, 2'd2);                   // log10(100)=2
    check_real(0.5, 2'd0);                     // ln(0.5)<0
    check_real(0.0, 2'd3);                     // log1p(0)=0
    check_real(1.0, 2'd3);                     // log1p(1)=ln2
    check_real(-0.5, 2'd3);                    // log1p(-0.5)=ln0.5
    // ---- specials ----
    check_bits('0, 2'd0, {1'b1,{EXP_W{1'b1}},{MANT_W{1'b0}}});   // log(+0)=-Inf
    check_bits(make_fp(1'b1,0,'0), 2'd0, QN);                    // log(-1)=NaN
    check_bits(PINF, 2'd0, PINF);                                // log(+Inf)=+Inf
    check_bits(QN, 2'd1, QN);                                    // log2(NaN)=NaN
    check_bits(make_fp(1'b1,0,'0), 2'd3, {1'b1,{EXP_W{1'b1}},{MANT_W{1'b0}}}); // log1p(-1)=-Inf
    check_bits(make_fp(1'b1,1,'0), 2'd3, QN);                    // log1p(-2)=NaN

    // ---- randomized ----
    for (i = 0; i < NRAND; i++) begin : rl
      r = {$random, $random};
      if (r[33:32] == 2'd3) begin
        x = (real'($signed(r[31:0])) / 2147483648.0);      // (-1,1)
        if (x <= -0.9) x = -0.9;
        check_real(x, 2'd3);
      end else begin
        x = (real'({1'b0, r[30:0]}) / 2147483648.0) * 1000.0 + 0.001;   // (0, 1000]
        check_real(x, r[33:32]);
      end
    end : rl

    if (error_count == 0)
      $display("PASS: fu_log_core EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, max_rel=%.3e",
               EXP_W, MANT_W, WIDTH, NRAND, max_rel);
    else begin
      $display("FAIL: fu_log_core EXP_W=%0d MANT_W=%0d, %0d mismatches, max_rel=%.3e", EXP_W, MANT_W, error_count, max_rel);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_log_core
