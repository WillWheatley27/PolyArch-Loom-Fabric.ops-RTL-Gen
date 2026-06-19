// tb_fu_fp_to_int.sv -- Self-checking testbench for fu_fp_to_int (share group 9).
// Unary, latency-1 DUT (IEEE-754 binary32 -> int32, truncate toward zero, RISC-V
// FCVT saturation). Layers:
//   1. Directed exact vectors with hand-computed results.
//   2. Independent oracle on random inputs: decode the float bits to real,
//      classify (NaN/Inf/overflow/negative/in-range), compute the exact expected
//      integer ($rtoi for signed in-range, $floor for unsigned in-range, exact
//      constants for special/overflow). Two batches: exponent-biased in-range +
//      full-random 32-bit.
//   3. Handshake corners: latency-1 timing, backpressure, no-accept.
// FP_WIDTH=INT_WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_fp_to_int #(
  parameter int unsigned FP_WIDTH  = 32,
  parameter int unsigned INT_WIDTH = 32,
  parameter int unsigned NRAND     = 4000
);

  logic              clk;
  logic              rst_n;
  logic              op_sel;
  logic [FP_WIDTH-1:0]  in_data_0;
  logic              in_valid_0;
  logic              in_ready_0;
  logic [INT_WIDTH-1:0] out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_fp_to_int #(.FP_WIDTH(FP_WIDTH), .INT_WIDTH(INT_WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  // Decode FINITE binary32 bits to real (caller must rule out exp==0xFF first).
  function automatic real decode_f32(input logic [31:0] b);
    logic [7:0]  e;
    logic [22:0] m;
    real         val, p;
    integer      k;
    begin : dec
      e = b[30:23]; m = b[22:0];
      if (e == 8'd0) begin : zero_sub
        val = 0.0;                       // zero / subnormal -> truncates to 0
      end : zero_sub
      else begin : normal
        p = 1.0;
        if (int'(e) >= 127) begin : pe
          for (k = 0; k < (int'(e) - 127); k = k + 1) p = p * 2.0;
        end : pe
        else begin : ne
          for (k = 0; k < (127 - int'(e)); k = k + 1) p = p / 2.0;
        end : ne
        val = (1.0 + real'(m) / 8388608.0) * p;
      end : normal
      decode_f32 = b[31] ? -val : val;
    end : dec
  endfunction

  // Drive one value through the latency-1 pipe; return the registered output.
  task automatic drive_get(input logic [31:0] fb, input logic op, output logic [31:0] result);
    begin : dg
      @(negedge clk);
      in_data_0 = fb[FP_WIDTH-1:0]; op_sel = op; in_valid_0 = 1'b1; out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      in_valid_0 = 1'b0;
      if (out_valid !== 1'b1) begin
        $display("FAIL latency: out_valid not high 1 cycle after fire (fb=%h op=%0b)", fb, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);
    end : dg
  endtask

  // Directed: compare to a hand-computed exact result.
  task automatic check_exact(input logic [31:0] fb, input logic op, input logic [31:0] exp_v);
    logic [31:0] got;
    begin : ce
      drive_get(fb, op, got);
      if (got !== exp_v) begin
        $display("FAIL exact: op=%0b fb=%h got=%h exp=%h", op, fb, got, exp_v);
        error_count = error_count + 1;
      end
    end : ce
  endtask

  // Independent oracle check (any input).
  task automatic check_conv(input logic [31:0] fb, input logic op);
    logic [31:0] got, exp_v;
    logic [7:0]  e;
    logic [22:0] m;
    logic        s, nan;
    real         dec, fl;
    begin : cc
      drive_get(fb, op, got);
      s = fb[31]; e = fb[30:23]; m = fb[22:0]; nan = (e == 8'hFF) && (m != 23'd0);
      if (op == 1'b0) begin : signed_oracle
        if (nan)              exp_v = 32'h7FFF_FFFF;
        else if (e == 8'hFF)  exp_v = s ? 32'h8000_0000 : 32'h7FFF_FFFF;
        else begin : s_fin
          dec = decode_f32(fb);
          if (dec >= 2147483648.0)       exp_v = 32'h7FFF_FFFF;   // >= 2^31
          else if (dec < -2147483648.0)  exp_v = 32'h8000_0000;   // < -2^31
          else                           exp_v = $rtoi(dec);      // trunc toward zero
        end : s_fin
      end : signed_oracle
      else begin : unsigned_oracle
        if (nan)              exp_v = 32'hFFFF_FFFF;
        else if (s)           exp_v = 32'd0;                       // negative -> 0
        else if (e == 8'hFF)  exp_v = 32'hFFFF_FFFF;               // +Inf
        else begin : u_fin
          dec = decode_f32(fb);
          if (dec >= 4294967296.0)       exp_v = 32'hFFFF_FFFF;    // >= 2^32
          else begin : u_inrange
            fl = $floor(dec);                                      // [0, 2^32)
            if (fl >= 2147483648.0) exp_v = 32'h8000_0000 | $rtoi(fl - 2147483648.0);
            else                    exp_v = $rtoi(fl);
          end : u_inrange
        end : u_fin
      end : unsigned_oracle
      if (got !== exp_v) begin
        $display("FAIL conv: op=%0b fb=%h got=%h exp=%h", op, fb, got, exp_v);
        error_count = error_count + 1;
      end
    end : cc
  endtask

  task automatic check_no_accept;
    begin : na
      @(negedge clk); in_valid_0 = 1'b0; out_ready = 1'b1;
      @(negedge clk);
      if (out_valid !== 1'b0) begin $display("FAIL: out_valid high with no input"); error_count = error_count + 1; end
      if (in_ready_0 !== 1'b0) begin $display("FAIL: in_ready high with in_valid low"); error_count = error_count + 1; end
    end : na
  endtask

  task automatic check_backpressure;
    logic [31:0] held;
    integer      r;
    begin : bp
      @(negedge clk);
      in_data_0 = 32'h40A00000; op_sel = 1'b0; in_valid_0 = 1'b1; out_ready = 1'b0;  // 5.0
      @(posedge clk);
      @(negedge clk);
      in_data_0 = 32'h41200000;   // a different value waiting (10.0)
      if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid not set"); error_count = error_count + 1; end
      held = out_data;
      for (r = 0; r < 3; r = r + 1) begin : hold_loop
        @(negedge clk);
        if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid dropped"); error_count = error_count + 1; end
        if (out_data !== held)  begin $display("FAIL bp: out_data changed"); error_count = error_count + 1; end
        if (in_ready_0 !== 1'b0) begin $display("FAIL bp: in_ready high while full+stalled"); error_count = error_count + 1; end
      end : hold_loop
      @(negedge clk); out_ready = 1'b1; in_valid_0 = 1'b0;
      @(posedge clk);
    end : bp
  endtask

  initial begin : main
    integer       iter_var0;
    logic [31:0]  fb;
    logic [7:0]   re;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;
    @(posedge clk);

    // ---- Directed exact (hand-computed) ----
    check_exact(32'h40A00000, 1'b0, 32'h00000005); // fptosi(5.0)   = 5
    check_exact(32'hC0A00000, 1'b0, 32'hFFFFFFFB); // fptosi(-5.0)  = -5
    check_exact(32'h40200000, 1'b0, 32'h00000002); // fptosi(2.5)   = 2 (trunc)
    check_exact(32'hC0200000, 1'b0, 32'hFFFFFFFE); // fptosi(-2.5)  = -2 (trunc toward 0)
    check_exact(32'h3F000000, 1'b0, 32'h00000000); // fptosi(0.5)   = 0
    check_exact(32'h00000000, 1'b0, 32'h00000000); // fptosi(0.0)   = 0
    check_exact(32'h4F000000, 1'b0, 32'h7FFFFFFF); // fptosi(2^31)  -> INT_MAX (saturate)
    check_exact(32'hCF000000, 1'b0, 32'h80000000); // fptosi(-2^31) = INT_MIN
    check_exact(32'h7F800000, 1'b0, 32'h7FFFFFFF); // fptosi(+Inf)  -> INT_MAX
    check_exact(32'hFF800000, 1'b0, 32'h80000000); // fptosi(-Inf)  -> INT_MIN
    check_exact(32'h7FC00000, 1'b0, 32'h7FFFFFFF); // fptosi(NaN)   -> INT_MAX

    check_exact(32'h40A00000, 1'b1, 32'h00000005); // fptoui(5.0)   = 5
    check_exact(32'hC0A00000, 1'b1, 32'h00000000); // fptoui(-5.0)  = 0  (distinguisher)
    check_exact(32'h3F000000, 1'b1, 32'h00000000); // fptoui(0.5)   = 0
    check_exact(32'h4F000000, 1'b1, 32'h80000000); // fptoui(2^31)  = 0x80000000
    check_exact(32'h4F800000, 1'b1, 32'hFFFFFFFF); // fptoui(2^32)  -> UINT_MAX (saturate)
    check_exact(32'h7FC00000, 1'b1, 32'hFFFFFFFF); // fptoui(NaN)   -> UINT_MAX
    check_exact(32'hFF800000, 1'b1, 32'h00000000); // fptoui(-Inf)  = 0
    check_exact(32'h7F800000, 1'b1, 32'hFFFFFFFF); // fptoui(+Inf)  -> UINT_MAX

    // ---- Handshake corners ----
    check_no_accept();
    check_backpressure();

    // ---- Random batch (a): exponent-biased in-range floats ----
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_inrange
      fb     = $random;
      re     = 8'd120 + (fb[7:0] % 8'd39);          // exp in [120,158]
      fb     = {fb[31], re, fb[22:0]};
      check_conv(fb, fb[0] ^ iter_var0[0]);          // vary op_sel
    end : rand_inrange

    // ---- Random batch (b): full-random 32-bit (special / overflow) ----
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_full
      fb = $random;
      check_conv(fb, iter_var0[0]);
    end : rand_full

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_to_int FP_WIDTH=%0d, %0d random vectors, 0 mismatches", FP_WIDTH, 2*NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_to_int FP_WIDTH=%0d, %0d mismatches", FP_WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_fp_to_int
