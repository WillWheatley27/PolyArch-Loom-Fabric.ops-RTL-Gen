// tb_fu_fp_min_max.sv -- Self-checking testbench for fu_fp_min_max (group 12).
// Combinational 2-input DUT (IEEE-754 min/max, NaN-propagating, -0 < +0).
// PARAMETERIZED by (EXP_W, MANT_W): run at fp32 (8,23) and fp64 (11,52) via -G.
// Directed exact corners (built from fields) + randomized normal operands checked
// via a format-generic real-decode oracle + handshake. TB only.

`timescale 1ns/1ps

module tb_fu_fp_min_max #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 10000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;

  logic              clk, rst_n, op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;

  fu_fp_min_max #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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

  // format-generic decode (normal + subnormal); test values kept double-representable
  function automatic real decode_fp(input logic [WIDTH-1:0] b);
    logic          sgn; logic [EXP_W-1:0] e; logic [MANT_W-1:0] m; real val, scale;
    begin
      sgn = b[WIDTH-1]; e = b[WIDTH-2:MANT_W]; m = b[MANT_W-1:0];
      scale = pow2(MANT_W);
      if (e == '0) val = (real'(m) / scale) * pow2(1 - int'(BIAS));       // subnormal / zero
      else         val = (1.0 + real'(m) / scale) * pow2(int'(e) - int'(BIAS));
      decode_fp = sgn ? -val : val;
    end
  endfunction

  // field constructors (format-generic)
  function automatic logic [WIDTH-1:0] make_fp(input logic sgn, input integer exp_unb,
                                               input logic [MANT_W-1:0] mant);
    logic [EXP_W-1:0] e;
    begin e = (exp_unb + int'(BIAS)); make_fp = {sgn, e, mant}; end
  endfunction

  function automatic logic [WIDTH-1:0] pos_inf; pos_inf = {1'b0, {EXP_W{1'b1}}, {MANT_W{1'b0}}}; endfunction
  function automatic logic [WIDTH-1:0] neg_inf; neg_inf = {1'b1, {EXP_W{1'b1}}, {MANT_W{1'b0}}}; endfunction
  function automatic logic [WIDTH-1:0] q_nan;   q_nan   = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}}; endfunction
  function automatic logic [WIDTH-1:0] pos_zero; pos_zero = {WIDTH{1'b0}}; endfunction
  function automatic logic [WIDTH-1:0] neg_zero; neg_zero = {1'b1, {(WIDTH-1){1'b0}}}; endfunction
  // value with mantissa MSB set: 1.5 * 2^exp_unb
  function automatic logic [WIDTH-1:0] val_1p5(input logic sgn, input integer exp_unb);
    val_1p5 = make_fp(sgn, exp_unb, {1'b1, {(MANT_W-1){1'b0}}});
  endfunction

  task automatic check_vec(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b,
                           input logic op, input logic [WIDTH-1:0] e);
    begin
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1; #1;
      if (out_data !== e) begin
        $display("FAIL exact: op=%0b a=%h b=%h got=%h exp=%h", op, a, b, out_data, e);
        error_count = error_count + 1;
      end
      if (out_valid !== 1'b1) begin $display("FAIL out_valid low"); error_count = error_count + 1; end
      if ((in_ready_0 !== 1'b1) || (in_ready_1 !== 1'b1)) begin $display("FAIL in_ready low"); error_count = error_count + 1; end
    end
  endtask

  task automatic check_rand(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b, input logic op);
    real da, db; logic a_lt; logic [WIDTH-1:0] e;
    begin
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1; #1;
      da = decode_fp(a); db = decode_fp(b);
      // total order: by value, tie broken by sign (negative < non-negative -> covers -0<+0)
      if (da < db)      a_lt = 1'b1;
      else if (da > db) a_lt = 1'b0;
      else              a_lt = a[WIDTH-1] & ~b[WIDTH-1];
      e = op ? (a_lt ? b : a) : (a_lt ? a : b);   // max : min
      if (out_data !== e) begin
        $display("FAIL rand: op=%0b a=%h b=%h got=%h exp=%h (da=%g db=%g)", op, a, b, out_data, e, da, db);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_backpressure(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b);
    begin
      op_sel = 1'b0; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0; #1;
      if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid must hold"); error_count = error_count + 1; end
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin $display("FAIL bp: in_ready must be low"); error_count = error_count + 1; end
    end
  endtask

  initial begin : main
    integer i; logic [63:0] r0, r1, r2; logic [WIDTH-1:0] a, b; integer ea, eb;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- directed (format-generic) ----
    check_vec(val_1p5(1'b0,1), val_1p5(1'b0,2), 1'b0, val_1p5(1'b0,1)); // min(3,6)=3
    check_vec(val_1p5(1'b0,1), val_1p5(1'b0,2), 1'b1, val_1p5(1'b0,2)); // max(3,6)=6
    check_vec(val_1p5(1'b1,1), val_1p5(1'b1,2), 1'b0, val_1p5(1'b1,2)); // min(-3,-6)=-6
    check_vec(val_1p5(1'b1,1), val_1p5(1'b1,2), 1'b1, val_1p5(1'b1,1)); // max(-3,-6)=-3
    check_vec(neg_zero(), pos_zero(), 1'b0, neg_zero()); // min(-0,+0)=-0
    check_vec(neg_zero(), pos_zero(), 1'b1, pos_zero()); // max(-0,+0)=+0
    check_vec(pos_zero(), neg_zero(), 1'b0, neg_zero()); // min(+0,-0)=-0
    check_vec(pos_zero(), neg_zero(), 1'b1, pos_zero()); // max(+0,-0)=+0
    check_vec(q_nan(), val_1p5(1'b0,1), 1'b0, q_nan());  // min(NaN,3)=NaN
    check_vec(val_1p5(1'b0,1), q_nan(), 1'b1, q_nan());  // max(3,NaN)=NaN
    check_vec(pos_inf(), val_1p5(1'b0,1), 1'b0, val_1p5(1'b0,1)); // min(Inf,3)=3
    check_vec(pos_inf(), val_1p5(1'b0,1), 1'b1, pos_inf());       // max(Inf,3)=Inf
    check_vec(neg_inf(), val_1p5(1'b0,1), 1'b0, neg_inf());       // min(-Inf,3)=-Inf
    check_vec(neg_inf(), val_1p5(1'b0,1), 1'b1, val_1p5(1'b0,1)); // max(-Inf,3)=3
    check_vec(val_1p5(1'b0,2), val_1p5(1'b0,2), 1'b0, val_1p5(1'b0,2)); // min(6,6)=6
    check_vec(val_1p5(1'b0,2), val_1p5(1'b0,2), 1'b1, val_1p5(1'b0,2)); // max(6,6)=6

    // ---- handshake ----
    check_backpressure(val_1p5(1'b0,1), val_1p5(1'b0,2));

    // ---- randomized normal operands (exponent bounded to stay double-representable) ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      r0 = {$random, $random}; r1 = {$random, $random}; r2 = {$random, $random};
      ea = -60 + (r0[15:0] % 121);   // unbiased exponent in [-60, 60]
      eb = -60 + (r1[15:0] % 121);
      a  = make_fp(r0[63], ea, r0[MANT_W-1:0]);
      b  = make_fp(r1[63], eb, r1[MANT_W-1:0]);
      check_rand(a, b, r2[0]);
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_fp_min_max EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d random vectors, 0 mismatches",
               EXP_W, MANT_W, WIDTH, NRAND);
    else begin
      $display("FAIL: fu_fp_min_max EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_min_max
