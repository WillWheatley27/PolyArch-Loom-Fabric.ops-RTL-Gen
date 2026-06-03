// fu_div_rem_signed.sv -- Fabric FU for share group div_rem_signed.
// op_list: arith.divsi, arith.remsi
//   op_sel = 0 -> out = signed(a) / signed(b)   (arith.divsi, quotient tap)
//   op_sel = 1 -> out = signed(a) % signed(b)   (arith.remsi, remainder tap)
//
// One shared restoring-division datapath: quotient and remainder fall out of the
// same iteration; op_sel selects which tap drives out_data. op_sel is a held
// config input (no handshake).
//
// Multi-cycle: ST_IDLE -> ST_COMPUTE (WIDTH iters) -> ST_DONE. Intrinsic latency
// WIDTH+2. Non-pipelined (one operation in flight). Operands are captured at
// accept; the result is held in ST_DONE until out_ready.
//
// Edge cases (RISC-V M-extension semantics; this DIVERGES from loom's
// fu_op_divsi/fu_op_remsi, which return 0 on divide-by-zero):
//   b == 0       : quotient = -1 (all ones), remainder = dividend (a)
//   INT_MIN / -1 : quotient = INT_MIN, remainder = 0 (falls out of the datapath
//                  naturally; no special case needed)

module fu_div_rem_signed #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = arith.divsi (quotient), 1 = arith.remsi (remainder)

  input  logic [WIDTH-1:0]  in_data_0,  // dividend a
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,  // divisor b
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  // State encoding.
  typedef enum logic [1:0] {
    ST_IDLE    = 2'd0,
    ST_COMPUTE = 2'd1,
    ST_DONE    = 2'd2
  } state_t;

  state_t state_r, state_next;

  // Iteration counter.
  localparam int unsigned CNT_WIDTH = $clog2(WIDTH + 1);
  logic [CNT_WIDTH-1:0] cnt_r, cnt_next;

  // Restoring-division working registers.
  logic [WIDTH-1:0]   quo_mag_r,  quo_mag_next;   // dividend shift source -> |quotient|
  logic [WIDTH:0]     rem_acc_r,  rem_acc_next;   // partial remainder (one extra bit)
  logic [WIDTH-1:0]   divisor_r,  divisor_next;   // |b|
  logic               negate_q_r, negate_q_next;  // negate quotient at output
  logic               negate_r_r, negate_r_next;  // negate remainder at output

  // Input handshake: accept when idle and both operands valid.
  logic inputs_valid;
  assign inputs_valid = in_valid_0 & in_valid_1;
  assign in_ready_0   = (state_r == ST_IDLE) & inputs_valid;
  assign in_ready_1   = (state_r == ST_IDLE) & inputs_valid;

  // Output handshake.
  assign out_valid = (state_r == ST_DONE);

  // Operand sign / magnitude at accept time.
  logic              a_neg, b_neg;
  logic [WIDTH-1:0]  abs_a, abs_b;
  always_comb begin : abs_compute
    a_neg = in_data_0[WIDTH-1];
    b_neg = in_data_1[WIDTH-1];
    abs_a = a_neg ? (~in_data_0 + WIDTH'(1)) : in_data_0;
    abs_b = b_neg ? (~in_data_1 + WIDTH'(1)) : in_data_1;
  end : abs_compute

  // Next-state / datapath.
  always_comb begin : next_state_logic
    state_next    = state_r;
    cnt_next      = cnt_r;
    quo_mag_next  = quo_mag_r;
    rem_acc_next  = rem_acc_r;
    divisor_next  = divisor_r;
    negate_q_next = negate_q_r;
    negate_r_next = negate_r_r;

    case (state_r)
      ST_IDLE: begin : idle_case
        if (inputs_valid) begin : accept
          if (in_data_1 == {WIDTH{1'b0}}) begin : div_by_zero
            // RISC-V: quotient = -1, remainder = dividend. Encode via the
            // standard output formula: |quotient| = 1 with negate_q -> -1;
            // |remainder| = |a| with the dividend's sign -> a.
            quo_mag_next  = WIDTH'(1);          // value 1
            negate_q_next = 1'b1;
            rem_acc_next  = {1'b0, abs_a};
            negate_r_next = a_neg;
            state_next    = ST_DONE;
          end : div_by_zero
          else begin : start_compute
            quo_mag_next  = abs_a;              // shift source; becomes |a / b|
            rem_acc_next  = {(WIDTH + 1){1'b0}};
            divisor_next  = abs_b;
            negate_q_next = a_neg ^ b_neg;      // quotient sign
            negate_r_next = a_neg;              // remainder sign follows dividend
            cnt_next      = {CNT_WIDTH{1'b0}};
            state_next    = ST_COMPUTE;
          end : start_compute
        end : accept
      end : idle_case

      ST_COMPUTE: begin : compute_case
        logic [WIDTH:0] shifted_rem;
        logic [WIDTH:0] trial_sub;

        // Shift partial remainder left, bring in next dividend bit (quo MSB).
        shifted_rem = {rem_acc_r[WIDTH-1:0], quo_mag_r[WIDTH-1]};
        trial_sub   = shifted_rem - {1'b0, divisor_r};

        if (!trial_sub[WIDTH]) begin : sub_fits
          rem_acc_next = trial_sub;
          quo_mag_next = {quo_mag_r[WIDTH-2:0], 1'b1};
        end : sub_fits
        else begin : sub_restore
          rem_acc_next = shifted_rem;
          quo_mag_next = {quo_mag_r[WIDTH-2:0], 1'b0};
        end : sub_restore

        if (cnt_r == CNT_WIDTH'(WIDTH - 1)) begin : last_iter
          state_next = ST_DONE;
        end : last_iter
        else begin : more_iters
          cnt_next = cnt_r + CNT_WIDTH'(1);
        end : more_iters
      end : compute_case

      ST_DONE: begin : done_case
        if (out_ready) begin : transfer
          state_next = ST_IDLE;
        end : transfer
      end : done_case

      default: begin : default_case
        state_next = ST_IDLE;
      end : default_case
    endcase
  end : next_state_logic

  // Registered state.
  always_ff @(posedge clk) begin : state_update
    if (!rst_n) begin : reset_block
      state_r    <= ST_IDLE;
      cnt_r      <= {CNT_WIDTH{1'b0}};
      quo_mag_r  <= {WIDTH{1'b0}};
      rem_acc_r  <= {(WIDTH + 1){1'b0}};
      divisor_r  <= {WIDTH{1'b0}};
      negate_q_r <= 1'b0;
      negate_r_r <= 1'b0;
    end : reset_block
    else begin : normal_block
      state_r    <= state_next;
      cnt_r      <= cnt_next;
      quo_mag_r  <= quo_mag_next;
      rem_acc_r  <= rem_acc_next;
      divisor_r  <= divisor_next;
      negate_q_r <= negate_q_next;
      negate_r_r <= negate_r_next;
    end : normal_block
  end : state_update

  // Output taps: apply sign fix-up, then select quotient or remainder.
  logic [WIDTH-1:0] quo_signed;
  logic [WIDTH-1:0] rem_signed;
  assign quo_signed = negate_q_r ? (~quo_mag_r + WIDTH'(1)) : quo_mag_r;
  assign rem_signed = negate_r_r ? (~rem_acc_r[WIDTH-1:0] + WIDTH'(1))
                                 : rem_acc_r[WIDTH-1:0];

  assign out_data = op_sel ? rem_signed : quo_signed;

endmodule : fu_div_rem_signed
