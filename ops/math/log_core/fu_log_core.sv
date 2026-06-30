// fu_log_core.sv -- Fabric FU for share group log_core.
// op_list: math.log, math.log2, math.log10, math.log1p
//   op_sel = 0 -> out = log(x)     (math.log)  natural log
//   op_sel = 1 -> out = log2(x)    (math.log2)
//   op_sel = 2 -> out = log10(x)   (math.log10)
//   op_sel = 3 -> out = log1p(x)   (math.log1p)  ln(1+x)
//
// One shared log2 core: for x = 2^e * m (m in [1,2)), log2(x) = e + log2(m),
// with log2(m) from a 129-entry LUT + linear interpolation. Output scaled by
// 1 (log2), ln2 (log), or 1/log2(10) (log10). log1p pre-adds 1.0 via an inline
// copy of the group-10 FP adder, then takes the natural-log path. op_sel held
// config. Unary op. Latency 1.
//
// APPROXIMATE, NOT bit-exact. No loom reference. binary32 I/O. Subnormals FTZ.
// Specials (IEEE/libm): x<0 -> NaN, x=+/-0 -> -Inf, x=1 -> +0, +Inf -> +Inf;
// log1p(-1) -> -Inf, log1p(x<-1) -> NaN (fall out of the log path on 1+x).
// log1p's relative accuracy near x=0 is limited (1+x rounding); abs-accurate.

module fu_log_core #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic [1:0]        op_sel,     // 0=math.log 1=math.log2 2=math.log10 3=math.log1p

  input  logic [WIDTH-1:0]  in_data_0,  // x (binary32)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,   // log/log2/log10/log1p of x, binary32
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic signed [31:0] LN2        = 32'sd5814540;   // ln2 in Q.23
  localparam logic signed [31:0] INVLOG2_10 = 32'sd2525223;   // 1/log2(10) in Q.23
  localparam logic signed [31:0] ONE_Q23    = 32'sd8388608;   // 1.0 in Q.23
  localparam logic [31:0]        ONE_F32     = 32'h3F80_0000;  // 1.0 binary32
  localparam logic [31:0]        QNAN        = 32'h7FC0_0000;
  localparam logic [31:0]        POSINF      = 32'h7F80_0000;
  localparam logic [31:0]        NEGINF      = 32'hFF80_0000;

  localparam logic signed [31:0] LOG2_M [0:128] = '{
    32'sd0, 32'sd94181, 32'sd187635, 32'sd280372, 32'sd372405, 32'sd463743, 32'sd554396,
    32'sd644376, 32'sd733691, 32'sd822353, 32'sd910369, 32'sd997750, 32'sd1084505,
    32'sd1170642, 32'sd1256170, 32'sd1341098, 32'sd1425434, 32'sd1509187, 32'sd1592364,
    32'sd1674973, 32'sd1757022, 32'sd1838519, 32'sd1919470, 32'sd1999884, 32'sd2079767,
    32'sd2159126, 32'sd2237968, 32'sd2316299, 32'sd2394127, 32'sd2471458, 32'sd2548298,
    32'sd2624652, 32'sd2700529, 32'sd2775932, 32'sd2850868, 32'sd2925344, 32'sd2999364,
    32'sd3072933, 32'sd3146059, 32'sd3218745, 32'sd3290997, 32'sd3362820, 32'sd3434220,
    32'sd3505201, 32'sd3575768, 32'sd3645926, 32'sd3715679, 32'sd3785033, 32'sd3853992,
    32'sd3922560, 32'sd3990741, 32'sd4058541, 32'sd4125963, 32'sd4193011, 32'sd4259690,
    32'sd4326004, 32'sd4391956, 32'sd4457551, 32'sd4522792, 32'sd4587683, 32'sd4652228,
    32'sd4716431, 32'sd4780295, 32'sd4843824, 32'sd4907021, 32'sd4969890, 32'sd5032434,
    32'sd5094656, 32'sd5156560, 32'sd5218149, 32'sd5279426, 32'sd5340394, 32'sd5401057,
    32'sd5461417, 32'sd5521478, 32'sd5581242, 32'sd5640713, 32'sd5699892, 32'sd5758784,
    32'sd5817390, 32'sd5875714, 32'sd5933758, 32'sd5991526, 32'sd6049018, 32'sd6106239,
    32'sd6163191, 32'sd6219876, 32'sd6276297, 32'sd6332455, 32'sd6388355, 32'sd6443997,
    32'sd6499385, 32'sd6554520, 32'sd6609406, 32'sd6664043, 32'sd6718435, 32'sd6772584,
    32'sd6826491, 32'sd6880160, 32'sd6933591, 32'sd6986788, 32'sd7039752, 32'sd7092485,
    32'sd7144989, 32'sd7197266, 32'sd7249319, 32'sd7301148, 32'sd7352757, 32'sd7404147,
    32'sd7455319, 32'sd7506275, 32'sd7557019, 32'sd7607550, 32'sd7657871, 32'sd7707984,
    32'sd7757890, 32'sd7807591, 32'sd7857089, 32'sd7906385, 32'sd7955481, 32'sd8004379,
    32'sd8053080, 32'sd8101586, 32'sd8149898, 32'sd8198018, 32'sd8245948, 32'sd8293688,
    32'sd8341241, 32'sd8388608 };

  function automatic logic [4:0] lzc27(input logic [26:0] x);
    logic [4:0] n; logic f; integer i;
    begin n = 5'd0; f = 1'b0;
      for (i = 26; i >= 0; i = i - 1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 5'd1; end
      lzc27 = n;
    end
  endfunction

  function automatic logic [4:0] clz32(input logic [31:0] x);
    logic [4:0] n; logic f; integer i;
    begin n = 5'd0; f = 1'b0;
      for (i = 31; i >= 0; i = i - 1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 5'd1; end
      clz32 = n;
    end
  endfunction

  // Inline IEEE-754 binary32 add (group-10 logic): FTZ, round-to-nearest-even.
  // verilator lint_off UNUSEDSIGNAL
  function automatic logic [31:0] fp_add(input logic [31:0] a, input logic [31:0] b);
    logic sa, sb; logic [7:0] ea, eb; logic [22:0] ma, mb;
    logic an, bn, ai, bi, az, bz; logic [23:0] sga, sgb;
    logic bsgn, ssgn, addop; logic [7:0] bex; logic [23:0] bsig, ssig; logic [7:0] df;
    logic [27:0] bm, sm, sal, raw; logic [26:0] nrm; logic stsh, stk;
    logic [4:0] sh; logic [22:0] m23, mf; logic gd, rup; logic [23:0] mr;
    logic signed [9:0] es, es2; logic [31:0] r;
    begin
      sa=a[31]; ea=a[30:23]; ma=a[22:0]; sb=b[31]; eb=b[30:23]; mb=b[22:0];
      an=(ea==8'hFF)&(|ma); bn=(eb==8'hFF)&(|mb); ai=(ea==8'hFF)&(~|ma); bi=(eb==8'hFF)&(~|mb);
      az=(ea==8'd0); bz=(eb==8'd0); sga={1'b1,ma}; sgb={1'b1,mb};
      bsgn=1'b0; ssgn=1'b0; addop=1'b0; bex=8'd0; bsig=24'd0; ssig=24'd0; df=8'd0;
      bm=28'd0; sm=28'd0; sal=28'd0; raw=28'd0; nrm=27'd0; stsh=1'b0; stk=1'b0;
      sh=5'd0; m23=23'd0; mf=23'd0; gd=1'b0; rup=1'b0; mr=24'd0; es=10'sd0; es2=10'sd0; r=32'd0;
      if (an | bn)             r = 32'h7FC0_0000;
      else if (ai & bi)        r = (sa==sb) ? {sa,8'hFF,23'd0} : 32'h7FC0_0000;
      else if (ai)             r = {sa,8'hFF,23'd0};
      else if (bi)             r = {sb,8'hFF,23'd0};
      else if (az & bz)        r = {sa & sb, 31'd0};
      else if (az)             r = {sb, eb, mb};
      else if (bz)             r = {sa, ea, ma};
      else begin
        if ((ea>eb)|((ea==eb)&(ma>=mb))) begin bsgn=sa;bex=ea;bsig=sga;ssgn=sb;ssig=sgb;df=ea-eb; end
        else begin bsgn=sb;bex=eb;bsig=sgb;ssgn=sa;ssig=sga;df=eb-ea; end
        addop=(bsgn==ssgn);
        bm={1'b0,bsig,3'b000}; sm={1'b0,ssig,3'b000};
        if (df>=8'd28) begin sal=28'd0; stsh=|ssig; end
        else begin sal=sm>>df[4:0]; stsh=|(sm & ((28'd1<<df[4:0])-28'd1)); end
        sal[0]=sal[0]|stsh;
        raw = addop ? (bm+sal) : (bm-sal);
        if (!addop & (raw==28'd0)) r = 32'h0000_0000;
        else begin
          if (addop & raw[27])  begin nrm=raw[27:1]; es=$signed({2'b00,bex})+10'sd1; stk=raw[0]; end
          else if (addop)       begin nrm=raw[26:0]; es=$signed({2'b00,bex});        stk=1'b0;   end
          else begin sh=lzc27(raw[26:0]); nrm=raw[26:0]<<sh; es=$signed({2'b00,bex})-$signed({5'd0,sh}); stk=1'b0; end
          m23=nrm[25:3]; gd=nrm[2]; stk=stk|nrm[1]|nrm[0];
          rup=gd&(stk|m23[0]); mr={1'b0,m23}+{23'd0,rup};
          if (mr[23]) begin mf=23'd0; es2=es+10'sd1; end else begin mf=mr[22:0]; es2=es; end
          if (es2>=10'sd255)     r={bsgn,8'hFF,23'd0};
          else if (es2<=10'sd0)  r={bsgn,8'd0,23'd0};
          else                   r={bsgn,es2[7:0],mf};
        end
      end
      fp_add = r;
    end
  endfunction
  // verilator lint_on UNUSEDSIGNAL

  logic [31:0] xv;            // value the log is taken of (x, or 1+x for log1p)
  logic        svx, nanx, infx, zerox;
  logic [7:0]  evx8;
  logic [22:0] mvx;
  logic signed [9:0]  ev;
  logic signed [63:0] ev64;
  logic [7:0]  idx, idx1;
  logic [15:0] frac;
  logic [23:0] l0u, l1u, dlu;
  logic [24:0] interp;
  logic [24:0] scale;
  // verilator lint_off UNUSEDSIGNAL
  logic [47:0] prodg;         // interp product (16x24); low 16 bits dropped
  logic signed [63:0] log2core, scale_s, prodm, res_q23, res_abs;
  logic [31:0] norm_e;        // norm_e[31] = implicit leading 1
  // verilator lint_on UNUSEDSIGNAL
  logic [31:0] mag32;
  logic [4:0]  clz_e;
  logic [22:0] mant_e, mant_fe;
  logic        guard_e, sticky_e, roundup_e, rsign;
  logic [23:0] mant24_e;
  logic signed [9:0] exp_be;
  logic [31:0] core_enc, conv_result;

  always_comb begin : datapath
    // operand the log acts on (pre-add 1.0 for log1p)
    xv   = (op_sel == 2'd3) ? fp_add(in_data_0, ONE_F32) : in_data_0;
    svx  = xv[31]; evx8 = xv[30:23]; mvx = xv[22:0];
    nanx = (evx8 == 8'hFF) & (|mvx);
    infx = (evx8 == 8'hFF) & (~|mvx);
    zerox = (evx8 == 8'd0);                 // FTZ: subnormal/zero -> zero

    // ---- log2 core: log2(xv) = e + log2(m) ----
    ev   = $signed({2'b00, evx8}) - 10'sd127;
    idx  = {1'b0, mvx[22:16]};
    frac = mvx[15:0];
    idx1 = idx + 8'd1;
    l0u  = LOG2_M[idx][23:0];
    l1u  = LOG2_M[idx1][23:0];
    dlu  = l1u - l0u;
    prodg  = {32'd0, frac} * {24'd0, dlu};
    interp = {1'b0, l0u} + {1'b0, prodg[39:16]};   // Q.23, in [0, 2^23]

    // scale select: log2 *1, log *ln2, log10 *1/log2(10), log1p *ln2
    case (op_sel)
      2'd1:    scale = 25'(ONE_Q23);
      2'd2:    scale = 25'(INVLOG2_10);
      default: scale = 25'(LN2);
    endcase

    // log2core (Q.23) -> scale -> result (Q.23)
    ev64     = 64'(ev);                             // sign-extend 10 -> 64
    log2core = (ev64 <<< 23) + $signed({39'd0, interp});
    scale_s  = $signed({39'd0, scale});
    prodm    = log2core * scale_s;
    res_q23  = prodm >>> 23;

    // ---- encode signed Q.23 result -> binary32 (RNE) ----
    rsign   = res_q23[63];
    res_abs = rsign ? (~res_q23 + 64'sd1) : res_q23;
    mag32   = res_abs[31:0];
    clz_e   = clz32(mag32);
    norm_e  = mag32 << clz_e;
    mant_e  = norm_e[30:8];
    guard_e = norm_e[7];
    sticky_e = |norm_e[6:0];
    roundup_e = guard_e & (sticky_e | mant_e[0]);
    mant24_e = {1'b0, mant_e} + {23'd0, roundup_e};
    exp_be  = 10'sd135 - $signed({5'd0, clz_e});
    if (mant24_e[23]) begin mant_fe = 23'd0;          exp_be = exp_be + 10'sd1; end
    else              begin mant_fe = mant24_e[22:0];                            end
    if (mag32 == 32'd0)        core_enc = {rsign, 31'd0};
    else if (exp_be <= 10'sd0) core_enc = {rsign, 8'd0, 23'd0};
    else                       core_enc = {rsign, exp_be[7:0], mant_fe};

    // ---- specials (priority) ----
    if (nanx)                 conv_result = QNAN;
    else if (svx & ~zerox)    conv_result = QNAN;     // negative -> NaN (incl x<-1 for log1p)
    else if (zerox)           conv_result = NEGINF;   // +/-0 -> -Inf (log1p(-1) -> -Inf)
    else if (infx)            conv_result = POSINF;   // +Inf -> +Inf
    else                      conv_result = core_enc;
  end : datapath

  // ---- latency-1 handshake (unary) ----
  logic fire;
  assign fire       = in_valid_0 & (~out_valid | out_ready);
  assign in_ready_0 = fire;

  always_ff @(posedge clk) begin : pipe
    if (!rst_n) begin
      out_valid <= 1'b0; out_data <= {WIDTH{1'b0}};
    end else begin
      if (fire)           begin out_data <= conv_result; out_valid <= 1'b1; end
      else if (out_ready) out_valid <= 1'b0;
    end
  end : pipe

endmodule : fu_log_core
