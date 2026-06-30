// tb_fu_rounding.sv -- Self-checking testbench for fu_rounding (group 17).
// Unary, latency-1 DUT (floor/ceil/round/trunc/roundeven). EXACT (no tolerance):
//   - value oracle: decode dut + a real reference to real, assert EXACT equality
//     (random |x| < 1e6, all modes; rounding results are exactly representable).
//   - exact-bit directed: hand-computed bit patterns incl. signed zero, +/-1,
//     ties (0.5/1.5/2.5), already-integer passthrough, Inf/NaN passthrough.
// WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_rounding #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 6000
);

  logic              clk, rst_n;
  logic [2:0]        op_sel;
  logic [WIDTH-1:0]  in_data_0;
  logic              in_valid_0, in_ready_0;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;

  fu_rounding #(.WIDTH(WIDTH)) dut (
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

  // real reference for each mode
  function automatic real ref_round(input real x, input logic [2:0] op);
    real a, fl, fr, m; logic sgn;
    begin
      case (op)
        3'd0: ref_round = $floor(x);
        3'd1: ref_round = $ceil(x);
        3'd3: ref_round = real'($rtoi(x));                 // trunc toward zero
        default: begin                                      // round (2) / roundeven (4)
          sgn = (x < 0.0); a = sgn ? -x : x;
          fl  = $floor(a); fr = a - fl;
          if (fr > 0.5)      m = fl + 1.0;
          else if (fr < 0.5) m = fl;
          else if (op == 3'd2) m = fl + 1.0;                // ties away
          else begin                                        // ties even
            if (($rtoi(fl) % 2) == 0) m = fl; else m = fl + 1.0;
          end
          ref_round = sgn ? -m : m;
        end
      endcase
    end
  endfunction

  task automatic drive_get(input logic [31:0] xb, input logic [2:0] op, output logic [31:0] result);
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

  // value-equality check (treats +0 == -0; magnitude/rounding correctness)
  task automatic check_val(input logic [31:0] xb, input logic [2:0] op);
    logic [31:0] got; real xr, rv, dr;
    begin
      drive_get(xb, op, got);
      xr = decode_f32(xb); rv = ref_round(xr, op); dr = decode_f32(got);
      if (dr != rv) begin
        $display("FAIL val: op=%0d x=%h (%.6g) got=%h (%.6g) ref=%.6g", op, xb, xr, got, dr, rv);
        error_count = error_count + 1;
      end
    end
  endtask

  // exact-bit check
  task automatic check_bits(input logic [31:0] xb, input logic [2:0] op, input logic [31:0] e);
    logic [31:0] got;
    begin
      drive_get(xb, op, got);
      if (got !== e) begin
        $display("FAIL bits: op=%0d x=%h got=%h exp=%h", op, xb, got, e);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_real(input real v, input logic [2:0] op); check_val(real_to_f32(v), op); endtask

  initial begin : main
    integer i, j; logic [31:0] t0, t1; real r; logic [2:0] op;

    error_count = 0;
    op_sel = 3'd0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- exact-bit directed (signed zero, +/-1, ties, passthrough, Inf/NaN) ----
    // trunc(-0.3) = -0  (0x80000000) ; trunc(0.3) = +0
    check_bits(real_to_f32(-0.3), 3'd3, 32'h80000000);
    check_bits(real_to_f32( 0.3), 3'd3, 32'h00000000);
    // ceil(-0.3) = -0 ; floor(0.3) = +0 ; floor(-0.3) = -1 ; ceil(0.3) = +1
    check_bits(real_to_f32(-0.3), 3'd1, 32'h80000000);
    check_bits(real_to_f32( 0.3), 3'd0, 32'h00000000);
    check_bits(real_to_f32(-0.3), 3'd0, 32'hBF800000);
    check_bits(real_to_f32( 0.3), 3'd1, 32'h3F800000);
    // round(0.5)=1, round(-0.5)=-1, roundeven(0.5)=0, roundeven(-0.5)=-0
    check_bits(real_to_f32( 0.5), 3'd2, 32'h3F800000);
    check_bits(real_to_f32(-0.5), 3'd2, 32'hBF800000);
    check_bits(real_to_f32( 0.5), 3'd4, 32'h00000000);
    check_bits(real_to_f32(-0.5), 3'd4, 32'h80000000);
    // ties at 1.5 / 2.5: round away vs even
    check_bits(real_to_f32(1.5), 3'd2, 32'h40000000);  // round(1.5)=2
    check_bits(real_to_f32(1.5), 3'd4, 32'h40000000);  // roundeven(1.5)=2
    check_bits(real_to_f32(2.5), 3'd2, 32'h40400000);  // round(2.5)=3
    check_bits(real_to_f32(2.5), 3'd4, 32'h40000000);  // roundeven(2.5)=2
    // already-integer passthrough (2^23, 2^24, 12345.0)
    check_bits(32'h4B000000, 3'd0, 32'h4B000000);      // floor(2^23)=2^23
    check_bits(32'h4B800000, 3'd2, 32'h4B800000);      // round(2^24)=2^24
    check_bits(real_to_f32(12345.0), 3'd3, real_to_f32(12345.0));
    // Inf / NaN passthrough
    check_bits(32'h7F800000, 3'd0, 32'h7F800000);      // floor(+Inf)=+Inf
    check_bits(32'hFF800000, 3'd1, 32'hFF800000);      // ceil(-Inf)=-Inf
    check_bits(32'h7FC00000, 3'd2, 32'h7FC00000);      // round(NaN)=NaN

    // directed value checks
    check_real(2.3, 3'd0); check_real(2.3, 3'd1); check_real(2.3, 3'd2);
    check_real(2.7, 3'd0); check_real(-2.7, 3'd3); check_real(-2.3, 3'd4);
    check_real(100.49, 3'd2); check_real(100.51, 3'd2); check_real(-0.5, 3'd2);

    // ---- randomized value oracle (|x| < 1e6, all modes) ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      t0 = $random; t1 = $random;
      r  = (real'($signed(t0)) / 2147483648.0) * 1000000.0;
      op = (t1[2:0] > 3'd4) ? 3'd0 : t1[2:0];     // op in {0..4}
      check_val(real_to_f32(r), op);
      // also exercise small |x| < 1 region with finer values
      r  = (real'($signed(t0)) / 2147483648.0);   // (-1,1)
      check_val(real_to_f32(r), op);
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_rounding WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, 2*NRAND);
    else begin
      $display("FAIL: fu_rounding WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_rounding
