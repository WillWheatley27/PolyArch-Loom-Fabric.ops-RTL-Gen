// fu_div_rem_unsigned.sv -- Fabric FU for share group div_rem_unsigned.
// op_list: arith.divui, arith.remui
//   op_sel = 0 -> out = a / b   (arith.divui, unsigned, quotient tap)
//   op_sel = 1 -> out = a % b   (arith.remui, unsigned, remainder tap)
//
// One shared restoring-division datapath: quotient and remainder fall out of the
// same iteration; op_sel selects which tap drives out_data. op_sel is a held
// config input (no handshake). Unsigned counterpart of fu_div_rem_signed --
// no absolute value, no sign fix-up.
//
// Multi-cycle: ST_IDLE -> ST_COMPUTE (WIDTH iters) -> ST_DONE. Intrinsic latency
// WIDTH+2. Non-pipelined (one operation in flight). Operands are captured at
// accept; the result is held in ST_DONE until out_ready.
//
// Edge case (RISC-V M-extension semantics; this DIVERGES from loom's
// fu_op_divui/fu_op_remui, which return 0 on divide-by-zero):
//   b == 0 : quotient = all-ones (2^WIDTH-1, max unsigned), remainder = dividend (a)

module fu_div_rem_unsigned #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = arith.divui (quotient), 1 = arith.remui (remainder)

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
  logic [WIDTH-1:0]   quo_mag_r, quo_mag_next;   // dividend shift source -> quotient
  logic [WIDTH:0]     rem_acc_r, rem_acc_next;   // partial remainder (one extra bit)
  logic [WIDTH-1:0]   divisor_r, divisor_next;   // b

  // Input handshake: accept when idle and both operands valid.
  logic inputs_valid;
  assign inputs_valid = in_valid_0 & in_valid_1;
  assign in_ready_0   = (state_r == ST_IDLE) & inputs_valid;
  assign in_ready_1   = (state_r == ST_IDLE) & inputs_valid;

  // Output handshake.
  assign out_valid = (state_r == ST_DONE);

  // Next-state / datapath.
  always_comb begin : next_state_logic
    state_next   = state_r;
    cnt_next     = cnt_r;
    quo_mag_next = quo_mag_r;
    rem_acc_next = rem_acc_r;
    divisor_next = divisor_r;

    case (state_r)
      ST_IDLE: begin : idle_case
        if (inputs_valid) begin : accept
          if (in_data_1 == {WIDTH{1'b0}}) begin : div_by_zero
            // RISC-V: quotient = all-ones (max unsigned), remainder = dividend.
            quo_mag_next = {WIDTH{1'b1}};
            rem_acc_next = {1'b0, in_data_0};
            state_next   = ST_DONE;
          end : div_by_zero
          else begin : start_compute
            quo_mag_next = in_data_0;            // shift source; becomes a / b
            rem_acc_next = {(WIDTH + 1){1'b0}};
            divisor_next = in_data_1;
            cnt_next     = {CNT_WIDTH{1'b0}};
            state_next   = ST_COMPUTE;
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
      state_r   <= ST_IDLE;
      cnt_r     <= {CNT_WIDTH{1'b0}};
      quo_mag_r <= {WIDTH{1'b0}};
      rem_acc_r <= {(WIDTH + 1){1'b0}};
      divisor_r <= {WIDTH{1'b0}};
    end : reset_block
    else begin : normal_block
      state_r   <= state_next;
      cnt_r     <= cnt_next;
      quo_mag_r <= quo_mag_next;
      rem_acc_r <= rem_acc_next;
      divisor_r <= divisor_next;
    end : normal_block
  end : state_update

  // Output taps: select quotient or remainder (no sign fix-up for unsigned).
  logic [WIDTH-1:0] quo_out;
  logic [WIDTH-1:0] rem_out;
  assign quo_out  = quo_mag_r;
  assign rem_out  = rem_acc_r[WIDTH-1:0];
  assign out_data = op_sel ? rem_out : quo_out;

endmodule : fu_div_rem_unsigned
