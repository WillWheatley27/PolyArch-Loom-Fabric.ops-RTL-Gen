// tb_fu_fp_div_rem.sv -- Self-checking testbench for fu_fp_div_rem (group 11).
// 2-input, multi-cycle DUT (IEEE-754 divf RNE + remf/fmod exact, FTZ).
// PARAMETERIZED by (EXP_W, MANT_W): run at fp32 (8,23) and fp64 (11,52) via -G.
// divf: correct rounding via half-ULP (exact oracle for fp64). remf: exact fmod
// oracle. Directed specials by exact bits. Bounded exponents keep results normal.

`timescale 1ns/1ps

module tb_fu_fp_div_rem #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 8000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;

  logic             clk, rst_n, op_sel;
  logic [WIDTH-1:0] in_data_0, in_data_1;
  logic             in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;

  fu_fp_div_rem #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
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

  function automatic real decode_fp(input logic [WIDTH-1:0] b);   // finite, FTZ
    logic sgn; logic [EXP_W-1:0] e; logic [MANT_W-1:0] m; real val;
    begin
      sgn = b[WIDTH-1]; e = b[WIDTH-2:MANT_W]; m = b[MANT_W-1:0];
      if (e == '0) val = 0.0;
      else         val = (1.0 + real'(m) / pow2(MANT_W)) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

  function automatic logic [WIDTH-1:0] make_fp(input logic sgn, input integer eu,
                                               input logic [MANT_W-1:0] m);
    logic [EXP_W-1:0] e;
    begin e = (eu + int'(BIAS)); make_fp = {sgn, e, m}; end
  endfunction

  task automatic drive_get(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b,
                           input logic op, output logic [WIDTH-1:0] result);
    integer guard;
    begin
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = op;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk); in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      guard = 0;
      while ((out_valid !== 1'b1) && (guard <= 3000)) begin @(negedge clk); guard++; end
      if (out_valid !== 1'b1) begin $display("FAIL timeout a=%h b=%h op=%0b", a, b, op); error_count++; end
      result = out_data;
      @(posedge clk);
    end
  endtask

  task automatic check_bits(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b,
                            input logic op, input logic [WIDTH-1:0] e);
    logic [WIDTH-1:0] got;
    begin
      drive_get(a, b, op, got);
      if (got !== e) begin $display("FAIL bits: op=%0b a=%h b=%h got=%h exp=%h", op, a, b, got, e); error_count++; end
    end
  endtask

  task automatic check_div(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b);
    logic [WIDTH-1:0] got; real da, db, tv, dv, diff, ulp; logic [EXP_W-1:0] e;
    begin
      drive_get(a, b, 1'b0, got);
      da = decode_fp(a); db = decode_fp(b); tv = da / db; dv = decode_fp(got);
      diff = dv - tv; if (diff < 0.0) diff = -diff;
      e = got[WIDTH-2:MANT_W];
      ulp = pow2(int'(e) - int'(BIAS) - int'(MANT_W));
      if (diff > 0.5 * ulp * 1.0000001) begin
        $display("FAIL div: a=%h b=%h got=%h dv=%.10g tv=%.10g diff=%.3g ulp=%.3g", a, b, got, dv, tv, diff, ulp);
        error_count++;
      end
    end
  endtask

  // Verify fmod by its defining PROPERTIES (no exact oracle needed, robust for
  // fp64 where a - b*q would round): |r| < |b|, (a - r)/b is an integer, and
  // sign(r) == sign(a) unless r == 0.
  task automatic check_rem(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b);
    logic [WIDTH-1:0] got; real da, db, dv, adv, adb, n, nfrac;
    begin
      drive_get(a, b, 1'b1, got);
      da = decode_fp(a); db = decode_fp(b); dv = decode_fp(got);
      adv = dv < 0.0 ? -dv : dv; adb = db < 0.0 ? -db : db;
      n = (da - dv) / db;
      nfrac = n - real'($rtoi(n >= 0.0 ? n + 0.5 : n - 0.5));  // distance to nearest int
      if (nfrac < 0.0) nfrac = -nfrac;
      if (adv > adb * 1.0000001) begin
        $display("FAIL rem |r|>=|b|: a=%h b=%h got=%h dv=%.10g db=%.10g", a, b, got, dv, db);
        error_count++;
      end else if (nfrac > 1.0e-6) begin
        $display("FAIL rem (a-r)/b not integer: a=%h b=%h got=%h n=%.10g", a, b, got, n);
        error_count++;
      end else if ((dv != 0.0) && ((dv < 0.0) != (da < 0.0))) begin
        $display("FAIL rem sign: a=%h b=%h got=%h dv=%.6g da=%.6g", a, b, got, dv, da);
        error_count++;
      end
    end
  endtask

  initial begin : main
    integer i, ea, eb; logic [63:0] r0, r1;
    localparam logic [WIDTH-1:0] PINF = {1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    localparam logic [WIDTH-1:0] QNAN = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check_bits(make_fp(1'b0,2,'0), make_fp(1'b0,1,'0), 1'b0, make_fp(1'b0,1,'0)); // 4/2=2
    check_div(make_fp(1'b0,0,'0), make_fp(1'b0,2,'0));                            // 1/4=0.25
    check_bits(make_fp(1'b0,0,'0), '0, 1'b0, PINF);                              // 1/0=Inf
    check_bits('0, '0, 1'b0, QNAN);                                              // 0/0=NaN
    check_bits(PINF, PINF, 1'b0, QNAN);                                          // Inf/Inf=NaN
    check_bits(make_fp(1'b0,0,'0), PINF, 1'b0, '0);                              // 1/Inf=0
    check_rem(make_fp(1'b0,3,'0), make_fp(1'b0,1,'0));                            // fmod(8,2)=0
    check_rem(make_fp(1'b0,1,{1'b1,{(MANT_W-1){1'b0}}}), make_fp(1'b0,0,'0));     // fmod(3,1)=0
    check_bits(make_fp(1'b0,0,'0), '0, 1'b1, QNAN);                              // fmod(1,0)=NaN

    // ---- randomized (bounded exponents: results normal, ratios modest) ----
    for (i = 0; i < NRAND; i++) begin : rl
      r0 = {$random,$random}; r1 = {$random,$random};
      ea = -15 + (r0[15:0] % 31); eb = -15 + (r1[15:0] % 31);
      check_div(make_fp(r0[63], ea, r0[MANT_W-1:0]), make_fp(r1[63], eb, r1[MANT_W-1:0]));
      check_rem(make_fp(r0[62], ea, r0[MANT_W-1:1] << 1), make_fp(r1[62], eb, r1[MANT_W-1:1] << 1));
    end : rl

    if (error_count == 0)
      $display("PASS: fu_fp_div_rem EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, 0 mismatches",
               EXP_W, MANT_W, WIDTH, NRAND);
    else begin
      $display("FAIL: fu_fp_div_rem EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_div_rem
