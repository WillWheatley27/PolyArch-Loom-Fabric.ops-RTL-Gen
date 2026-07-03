// tb_fu_rounding.sv -- Self-checking testbench for fu_rounding (group 17).
// Unary, latency-1 DUT (floor/ceil/round/trunc/roundeven). EXACT (no tolerance).
// PARAMETERIZED by (EXP_W, MANT_W): run at fp32 (8,23) and fp64 (11,52) via -G.
//   - value oracle: decode dut + a real reference, assert EXACT equality
//     (random |x| < 2^28, all modes; rounding results are exactly representable).
//   - exact-bit directed: format-generic patterns incl. signed zero, +/-1, ties,
//     already-integer passthrough, Inf/NaN passthrough.

`timescale 1ns/1ps

module tb_fu_rounding #(
  parameter int unsigned EXP_W  = 8,
  parameter int unsigned MANT_W = 23,
  parameter int unsigned NRAND  = 6000
);

  localparam int unsigned WIDTH = EXP_W + MANT_W + 1;
  localparam int unsigned BIAS  = (1 << (EXP_W - 1)) - 1;

  logic              clk, rst_n;
  logic [2:0]        op_sel;
  logic [WIDTH-1:0]  in_data_0;
  logic              in_valid_0, in_ready_0;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;

  fu_rounding #(.EXP_W(EXP_W), .MANT_W(MANT_W)) dut (
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
    real av, tmp; integer ex; logic sgn; logic [MANT_W:0] sigi; logic [EXP_W-1:0] be;
    begin
      sgn = (v < 0.0); av = sgn ? -v : v;
      if (av == 0.0) real_to_fp = {sgn, {(WIDTH-1){1'b0}}};
      else begin
        ex = 0; tmp = av;
        while (tmp >= 2.0) begin tmp = tmp / 2.0; ex++; end
        while (tmp <  1.0) begin tmp = tmp * 2.0; ex--; end
        sigi = $rtoi((tmp - 1.0) * pow2(MANT_W) + 0.5);
        be   = ex + int'(BIAS);
        real_to_fp = {sgn, be, sigi[MANT_W-1:0]};
      end
    end
  endfunction

  function automatic real ref_round(input real x, input logic [2:0] op);
    real a, fl, fr, m; logic sgn;
    begin
      case (op)
        3'd0: ref_round = $floor(x);
        3'd1: ref_round = $ceil(x);
        3'd3: ref_round = real'($rtoi(x));                   // trunc
        default: begin                                        // round(2) / roundeven(4)
          sgn = (x < 0.0); a = sgn ? -x : x; fl = $floor(a); fr = a - fl;
          if (fr > 0.5)        m = fl + 1.0;
          else if (fr < 0.5)   m = fl;
          else if (op == 3'd2) m = fl + 1.0;                  // ties away
          else                 m = (($rtoi(fl) % 2) == 0) ? fl : fl + 1.0;  // ties even
          ref_round = sgn ? -m : m;
        end
      endcase
    end
  endfunction

  task automatic drive(input logic [WIDTH-1:0] a, input logic [2:0] op, output logic [WIDTH-1:0] got);
    begin
      @(negedge clk);
      in_data_0 = a; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin $display("FAIL valid low a=%h op=%0d", a, op); error_count++; end
      got = out_data; @(posedge clk);
    end
  endtask

  task automatic check_val(input logic [WIDTH-1:0] a, input logic [2:0] op);
    logic [WIDTH-1:0] got; real xr, rv, dr;
    begin
      drive(a, op, got);
      xr = decode_fp(a); rv = ref_round(xr, op); dr = decode_fp(got);
      if (dr != rv) begin
        $display("FAIL val: op=%0d a=%h (%.6g) got=%h (%.6g) ref=%.6g", op, a, xr, got, dr, rv);
        error_count++;
      end
    end
  endtask

  task automatic check_bits(input logic [WIDTH-1:0] a, input logic [2:0] op, input logic [WIDTH-1:0] e);
    logic [WIDTH-1:0] got;
    begin
      drive(a, op, got);
      if (got !== e) begin $display("FAIL bits: op=%0d a=%h got=%h exp=%h", op, a, got, e); error_count++; end
    end
  endtask

  task automatic check_real(input real v, input logic [2:0] op); check_val(real_to_fp(v), op); endtask

  initial begin : main
    integer i; logic [63:0] r; real x;
    logic [WIDTH-1:0] nz, pz;
    localparam logic [WIDTH-1:0] v1p5 = {1'b0, EXP_W'(BIAS), {1'b1, {(MANT_W-1){1'b0}}}}; // 1.5
    localparam logic [WIDTH-1:0] v2p5 = {1'b0, EXP_W'(BIAS+1), {2'b01, {(MANT_W-2){1'b0}}}}; // 2.5

    error_count = 0; nz = {1'b1, {(WIDTH-1){1'b0}}}; pz = {WIDTH{1'b0}};
    op_sel = 3'd0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- exact-bit directed ----
    check_bits(make_fp(1'b1, -2, '0), 3'd3, nz);                 // trunc(-0.25) = -0
    check_bits(make_fp(1'b1, -2, '0), 3'd0, NEG1_val());         // floor(-0.25) = -1  (helper below)
    // (use inline constants for clarity)
    check_bits(make_fp(1'b0, -2, '0), 3'd1, {1'b0, EXP_W'(BIAS), {MANT_W{1'b0}}}); // ceil(0.25)=+1
    check_bits(make_fp(1'b0, -1, '0), 3'd2, {1'b0, EXP_W'(BIAS), {MANT_W{1'b0}}}); // round(0.5)=1
    check_bits(make_fp(1'b0, -1, '0), 3'd4, pz);                 // roundeven(0.5)=0
    check_bits(v1p5, 3'd2, make_fp(1'b0,1,'0));                  // round(1.5)=2
    check_bits(v1p5, 3'd4, make_fp(1'b0,1,'0));                  // roundeven(1.5)=2
    check_bits(v2p5, 3'd4, make_fp(1'b0,1,'0));                  // roundeven(2.5)=2
    check_bits(make_fp(1'b0, MANT_W, '0), 3'd0, make_fp(1'b0, MANT_W, '0));   // 2^MANT_W passthrough
    check_bits({1'b0,{EXP_W{1'b1}},{MANT_W{1'b0}}}, 3'd0, {1'b0,{EXP_W{1'b1}},{MANT_W{1'b0}}}); // +Inf
    check_bits({1'b0,{EXP_W{1'b1}},1'b1,{(MANT_W-1){1'b0}}}, 3'd2,
               {1'b0,{EXP_W{1'b1}},1'b1,{(MANT_W-1){1'b0}}});   // NaN passthrough

    // ---- randomized value oracle (|x| < 2^28) ----
    for (i = 0; i < NRAND; i++) begin : rl
      r = {$random, $random};
      x = (real'($signed(r[47:0])) / pow2(20));    // ~[-2^27, 2^27]
      check_real(x, r[50:48] > 3'd4 ? 3'd0 : r[50:48]);
      x = (real'($signed(r[31:0])) / 2147483648.0); // (-1,1) small region
      check_real(x, r[52:51] == 2'd3 ? 3'd2 : {1'b0, r[52:51]});
    end : rl

    if (error_count == 0)
      $display("PASS: fu_rounding EXP_W=%0d MANT_W=%0d (WIDTH=%0d), %0d random vectors, 0 mismatches",
               EXP_W, MANT_W, WIDTH, NRAND);
    else begin
      $display("FAIL: fu_rounding EXP_W=%0d MANT_W=%0d, %0d mismatches", EXP_W, MANT_W, error_count);
      $fatal(1);
    end
    $finish;
  end : main

  function automatic logic [WIDTH-1:0] NEG1_val; NEG1_val = {1'b1, EXP_W'(BIAS), {MANT_W{1'b0}}}; endfunction

endmodule : tb_fu_rounding
