// tb_fu_fp_div_rem.sv -- Self-checking testbench for fu_fp_div_rem (group 11).
// 2-input, multi-cycle DUT: divf (IEEE binary32 divide, RNE, FTZ) and remf
// (fmod). Layers:
//   1. Directed exact vectors (hand-computed) for divf and remf.
//   2. Random oracle: divf -> |decode(dut) - da/db| <= half_ULP. remf -> exact
//      fmod via da - db*$rtoi(da/db) (operands constrained to modest exponent
//      gaps so the integer quotient is exact); real-equality check.
//   3. Handshake: multi-cycle accept / out_valid timing, backpressure.
// WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_fp_div_rem #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 3000
);

  logic              clk, rst_n, op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;

  fu_fp_div_rem #(.WIDTH(WIDTH)) dut (
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

  function automatic real decode_f32(input logic [31:0] b);  // finite, FTZ
    logic [7:0] e; logic [22:0] m; real val;
    begin
      e = b[30:23]; m = b[22:0];
      if (e == 8'd0) val = 0.0;
      else           val = (1.0 + real'(m) / 8388608.0) * pow2(int'(e) - 127);
      decode_f32 = b[31] ? -val : val;
    end
  endfunction

  task automatic drive_get(input logic [31:0] a, input logic [31:0] b,
                           input logic op, output logic [31:0] result);
    integer guard;
    begin : dg
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = op;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      @(posedge clk);                     // accept (IDLE & both valid)
      @(negedge clk); in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      guard = 0;
      while ((out_valid !== 1'b1) && (guard <= 600)) begin
        @(negedge clk); guard = guard + 1;
      end
      if (out_valid !== 1'b1) begin
        $display("FAIL timeout: a=%h b=%h op=%0b", a, b, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);                     // drain
    end : dg
  endtask

  task automatic check_exact(input logic [31:0] a, input logic [31:0] b,
                             input logic op, input logic [31:0] e);
    logic [31:0] got;
    begin
      drive_get(a, b, op, got);
      if (got !== e) begin
        $display("FAIL exact: op=%0b a=%h b=%h got=%h exp=%h", op, a, b, got, e);
        error_count = error_count + 1;
      end
    end
  endtask

  // divf random: correct-rounding half-ULP property.
  task automatic check_div(input logic [31:0] a, input logic [31:0] b);
    logic [31:0] got; real da, db, tv, dec, hu, diff; logic [7:0] eg;
    begin
      drive_get(a, b, 1'b0, got);
      da = decode_f32(a); db = decode_f32(b); tv = da / db;
      eg = got[30:23]; dec = decode_f32(got);
      hu = pow2(int'(eg) - 151);
      diff = dec - tv; if (diff < 0.0) diff = -diff;
      if (diff > hu) begin
        $display("FAIL div: a=%h b=%h got=%h dec=%g true=%g diff=%e hu=%e", a, b, got, dec, tv, diff, hu);
        error_count = error_count + 1;
      end
    end
  endtask

  // remf random: exact fmod (operands constrained so quotient fits $rtoi).
  task automatic check_rem(input logic [31:0] a, input logic [31:0] b);
    logic [31:0] got; real da, db, q, fm, dec;
    begin
      drive_get(a, b, 1'b1, got);
      da = decode_f32(a); db = decode_f32(b);
      q  = da / db;
      q  = (q < 0.0) ? $ceil(q) : $floor(q);   // trunc toward zero
      fm = da - db * q;
      dec = decode_f32(got);
      if (dec != fm) begin
        $display("FAIL rem: a=%h b=%h got=%h dec=%g fmod=%g", a, b, got, dec, fm);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_backpressure;
    logic [31:0] held; integer r;
    begin
      @(negedge clk);
      in_data_0 = 32'h40000000; in_data_1 = 32'h40000000; op_sel = 1'b0;  // 2/2
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      @(posedge clk); @(negedge clk); in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      r = 0;
      while ((out_valid !== 1'b1) && (r <= 60)) begin @(negedge clk); r = r + 1; end
      held = out_data;
      for (r = 0; r < 3; r++) begin
        @(negedge clk);
        if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid dropped"); error_count = error_count + 1; end
        if (out_data !== held)  begin $display("FAIL bp: out_data changed"); error_count = error_count + 1; end
        if (in_ready_0 !== 1'b0) begin $display("FAIL bp: in_ready high while busy/done"); error_count = error_count + 1; end
      end
      @(negedge clk); out_ready = 1'b1; @(posedge clk);
    end
  endtask

  initial begin : main
    integer       i;
    logic [31:0]  t0, t1;
    logic [7:0]   eb_r, ea_r;
    logic [31:0]  ra, rb;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1; @(posedge clk);

    // ---- divf directed ----
    check_exact(32'h40000000, 32'h40000000, 1'b0, 32'h3F800000); // 2/2=1
    check_exact(32'h3F800000, 32'h40000000, 1'b0, 32'h3F000000); // 1/2=0.5
    check_exact(32'h40400000, 32'h40000000, 1'b0, 32'h3FC00000); // 3/2=1.5
    check_exact(32'h40A00000, 32'h40000000, 1'b0, 32'h40200000); // 5/2=2.5
    check_exact(32'h3F800000, 32'h40800000, 1'b0, 32'h3E800000); // 1/4=0.25
    check_exact(32'h40E00000, 32'h40000000, 1'b0, 32'h40600000); // 7/2=3.5
    check_exact(32'hC0C00000, 32'h40000000, 1'b0, 32'hC0400000); // -6/2=-3
    check_exact(32'h3F800000, 32'h00000000, 1'b0, 32'h7F800000); // 1/0=Inf
    check_exact(32'hBF800000, 32'h00000000, 1'b0, 32'hFF800000); // -1/0=-Inf
    check_exact(32'h00000000, 32'h00000000, 1'b0, 32'h7FC00000); // 0/0=NaN
    check_exact(32'h00000000, 32'h40000000, 1'b0, 32'h00000000); // 0/2=0
    check_exact(32'h7F800000, 32'h40000000, 1'b0, 32'h7F800000); // Inf/2=Inf
    check_exact(32'h40000000, 32'h7F800000, 1'b0, 32'h00000000); // 2/Inf=0
    check_exact(32'h7F800000, 32'h7F800000, 1'b0, 32'h7FC00000); // Inf/Inf=NaN
    check_exact(32'h7FC00000, 32'h40000000, 1'b0, 32'h7FC00000); // NaN/2=NaN

    // ---- remf directed ----
    check_exact(32'h40400000, 32'h40000000, 1'b1, 32'h3F800000); // fmod(3,2)=1
    check_exact(32'h40A00000, 32'h40400000, 1'b1, 32'h40000000); // fmod(5,3)=2
    check_exact(32'h40E00000, 32'h40400000, 1'b1, 32'h3F800000); // fmod(7,3)=1
    check_exact(32'hC0E00000, 32'h40400000, 1'b1, 32'hBF800000); // fmod(-7,3)=-1
    check_exact(32'h41000000, 32'h40400000, 1'b1, 32'h40000000); // fmod(8,3)=2
    check_exact(32'hC1000000, 32'h40400000, 1'b1, 32'hC0000000); // fmod(-8,3)=-2
    check_exact(32'h41100000, 32'h40400000, 1'b1, 32'h00000000); // fmod(9,3)=0
    check_exact(32'h40000000, 32'h40A00000, 1'b1, 32'h40000000); // fmod(2,5)=2 (|a|<|b|)
    check_exact(32'h40400000, 32'h00000000, 1'b1, 32'h7FC00000); // fmod(3,0)=NaN
    check_exact(32'h7F800000, 32'h40400000, 1'b1, 32'h7FC00000); // fmod(Inf,3)=NaN
    check_exact(32'h40400000, 32'h7F800000, 1'b1, 32'h40400000); // fmod(3,Inf)=3

    // ---- handshake ----
    check_backpressure();

    // ---- divf random (normal range, half-ULP) ----
    for (i = 0; i < NRAND; i++) begin : rdiv
      t0 = $random; t1 = $random;
      ea_r = 8'd100 + (t0[7:0] % 8'd55);
      eb_r = 8'd100 + (t1[7:0] % 8'd55);
      ra = {t0[31], ea_r, t0[22:0]};
      rb = {t1[31], eb_r, t1[22:0]};
      check_div(ra, rb);
    end : rdiv

    // ---- remf random (modest exponent gap, exact fmod) ----
    for (i = 0; i < NRAND; i++) begin : rrem
      t0 = $random; t1 = $random;
      eb_r = 8'd120 + (t1[3:0]);                 // [120,135]
      ea_r = eb_r + (t0[4:0] % 5'd19);           // gap [0,18]
      ra = {t0[31], ea_r, t0[22:0]};
      rb = {t1[31], eb_r, t1[22:0]};
      check_rem(ra, rb);
    end : rrem

    if (error_count == 0)
      $display("PASS: fu_fp_div_rem WIDTH=%0d, %0d+%0d random vectors, 0 mismatches", WIDTH, NRAND, NRAND);
    else begin
      $display("FAIL: fu_fp_div_rem WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_div_rem
