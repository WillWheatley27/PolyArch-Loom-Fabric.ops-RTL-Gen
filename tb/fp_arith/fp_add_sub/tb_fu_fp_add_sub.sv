// tb_fu_fp_add_sub.sv -- Self-checking testbench for fu_fp_add_sub (group 10).
// 2-input, latency-1 DUT (IEEE-754 binary32 add/sub, FTZ subnormals, RNE).
// Layers:
//   1. Directed exact vectors with hand-computed binary32 results.
//   2. Randomized correct-rounding property: decode both operands to real,
//      true = da +/- db; require |decode(dut) - true| <= half_ULP (the
//      double-rounding-safe property for a single add). Operands use moderate,
//      overlapping exponents so results stay in the normal range (alignment,
//      cancellation, rounding) -- Inf/NaN/overflow/underflow are covered by the
//      directed vectors.
//   3. Handshake corners: 2-input join latency-1 timing, backpressure, no-accept.
// WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_fp_add_sub #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 6000
);

  logic              clk;
  logic              rst_n;
  logic              op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1;
  logic              in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_fp_add_sub #(.WIDTH(WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic real pow2(input integer k);
    real r; integer i;
    begin : p2
      r = 1.0;
      if (k >= 0) for (i = 0; i < k;  i = i + 1) r = r * 2.0;
      else        for (i = 0; i < -k; i = i + 1) r = r / 2.0;
      pow2 = r;
    end : p2
  endfunction

  // Decode FINITE binary32 with FTZ (exp==0 -> 0). Caller rules out exp==0xFF.
  function automatic real decode_f32(input logic [31:0] b);
    logic [7:0]  e; logic [22:0] m; real val;
    begin : dec
      e = b[30:23]; m = b[22:0];
      if (e == 8'd0) val = 0.0;                                    // FTZ
      else           val = (1.0 + real'(m) / 8388608.0) * pow2(int'(e) - 127);
      decode_f32 = b[31] ? -val : val;
    end : dec
  endfunction

  task automatic drive_get(input logic [31:0] a, input logic [31:0] b,
                           input logic op, output logic [31:0] result);
    begin : dg
      @(negedge clk);
      in_data_0 = a; in_data_1 = b; op_sel = op;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      if (out_valid !== 1'b1) begin
        $display("FAIL latency: out_valid not high after fire (a=%h b=%h op=%0b)", a, b, op);
        error_count = error_count + 1;
      end
      result = out_data;
      @(posedge clk);
    end : dg
  endtask

  task automatic check_exact(input logic [31:0] a, input logic [31:0] b,
                             input logic op, input logic [31:0] exp_v);
    logic [31:0] got;
    begin : ce
      drive_get(a, b, op, got);
      if (got !== exp_v) begin
        $display("FAIL exact: op=%0b a=%h b=%h got=%h exp=%h", op, a, b, got, exp_v);
        error_count = error_count + 1;
      end
    end : ce
  endtask

  // Random correct-rounding property (operands kept finite & in normal range).
  task automatic check_prop(input logic [31:0] a, input logic [31:0] b, input logic op);
    logic [31:0] got;
    real         da, db, tv, dec, half_ulp, diff;
    logic [7:0]  eg;
    begin : cp
      drive_get(a, b, op, got);
      da = decode_f32(a);
      db = decode_f32(b);
      if (op) db = -db;                       // subf
      tv = da + db;
      if (tv == 0.0) begin : zero_res
        if (got[30:0] !== 31'd0) begin        // expect +/-0
          $display("FAIL prop zero: a=%h b=%h op=%0b got=%h true=0", a, b, op, got);
          error_count = error_count + 1;
        end
      end : zero_res
      else begin : nz_res
        eg       = got[30:23];
        half_ulp = pow2(int'(eg) - 151);      // half-ULP at result magnitude: 2^((eg-127-23)-1)
        dec      = decode_f32(got);
        diff     = dec - tv;
        if (diff < 0.0) diff = -diff;
        if (diff > half_ulp) begin
          $display("FAIL prop: a=%h b=%h op=%0b got=%h dec=%g true=%g diff=%e ulp/2=%e",
                   a, b, op, got, dec, tv, diff, half_ulp);
          error_count = error_count + 1;
        end
      end : nz_res
    end : cp
  endtask

  task automatic check_no_accept;
    begin : na
      @(negedge clk); in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b1;
      @(negedge clk);
      if (out_valid !== 1'b0) begin $display("FAIL: out_valid high w/o input"); error_count = error_count + 1; end
      if (in_ready_0 !== 1'b0) begin $display("FAIL: in_ready0 high w/o both valid"); error_count = error_count + 1; end
    end : na
  endtask

  task automatic check_join;
    begin : jn
      // only one operand valid -> no fire
      @(negedge clk); in_data_0 = 32'h3F800000; in_data_1 = 32'h3F800000;
      op_sel = 1'b0; in_valid_0 = 1'b1; in_valid_1 = 1'b0; out_ready = 1'b1;
      @(negedge clk);
      if (in_ready_0 !== 1'b0) begin $display("FAIL join: in_ready0 high with in_valid_1 low"); error_count = error_count + 1; end
      if (out_valid !== 1'b0) begin $display("FAIL join: out_valid high without join"); error_count = error_count + 1; end
      in_valid_0 = 1'b0;
    end : jn
  endtask

  task automatic check_backpressure;
    logic [31:0] held; integer r;
    begin : bp
      @(negedge clk);
      in_data_0 = 32'h3F800000; in_data_1 = 32'h3F800000; op_sel = 1'b0;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      @(posedge clk);
      @(negedge clk);
      if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid not set"); error_count = error_count + 1; end
      held = out_data;
      for (r = 0; r < 3; r = r + 1) begin : hold_loop
        @(negedge clk);
        if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid dropped"); error_count = error_count + 1; end
        if (out_data !== held)  begin $display("FAIL bp: out_data changed"); error_count = error_count + 1; end
        if (in_ready_0 !== 1'b0) begin $display("FAIL bp: in_ready high while stalled"); error_count = error_count + 1; end
      end : hold_loop
      @(negedge clk); out_ready = 1'b1; in_valid_0 = 1'b0; in_valid_1 = 1'b0;
      @(posedge clk);
    end : bp
  endtask

  initial begin : main
    integer       iter_var0;
    logic [31:0]  ra, rb;
    logic [31:0]  t0, t1, t2;
    logic [7:0]   ea_r, eb_r;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;
    @(posedge clk);

    // ---- Directed exact ----
    check_exact(32'h3F800000, 32'h3F800000, 1'b0, 32'h40000000); // 1+1=2
    check_exact(32'h3F800000, 32'h3F000000, 1'b0, 32'h3FC00000); // 1+0.5=1.5
    check_exact(32'h3FC00000, 32'h3F800000, 1'b1, 32'h3F000000); // 1.5-1=0.5
    check_exact(32'h3F800000, 32'h3F800000, 1'b1, 32'h00000000); // 1-1=+0
    check_exact(32'h3F800000, 32'hBF800000, 1'b0, 32'h00000000); // 1+(-1)=+0
    check_exact(32'h4B800000, 32'h3F800000, 1'b0, 32'h4B800000); // 2^24+1 -> 2^24 (RNE)
    check_exact(32'h4B800000, 32'h40400000, 1'b0, 32'h4B800002); // 2^24+3 -> 2^24+4
    check_exact(32'h40400000, 32'h40A00000, 1'b0, 32'h41000000); // 3+5=8
    check_exact(32'h40400000, 32'h40A00000, 1'b1, 32'hC0000000); // 3-5=-2
    check_exact(32'hC0400000, 32'h40A00000, 1'b0, 32'h40000000); // -3+5=2
    check_exact(32'h40200000, 32'hBF800000, 1'b0, 32'h3FC00000); // 2.5+(-1)=1.5
    check_exact(32'h00000000, 32'h00000000, 1'b0, 32'h00000000); // 0+0=+0
    check_exact(32'h80000000, 32'h80000000, 1'b0, 32'h80000000); // -0+-0=-0
    check_exact(32'h40A00000, 32'h00000000, 1'b0, 32'h40A00000); // 5+0=5
    check_exact(32'h00000000, 32'h40A00000, 1'b0, 32'h40A00000); // 0+5=5
    check_exact(32'h40A00000, 32'h40A00000, 1'b1, 32'h00000000); // 5-5=+0
    check_exact(32'h7F800000, 32'h3F800000, 1'b0, 32'h7F800000); // Inf+1=Inf
    check_exact(32'h7F800000, 32'hFF800000, 1'b0, 32'h7FC00000); // Inf+(-Inf)=NaN
    check_exact(32'h7F800000, 32'h7F800000, 1'b1, 32'h7FC00000); // Inf-Inf=NaN
    check_exact(32'h7FC00000, 32'h3F800000, 1'b0, 32'h7FC00000); // NaN+1=NaN
    check_exact(32'h7F7FFFFF, 32'h7F7FFFFF, 1'b0, 32'h7F800000); // max+max -> +Inf

    // ---- Handshake corners ----
    check_no_accept();
    check_join();
    check_backpressure();

    // ---- Randomized correct-rounding (normal-range operands) ----
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      t0 = $random; t1 = $random; t2 = $random;
      ea_r = 8'd100 + (t0[7:0] % 8'd60);   // exp in [100,159]
      eb_r = 8'd100 + (t1[7:0] % 8'd60);
      ra = {t0[31], ea_r, t0[22:0]};
      rb = {t1[31], eb_r, t1[22:0]};
      check_prop(ra, rb, t2[0]);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_add_sub WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_add_sub WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_fp_add_sub
