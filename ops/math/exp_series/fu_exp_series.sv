// fu_exp_series.sv -- Fabric FU for share group exp_series.
// op_list: math.exp, math.exp2, math.expm1
//   op_sel = 0 -> out = exp(x)    (math.exp)
//   op_sel = 1 -> out = exp2(x)   (math.exp2)
//   op_sel = 2 -> out = expm1(x)  (math.expm1)
//
// One shared 2^f core (LUT + linear interpolation); op_sel selects argument
// pre-scale and post-correction. op_sel held config. Unary op. Latency 1.
//
// APPROXIMATE, NOT bit-exact. No loom reference (loom rejects transcendentals).
// 2^y: y = n + f, n -> float exponent, 2^f in [1,2) from a 129-entry LUT.
//   exp2:  y = x.        exp: y = x*log2e.   expm1: exp then V + (-1.0).
// expm1's -1 reuses an inline copy of the group-10 IEEE-754 FP adder; its
// RELATIVE accuracy degrades for tiny x (exp-1 cancellation) -- ABSOLUTE
// accuracy is maintained. Overflow -> +Inf, underflow -> +0 (FTZ). binary32 I/O.

module fu_exp_series #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic [1:0]        op_sel,     // 0=math.exp 1=math.exp2 2=math.expm1

  input  logic [WIDTH-1:0]  in_data_0,  // x (binary32)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,   // exp/exp2/expm1 of x, binary32
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic signed [31:0] LOG2E = 32'sd1549082005;   // log2(e) in Q2.30
  localparam logic [23:0] TWO_F [0:128] = '{
    24'd8388608, 24'd8434157, 24'd8479954, 24'd8525999, 24'd8572295, 24'd8618841, 24'd8665641,
    24'd8712694, 24'd8760003, 24'd8807569, 24'd8855394, 24'd8903477, 24'd8951823, 24'd9000430,
    24'd9049301, 24'd9098438, 24'd9147842, 24'd9197514, 24'd9247455, 24'd9297668, 24'd9348154,
    24'd9398913, 24'd9449948, 24'd9501261, 24'd9552851, 24'd9604722, 24'd9656875, 24'd9709311,
    24'd9762032, 24'd9815039, 24'd9868333, 24'd9921917, 24'd9975792, 24'd10029960,
    24'd10084422, 24'd10139179, 24'd10194234, 24'd10249587, 24'd10305242, 24'd10361198,
    24'd10417458, 24'd10474024, 24'd10530897, 24'd10588079, 24'd10645571, 24'd10703375,
    24'd10761494, 24'd10819928, 24'd10878679, 24'd10937749, 24'd10997140, 24'd11056853,
    24'd11116891, 24'd11177254, 24'd11237946, 24'd11298967, 24'd11360319, 24'd11422004,
    24'd11484025, 24'd11546382, 24'd11609078, 24'd11672114, 24'd11735492, 24'd11799215,
    24'd11863283, 24'd11927700, 24'd11992466, 24'd12057584, 24'd12123055, 24'd12188882,
    24'd12255067, 24'd12321610, 24'd12388516, 24'd12455784, 24'd12523418, 24'd12591419,
    24'd12659789, 24'd12728530, 24'd12797645, 24'd12867135, 24'd12937002, 24'd13007249,
    24'd13077877, 24'd13148888, 24'd13220286, 24'd13292070, 24'd13364245, 24'd13436812,
    24'd13509772, 24'd13583129, 24'd13656884, 24'd13731039, 24'd13805598, 24'd13880561,
    24'd13955931, 24'd14031710, 24'd14107901, 24'd14184505, 24'd14261526, 24'd14338964,
    24'd14416824, 24'd14495106, 24'd14573813, 24'd14652947, 24'd14732511, 24'd14812507,
    24'd14892937, 24'd14973805, 24'd15055111, 24'd15136859, 24'd15219050, 24'd15301688,
    24'd15384775, 24'd15468313, 24'd15552304, 24'd15636752, 24'd15721658, 24'd15807025,
    24'd15892855, 24'd15979152, 24'd16065917, 24'd16153153, 24'd16240863, 24'd16329050,
    24'd16417715, 24'd16506861, 24'd16596492, 24'd16686609, 24'd16777215 };

  function automatic logic [4:0] lzc27(input logic [26:0] x);
    logic [4:0] n; logic f; integer i;
    begin n = 5'd0; f = 1'b0;
      for (i = 26; i >= 0; i = i - 1) if (!f) begin if (x[i]) f = 1'b1; else n = n + 5'd1; end
      lzc27 = n;
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

  logic        s_in;
  logic [7:0]  e_in;
  logic [22:0] m_in;
  logic [23:0] sig_in;
  logic signed [9:0] ish;
  // verilator lint_off UNUSEDSIGNAL
  logic [31:0]        xfm;
  logic signed [63:0] pr;     // product; only mid bits used
  logic signed [31:0] xf, yf;
  logic [21:0]        ff;
  logic [38:0]        prodg;  // low bits unused after >>15
  logic signed [9:0]  biased;
  logic [23:0]        g;      // g[23] = implicit leading 1 (unused)
  // verilator lint_on UNUSEDSIGNAL
  logic        sat, use_log2e;
  logic signed [9:0] n;
  logic [7:0]  idx, idx1;
  logic [14:0] fr;
  logic [23:0] t0, t1, delta;
  logic [22:0] mant;
  logic [31:0] vexp, em1, conv_result;

  always_comb begin : datapath
    s_in = in_data_0[31]; e_in = in_data_0[30:23]; m_in = in_data_0[22:0];
    sig_in = {1'b1, m_in};

    // decode x -> Q10.22
    ish = $signed({2'b00, e_in}) - 10'sd128;
    if (e_in == 8'd0)        begin xfm = 32'd0; sat = 1'b0; end
    else if (e_in >= 8'd134) begin xfm = 32'd0; sat = 1'b1; end   // |x| >= 128
    else if (ish >= 10'sd0)  begin xfm = {8'd0, sig_in} << ish[4:0]; sat = 1'b0; end
    else                     begin xfm = {8'd0, sig_in} >> (-ish); sat = 1'b0; end
    xf = s_in ? -$signed(xfm) : $signed(xfm);

    // pre-scale by log2e for exp/expm1 (op_sel 0 and 2); exp2 (1) uses x directly
    use_log2e = (op_sel != 2'd1);
    pr = $signed(xf) * $signed(LOG2E);
    yf = use_log2e ? pr[61:30] : xf;

    // split y = n + f
    n   = $signed(yf[31:22]);     // integer part (Q10.22 top 10 bits)
    ff  = yf[21:0];
    idx = {1'b0, ff[21:15]};
    fr  = ff[14:0];
    idx1 = idx + 8'd1;

    // 2^f via LUT + linear interpolation
    t0 = TWO_F[idx]; t1 = TWO_F[idx1];
    delta = t1 - t0;
    prodg = {9'd0, fr} * {15'd0, delta};
    g = t0 + prodg[38:15];
    mant = g[22:0];

    // assemble V = 2^y (clamp overflow/underflow)
    biased = n + 10'sd127;
    if (sat)                     vexp = s_in ? 32'd0 : 32'h7F80_0000;
    else if (biased >= 10'sd255) vexp = 32'h7F80_0000;
    else if (biased <= 10'sd0)   vexp = 32'd0;
    else                         vexp = {1'b0, biased[7:0], mant};

    // expm1 = V + (-1.0)
    em1 = fp_add(vexp, 32'hBF80_0000);

    conv_result = op_sel[1] ? em1 : vexp;   // op_sel==2 -> expm1; 0,1 -> 2^y
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

endmodule : fu_exp_series
