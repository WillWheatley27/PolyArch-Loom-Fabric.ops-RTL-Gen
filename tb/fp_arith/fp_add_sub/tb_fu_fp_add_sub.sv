// tb_fu_fp_add_sub.sv -- Self-checking testbench for fu_fp_add_sub (group 10).
// 2-input, latency-1 DUT (IEEE-754 add/sub, FTZ subnormals, RNE).
// PARAMETERIZED by (EXP_W, MANT_W): run at fp32 (8,23) and fp64 (11,52) via -G.
// Randomized correct-rounding: true = da +/- db; require |decode(dut) - true| <=
// half ULP (exact for fp64 since Verilator real is double; bounded exponents keep
// the double sum exact for fp32). Directed vectors cover NaN/Inf/zero/cancel. TB.

`timescale 1ns/1ps

module tb_fu_fp_add_sub #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 20000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;

  logic             clk, rst_n, op_sel;
  logic [WIDTH-1:0] in_data_0, in_data_1;
  logic             in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic [WIDTH-1:0] out_data;
  logic             out_valid, out_ready;
  integer           error_count;

  fu_fp_add_sub #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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

  function automatic real decode_fp(input logic [WIDTH-1:0] b);
    logic sgn; logic [EXP_W-1:0] e; logic [MANT_W-1:0] m; real val;
    begin
      sgn = b[WIDTH-1]; e = b[WIDTH-2:MANT_W]; m = b[MANT_W-1:0];
      if (e == '0)                 val = 0.0;                                   // FTZ
      else if (&e)                 val = 1.0e300;                              // Inf sentinel
      else                         val = (1.0 + real'(m) / pow2(MANT_W)) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

  function automatic logic [WIDTH-1:0] make_fp(input logic sgn, input integer exp_unb,
                                               input logic [MANT_W-1:0] m);
    logic [EXP_W-1:0] e;
    begin e = (exp_unb + int'(BIAS)); make_fp = {sgn, e, m}; end
  endfunction

  localparam real MINNORM = pow2(1 - int'(BIAS));   // smallest normal magnitude

  task automatic drive(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b,
                       input logic op, output logic [WIDTH-1:0] got);
    begin
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = op;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low a=%h b=%h", a, b); error_count++; end
      got = out_data;
      @(posedge clk);
    end
  endtask

  task automatic check_bits(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b,
                            input logic op, input logic [WIDTH-1:0] e);
    logic [WIDTH-1:0] got;
    begin
      drive(a, b, op, got);
      if (got !== e) begin
        $display("FAIL bits: op=%0b a=%h b=%h got=%h exp=%h", op, a, b, got, e);
        error_count++;
      end
    end
  endtask

  task automatic check_rand(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b, input logic op);
    logic [WIDTH-1:0] got; real da, db, tv, dv, diff, ulp; logic [EXP_W-1:0] e;
    begin
      drive(a, b, op, got);
      da = decode_fp(a); db = decode_fp(b);
      tv = op ? (da - db) : (da + db);
      dv = decode_fp(got);
      if ((tv < MINNORM) && (tv > -MINNORM)) begin
        // result underflows to FTZ signed zero (magnitude below smallest normal)
        if (got[WIDTH-2:0] !== '0) begin
          $display("FAIL ftz: op=%0b a=%h b=%h got=%h (tv=%.6g)", op, a, b, got, tv);
          error_count++;
        end
      end else begin
        diff = dv - tv; if (diff < 0.0) diff = -diff;
        e = got[WIDTH-2:MANT_W];
        ulp = pow2(int'(e) - int'(BIAS) - int'(MANT_W));
        if (diff > 0.5 * ulp * 1.0000001) begin
          $display("FAIL rnd: op=%0b a=%h b=%h got=%h dv=%.10g tv=%.10g diff=%.3g ulp=%.3g",
                   op, a, b, got, dv, tv, diff, ulp);
          error_count++;
        end
      end
    end
  endtask

  initial begin : main
    integer i, ea, eb; logic [63:0] r0, r1, r2;
    localparam logic [WIDTH-1:0] PINF = {1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    localparam logic [WIDTH-1:0] NINF = {1'b1, {EXP_W{1'b1}}, {MANT_W{1'b0}}};
    localparam logic [WIDTH-1:0] QNAN = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- directed ----
    check_bits(make_fp(1'b0,1,'0), make_fp(1'b0,1,'0), 1'b0, make_fp(1'b0,2,'0)); // 2+2=4
    check_bits(make_fp(1'b0,2,'0), make_fp(1'b0,1,'0), 1'b1, make_fp(1'b0,1,'0)); // 4-2=2
    check_bits(make_fp(1'b0,1,'0), make_fp(1'b0,1,'0), 1'b1, '0);                 // 2-2=+0
    check_bits(make_fp(1'b0,0,'0), make_fp(1'b1,0,'0), 1'b0, '0);                 // 1+(-1)=+0
    check_bits('0, '0, 1'b0, '0);                                                 // +0 + +0
    check_bits({1'b1,{(WIDTH-1){1'b0}}}, {1'b1,{(WIDTH-1){1'b0}}}, 1'b0, {1'b1,{(WIDTH-1){1'b0}}}); // -0 + -0 = -0
    check_bits(PINF, make_fp(1'b0,0,'0), 1'b0, PINF);                             // Inf+1=Inf
    check_bits(PINF, PINF, 1'b1, QNAN);                                           // Inf-Inf=NaN
    check_bits(NINF, make_fp(1'b0,0,'0), 1'b0, NINF);                             // -Inf+1=-Inf
    check_bits(QNAN, make_fp(1'b0,0,'0), 1'b0, QNAN);                             // NaN+1=NaN

    // ---- randomized (bounded, overlapping exponents; results stay normal) ----
    for (i = 0; i < NRAND; i++) begin : rl
      r0 = {$random,$random}; r1 = {$random,$random}; r2 = {$random,$random};
      ea = -20 + (r0[15:0] % 41);   // unbiased exponent in [-20,20]
      eb = -20 + (r1[15:0] % 41);
      check_rand(make_fp(r0[63], ea, r0[MANT_W-1:0]),
                 make_fp(r1[63], eb, r1[MANT_W-1:0]), r2[0]);
    end : rl

    if (error_count == 0)
      $display("PASS: fu_fp_add_sub EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d vectors, 0 mismatches",
               EXP_W, MANT_W, WIDTH, NRAND);
    else begin
      $display("FAIL: fu_fp_add_sub EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_add_sub
