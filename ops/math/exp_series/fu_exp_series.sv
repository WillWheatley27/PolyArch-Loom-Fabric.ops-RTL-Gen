// fu_exp_series.sv -- Fabric FU for share group exp_series.
// op_list: math.exp, math.exp2, math.expm1
//   op_sel = 0 -> out = exp(x)    (math.exp)
//   op_sel = 1 -> out = exp2(x)   (math.exp2)
//   op_sel = 2 -> out = expm1(x)  (math.expm1)
//
// One shared 2^f core; op_sel selects argument pre-scale and post-correction.
// op_sel held config. Unary op. Latency 1.
//
// APPROXIMATE. COMPILE-TIME MINIMAX POLYNOMIAL (Horner) for 2^f over f in [0,1),
// baked per format. 2^y: y = n + f, n -> float exponent, 2^f in [1,2) = poly.
//   exp2: y = x.   exp: y = x*log2e.   expm1: exp then V + (-1.0).
// expm1's -1 reuses an inline parameterized IEEE-754 adder; RELATIVE accuracy
// near 0 degrades (cancellation), ABSOLUTE maintained. Overflow -> +Inf,
// underflow -> +0 (FTZ). PARAMETERIZED (EXP_W, MANT_W): fp32/fp64/bf16.

module fu_exp_series #(
  parameter  int unsigned EXP_W  = 8,
  parameter  int unsigned MANT_W = 23,
  localparam int unsigned WIDTH  = EXP_W + MANT_W + 1,
  localparam int unsigned BIAS   = (1 << (EXP_W - 1)) - 1,
  localparam int unsigned EXP_MAX = (1 << EXP_W) - 1,
  localparam int unsigned SIG_W  = MANT_W + 1,
  localparam int unsigned NORM_W = MANT_W + 4,
  localparam int unsigned ALN_W  = MANT_W + 5,
  localparam int unsigned LZW    = $clog2(NORM_W + 1),
  localparam int unsigned ES_W   = EXP_W + 2,
  localparam int unsigned FRAC   = MANT_W + 4,        // 2^f poly frac bits (matches generator)
  localparam int unsigned INTW   = EXP_W + 2,         // integer bits for n
  localparam int unsigned YW     = INTW + FRAC,       // y fixed-point width
  localparam int unsigned PCW    = FRAC + 4,          // poly coeff width
  localparam int unsigned E2DEG  = 6
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic [1:0]        op_sel,     // 0=math.exp 1=math.exp2 2=math.expm1
  input  logic [WIDTH-1:0]  in_data_0,
  input  logic              in_valid_0,
  output logic              in_ready_0,
  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic signed [31:0] LOG2E = 32'sd1549082005;   // log2(e) in Q2.30
  localparam logic [WIDTH-1:0]   NEG_ONE = {1'b1, EXP_W'(BIAS), {MANT_W{1'b0}}};   // -1.0
  localparam logic signed [PCW-1:0] EXP2F_C [0:E2DEG] = '{ 31'sd134217728, 31'sd93032606, 31'sd32243186, 31'sd7446484, 31'sd1299789, 31'sd166314, 31'sd29348 };

  function automatic logic [LZW-1:0] lzc(input logic [NORM_W-1:0] x);
    logic [LZW-1:0] n; logic f; integer i;
    begin n = '0; f = 1'b0;
      for (i = NORM_W-1; i >= 0; i = i-1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 1'b1; end
      lzc = n;
    end
  endfunction

  // Inline parameterized IEEE-754 adder (from fu_fp_add_sub): RNE, FTZ.
  // verilator lint_off UNUSEDSIGNAL
  function automatic logic [WIDTH-1:0] fp_add(input logic [WIDTH-1:0] a, input logic [WIDTH-1:0] b);
    logic sa, sb; logic [EXP_W-1:0] ea, eb; logic [MANT_W-1:0] ma, mb;
    logic an, bn, ai, bi, az, bz; logic [SIG_W-1:0] sga, sgb;
    logic bsgn, ssgn, addop; logic [EXP_W-1:0] bex, df; logic [SIG_W-1:0] bsig, ssig;
    logic [ALN_W-1:0] bm, sm, sal, raw; logic [NORM_W-1:0] nrm; logic stsh, stk;
    logic [LZW-1:0] sh; logic [MANT_W-1:0] m23, mf; logic gd, rup; logic [SIG_W-1:0] mr;
    logic signed [ES_W-1:0] es, es2; logic [WIDTH-1:0] r;
    begin
      sa=a[WIDTH-1]; ea=a[WIDTH-2:MANT_W]; ma=a[MANT_W-1:0];
      sb=b[WIDTH-1]; eb=b[WIDTH-2:MANT_W]; mb=b[MANT_W-1:0];
      an=(&ea)&(|ma); bn=(&eb)&(|mb); ai=(&ea)&(~|ma); bi=(&eb)&(~|mb);
      az=(ea=='0); bz=(eb=='0); sga={1'b1,ma}; sgb={1'b1,mb};
      bsgn='0;ssgn='0;addop='0;bex='0;bsig='0;ssig='0;df='0;bm='0;sm='0;sal='0;raw='0;
      nrm='0;stsh='0;stk='0;sh='0;m23='0;mf='0;gd='0;rup='0;mr='0;es='0;es2='0;
      r = {1'b0, {EXP_W{1'b1}}, 1'b1, {(MANT_W-1){1'b0}}};   // default qNaN
      if (an|bn)              r = {1'b0,{EXP_W{1'b1}},1'b1,{(MANT_W-1){1'b0}}};
      else if (ai&bi)         r = (sa==sb) ? {sa,{EXP_W{1'b1}},{MANT_W{1'b0}}} : {1'b0,{EXP_W{1'b1}},1'b1,{(MANT_W-1){1'b0}}};
      else if (ai)            r = {sa,{EXP_W{1'b1}},{MANT_W{1'b0}}};
      else if (bi)            r = {sb,{EXP_W{1'b1}},{MANT_W{1'b0}}};
      else if (az&bz)         r = {sa&sb,{(WIDTH-1){1'b0}}};
      else if (az)            r = {sb,eb,mb};
      else if (bz)            r = {sa,ea,ma};
      else begin
        if ((ea>eb)|((ea==eb)&(ma>=mb))) begin bsgn=sa;bex=ea;bsig=sga;ssgn=sb;ssig=sgb;df=ea-eb; end
        else begin bsgn=sb;bex=eb;bsig=sgb;ssgn=sa;ssig=sga;df=eb-ea; end
        addop=(bsgn==ssgn); bm={1'b0,bsig,3'b000}; sm={1'b0,ssig,3'b000};
        if (32'(df)>=ALN_W) begin sal='0; stsh=|ssig; end
        else begin sal=sm>>df; stsh=|(sm & ((ALN_W'(1)<<df)-ALN_W'(1))); end
        sal[0]=sal[0]|stsh;
        raw = addop ? (bm+sal) : (bm-sal);
        if (!addop & (raw=='0)) r = {WIDTH{1'b0}};
        else begin
          if (addop & raw[ALN_W-1]) begin nrm=raw[ALN_W-1:1]; es=signed'(ES_W'(bex))+signed'(ES_W'(1)); stk=raw[0]; end
          else if (addop)           begin nrm=raw[NORM_W-1:0]; es=signed'(ES_W'(bex));                    stk=1'b0; end
          else begin sh=lzc(raw[NORM_W-1:0]); nrm=raw[NORM_W-1:0]<<sh; es=signed'(ES_W'(bex))-signed'(ES_W'(sh)); stk=1'b0; end
          m23=nrm[MANT_W+2:3]; gd=nrm[2]; stk=stk|nrm[1]|nrm[0];
          rup=gd&(stk|m23[0]); mr={1'b0,m23}+SIG_W'(rup);
          if (mr[SIG_W-1]) begin mf='0; es2=es+signed'(ES_W'(1)); end else begin mf=mr[MANT_W-1:0]; es2=es; end
          if (es2>=signed'(ES_W'(EXP_MAX))) r={bsgn,{EXP_W{1'b1}},{MANT_W{1'b0}}};
          else if (es2<=0)                  r={bsgn,{EXP_W{1'b0}},{MANT_W{1'b0}}};
          else                              r={bsgn,es2[EXP_W-1:0],mf};
        end
      end
      fp_add = r;
    end
  endfunction
  // verilator lint_on UNUSEDSIGNAL

  logic        s_in, sat, use_log2e;
  logic [EXP_W-1:0]  e_in;
  logic [MANT_W-1:0] m_in;
  logic [SIG_W-1:0]  sig_in;
  logic signed [15:0] ish;
  // verilator lint_off UNUSEDSIGNAL
  logic [YW-1:0]       xfm;
  logic signed [YW+32:0] pr;
  logic signed [YW-1:0]  xf, yf;
  logic signed [PCW-1:0] acc;
  logic signed [2*PCW:0] pmul;
  logic signed [15:0]  biased;
  logic [FRAC-1:0]     f_frac;
  logic [MANT_W:0]     mant24;
  // verilator lint_on UNUSEDSIGNAL
  logic signed [15:0]  n;
  logic [FRAC:0]       pf;         // 2^f value in [1,2), Q.FRAC (leading 1 at bit FRAC)
  logic [MANT_W-1:0]   mant, mant_f;
  logic                guard, sticky, roundup;
  logic [WIDTH-1:0]    vexp, em1, conv_result;
  integer i;

  always_comb begin : datapath
    s_in = in_data_0[WIDTH-1]; e_in = in_data_0[WIDTH-2:MANT_W]; m_in = in_data_0[MANT_W-1:0];
    sig_in = {1'b1, m_in};

    // decode x -> Q(INTW).(FRAC); shift = e - BIAS + (FRAC - MANT_W) = e - BIAS + 4
    ish = signed'(16'(e_in)) - signed'(16'(BIAS)) + 16'sd4;
    if (e_in == '0)                          begin xfm = '0; sat = 1'b0; end
    else if (32'(e_in) >= (BIAS + INTW))      begin xfm = '0; sat = 1'b1; end
    else if (ish >= 0)                        begin xfm = YW'(sig_in) << ish[5:0]; sat = 1'b0; end
    else                                      begin xfm = YW'(sig_in) >> (-ish); sat = 1'b0; end
    xf = s_in ? -signed'(xfm) : signed'(xfm);

    // pre-scale by log2e for exp/expm1 (op_sel 0 and 2); exp2 (1) uses x
    use_log2e = (op_sel != 2'd1);
    pr = xf * LOG2E;
    yf = use_log2e ? YW'(pr >>> 30) : xf;

    // split y = n + f  (n = floor(y) via arithmetic shift; f = low bits, always >= 0)
    n      = 16'(yf >>> FRAC);
    f_frac = yf[FRAC-1:0];

    // 2^f via Horner minimax polynomial -> pf in [1,2), Q.FRAC
    acc = EXP2F_C[E2DEG];
    for (i = E2DEG - 1; i >= 0; i = i - 1) begin
      pmul = acc * $signed({1'b0, f_frac});
      acc  = PCW'(pmul >>> FRAC) + EXP2F_C[i];
    end
    pf = acc[FRAC:0];

    // encode significand pf (leading 1 at bit FRAC) with exponent n -> V
    mant    = pf[FRAC-1 -: MANT_W];
    guard   = pf[FRAC-MANT_W-1];               // = pf[2]
    sticky  = |pf[FRAC-MANT_W-2 : 0];          // = |pf[1:0]
    roundup = guard & (sticky | mant[0]);
    mant24  = {1'b0, mant} + (MANT_W+1)'(roundup);
    biased  = n + signed'(16'(BIAS)) + (mant24[MANT_W] ? 16'sd1 : 16'sd0);
    mant_f  = mant24[MANT_W] ? '0 : mant24[MANT_W-1:0];

    if (sat)                             vexp = s_in ? {WIDTH{1'b0}} : {1'b0,{EXP_W{1'b1}},{MANT_W{1'b0}}};
    else if (biased >= signed'(16'(EXP_MAX))) vexp = {1'b0,{EXP_W{1'b1}},{MANT_W{1'b0}}};
    else if (biased <= 0)                vexp = {WIDTH{1'b0}};
    else                                 vexp = {1'b0, biased[EXP_W-1:0], mant_f};

    // expm1 = V + (-1.0)
    em1 = fp_add(vexp, NEG_ONE);

    conv_result = op_sel[1] ? em1 : vexp;   // op_sel==2 -> expm1; 0,1 -> 2^y
  end : datapath

  logic fire;
  assign fire       = in_valid_0 & (~out_valid | out_ready);
  assign in_ready_0 = fire;

  always_ff @(posedge clk) begin : pipe
    if (!rst_n) begin out_valid <= 1'b0; out_data <= {WIDTH{1'b0}}; end
    else begin
      if (fire)           begin out_data <= conv_result; out_valid <= 1'b1; end
      else if (out_ready) out_valid <= 1'b0;
    end
  end : pipe

endmodule : fu_exp_series
