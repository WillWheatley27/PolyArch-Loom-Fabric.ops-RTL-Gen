// tb_fu_fp_min_max.sv -- Self-checking testbench for fu_fp_min_max (group 12).
// Combinational 2-input DUT (IEEE-754 binary32 minimum/maximum, NaN-propagating,
// -0 < +0). Directed exact vectors (sign quadrants, +/-0, NaN, +/-Inf, ties) +
// randomized normal operands checked via a real-decode oracle + handshake.
// WIDTH=32. TB only.

`timescale 1ns/1ps

module tb_fu_fp_min_max #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 10000
);

  logic              clk, rst_n, op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid, out_ready;
  integer            error_count;

  fu_fp_min_max #(.WIDTH(WIDTH)) dut (
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

  function automatic real decode_f32(input logic [31:0] b);  // normal operands
    logic [7:0] e; logic [22:0] m; real val;
    begin
      e = b[30:23]; m = b[22:0];
      val = (1.0 + real'(m) / 8388608.0) * pow2(int'(e) - 127);
      decode_f32 = b[31] ? -val : val;
    end
  endfunction

  task automatic check_vec(input logic [31:0] a, input logic [31:0] b,
                           input logic op, input logic [31:0] e);
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

  task automatic check_rand(input logic [31:0] a, input logic [31:0] b, input logic op);
    real da, db; logic [31:0] e;
    begin
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1; #1;
      da = decode_f32(a); db = decode_f32(b);
      // a_lt_b strict; min picks a iff a<b, else b; max is the complement
      if (op) e = (da < db) ? b : a;     // maximumf
      else    e = (da < db) ? a : b;     // minimumf
      if (out_data !== e) begin
        $display("FAIL rand: op=%0b a=%h b=%h got=%h exp=%h (da=%g db=%g)", op, a, b, out_data, e, da, db);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic check_backpressure(input logic [31:0] a, input logic [31:0] b, input logic op);
    begin
      op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0; #1;
      if (out_valid !== 1'b1) begin $display("FAIL bp: out_valid must hold"); error_count = error_count + 1; end
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin $display("FAIL bp: in_ready must be low"); error_count = error_count + 1; end
    end
  endtask

  task automatic check_input_invalid;
    begin
      op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1; #1;
      if (out_valid !== 1'b0) begin $display("FAIL: out_valid high w/ in_valid_0 low"); error_count = error_count + 1; end
      if (in_ready_1 !== 1'b0) begin $display("FAIL: in_ready_1 high w/o join"); error_count = error_count + 1; end
    end
  endtask

  initial begin : main
    integer       i;
    logic [31:0]  t0, t1, t2;
    logic [7:0]   ea_r, eb_r;
    logic [31:0]  ra, rb;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- directed ----
    check_vec(32'h40400000, 32'h40A00000, 1'b0, 32'h40400000); // min(3,5)=3
    check_vec(32'h40400000, 32'h40A00000, 1'b1, 32'h40A00000); // max(3,5)=5
    check_vec(32'hC0400000, 32'hC0A00000, 1'b0, 32'hC0A00000); // min(-3,-5)=-5
    check_vec(32'hC0400000, 32'hC0A00000, 1'b1, 32'hC0400000); // max(-3,-5)=-3
    check_vec(32'hC0000000, 32'h40400000, 1'b0, 32'hC0000000); // min(-2,3)=-2
    check_vec(32'hC0000000, 32'h40400000, 1'b1, 32'h40400000); // max(-2,3)=3
    check_vec(32'h80000000, 32'h00000000, 1'b0, 32'h80000000); // min(-0,+0)=-0
    check_vec(32'h80000000, 32'h00000000, 1'b1, 32'h00000000); // max(-0,+0)=+0
    check_vec(32'h00000000, 32'h80000000, 1'b0, 32'h80000000); // min(+0,-0)=-0
    check_vec(32'h00000000, 32'h80000000, 1'b1, 32'h00000000); // max(+0,-0)=+0
    check_vec(32'h7FC00000, 32'h40400000, 1'b0, 32'h7FC00000); // min(NaN,3)=NaN
    check_vec(32'h40400000, 32'h7FC00000, 1'b1, 32'h7FC00000); // max(3,NaN)=NaN
    check_vec(32'h7F800000, 32'h40400000, 1'b0, 32'h40400000); // min(Inf,3)=3
    check_vec(32'h7F800000, 32'h40400000, 1'b1, 32'h7F800000); // max(Inf,3)=Inf
    check_vec(32'hFF800000, 32'h40400000, 1'b0, 32'hFF800000); // min(-Inf,3)=-Inf
    check_vec(32'hFF800000, 32'h40400000, 1'b1, 32'h40400000); // max(-Inf,3)=3
    check_vec(32'h40A00000, 32'h40A00000, 1'b0, 32'h40A00000); // min(5,5)=5
    check_vec(32'h40A00000, 32'h40A00000, 1'b1, 32'h40A00000); // max(5,5)=5

    // ---- handshake ----
    check_backpressure(32'h40400000, 32'h40A00000, 1'b0);
    check_input_invalid();

    // ---- randomized normal operands ----
    for (i = 0; i < NRAND; i++) begin : rand_loop
      t0 = $random; t1 = $random; t2 = $random;
      ea_r = 8'd1 + (t0[7:0] % 8'd254);   // [1,254] -> normal
      eb_r = 8'd1 + (t1[7:0] % 8'd254);
      ra = {t0[31], ea_r, t0[22:0]};
      rb = {t1[31], eb_r, t1[22:0]};
      check_rand(ra, rb, t2[0]);
    end : rand_loop

    if (error_count == 0)
      $display("PASS: fu_fp_min_max WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    else begin
      $display("FAIL: fu_fp_min_max WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end
    $finish;
  end : main

endmodule : tb_fu_fp_min_max
