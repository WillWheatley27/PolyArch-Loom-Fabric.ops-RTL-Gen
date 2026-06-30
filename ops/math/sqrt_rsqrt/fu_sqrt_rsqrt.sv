// fu_sqrt_rsqrt.sv -- Fabric FU for share group sqrt_rsqrt.
// op_list: math.sqrt, math.rsqrt
//   op_sel = 0 -> out = sqrt(x)    (math.sqrt)
//   op_sel = 1 -> out = rsqrt(x)   (math.rsqrt)  1/sqrt(x)
//
// One shared LUT core; op_sel selects the sqrt vs rsqrt mantissa table and the
// exponent sign. op_sel held config. Unary op. Intrinsic latency 1.
//
// APPROXIMATE, NOT bit-exact. No simulatable loom reference. binary32, FTZ.
// For x = 1.m * 2^e (e = 2q + r): sqrt = [SQRT_M(m)*(r?sqrt2:1)] * 2^q;
// rsqrt = [RSQRT_M(m)*(r?1/sqrt2:1)] * 2^-q. Two 129-entry Q.30 LUTs + linear
// interpolation, normalize to [1,2), clz/RNE encode. Specials: x<0 -> NaN,
// sqrt(+0)=+0 sqrt(-0)=-0, rsqrt(+0)=+Inf rsqrt(-0)=-Inf, sqrt(+Inf)=+Inf
// rsqrt(+Inf)=+0.

module fu_sqrt_rsqrt #(
  parameter int unsigned WIDTH = 32
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              op_sel,     // 0 = math.sqrt (sqrt), 1 = math.rsqrt (rsqrt)

  input  logic [WIDTH-1:0]  in_data_0,  // x (binary32)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  localparam logic [31:0] SQRT2    = 32'd1518500250;   // sqrt(2) in Q.30
  localparam logic [31:0] INVSQRT2 = 32'd759250125;    // 1/sqrt(2) in Q.30
  localparam logic [31:0] QNAN     = 32'h7FC0_0000;
  localparam logic [31:0] POSINF   = 32'h7F80_0000;
  localparam logic [31:0] NEGINF   = 32'hFF80_0000;

  localparam logic [31:0] SQRT_M [0:128] = '{
    32'd1073741824, 32'd1077927968, 32'd1082097918, 32'd1086251860, 32'd1090389977,
    32'd1094512449, 32'd1098619452, 32'd1102711159, 32'd1106787739, 32'd1110849359,
    32'd1114896182, 32'd1118928370, 32'd1122946079, 32'd1126949464, 32'd1130938678,
    32'd1134913870, 32'd1138875187, 32'd1142822774, 32'd1146756771, 32'd1150677318,
    32'd1154584553, 32'd1158478610, 32'd1162359621, 32'd1166227717, 32'd1170083026,
    32'd1173925673, 32'd1177755783, 32'd1181573478, 32'd1185378878, 32'd1189172100,
    32'd1192953261, 32'd1196722475, 32'd1200479854, 32'd1204225510, 32'd1207959552,
    32'd1211682086, 32'd1215393219, 32'd1219093055, 32'd1222781696, 32'd1226459243,
    32'd1230125796, 32'd1233781453, 32'd1237426310, 32'd1241060463, 32'd1244684005,
    32'd1248297028, 32'd1251899625, 32'd1255491884, 32'd1259073893, 32'd1262645741,
    32'd1266207514, 32'd1269759295, 32'd1273301169, 32'd1276833217, 32'd1280355523,
    32'd1283868164, 32'd1287371222, 32'd1290864773, 32'd1294348895, 32'd1297823663,
    32'd1301289153, 32'd1304745438, 32'd1308192592, 32'd1311630686, 32'd1315059792,
    32'd1318479979, 32'd1321891318, 32'd1325293875, 32'd1328687719, 32'd1332072916,
    32'd1335449532, 32'd1338817632, 32'd1342177280, 32'd1345528539, 32'd1348871473,
    32'd1352206141, 32'd1355532607, 32'd1358850929, 32'd1362161168, 32'd1365463381,
    32'd1368757628, 32'd1372043966, 32'd1375322451, 32'd1378593139, 32'd1381856086,
    32'd1385111346, 32'd1388358974, 32'd1391599023, 32'd1394831545, 32'd1398056593,
    32'd1401274219, 32'd1404484474, 32'd1407687407, 32'd1410883069, 32'd1414071510,
    32'd1417252777, 32'd1420426919, 32'd1423593984, 32'd1426754019, 32'd1429907071,
    32'd1433053185, 32'd1436192407, 32'd1439324782, 32'd1442450355, 32'd1445569171,
    32'd1448681271, 32'd1451786701, 32'd1454885502, 32'd1457977717, 32'd1461063388,
    32'd1464142555, 32'd1467215261, 32'd1470281545, 32'd1473341447, 32'd1476395008,
    32'd1479442266, 32'd1482483261, 32'd1485518030, 32'd1488546612, 32'd1491569045,
    32'd1494585366, 32'd1497595611, 32'd1500599818, 32'd1503598022, 32'd1506590260,
    32'd1509576567, 32'd1512556978, 32'd1515531527, 32'd1518500250 };
  localparam logic [31:0] RSQRT_M [0:128] = '{
    32'd1073741824, 32'd1069571937, 32'd1065450257, 32'd1061375863, 32'd1057347856,
    32'd1053365364, 32'd1049427536, 32'd1045533543, 32'd1041682578, 32'd1037873853,
    32'd1034106604, 32'd1030380081, 32'd1026693558, 32'd1023046322, 32'd1019437682,
    32'd1015866961, 32'd1012333500, 32'd1008836655, 32'd1005375799, 32'd1001950318,
    32'd998559613, 32'd995203101, 32'd991880210, 32'd988590382, 32'd985333074, 32'd982107753,
    32'd978913898, 32'd975751001, 32'd972618566, 32'd969516107, 32'd966443148, 32'd963399225,
    32'd960383883, 32'd957396679, 32'd954437177, 32'd951504951, 32'd948599586, 32'd945720673,
    32'd942867814, 32'd940040618, 32'd937238702, 32'd934461692, 32'd931709222, 32'd928980931,
    32'd926276469, 32'd923595489, 32'd920937655, 32'd918302635, 32'd915690104, 32'd913099745,
    32'd910531246, 32'd907984300, 32'd905458609, 32'd902953878, 32'd900469818, 32'd898006148,
    32'd895562589, 32'd893138870, 32'd890734723, 32'd888349887, 32'd885984104, 32'd883637122,
    32'd881308694, 32'd878998575, 32'd876706528, 32'd874432318, 32'd872175715, 32'd869936492,
    32'd867714429, 32'd865509306, 32'd863320910, 32'd861149030, 32'd858993459, 32'd856853995,
    32'd854730438, 32'd852622592, 32'd850530263, 32'd848453263, 32'd846391405, 32'd844344506,
    32'd842312387, 32'd840294869, 32'd838291779, 32'd836302947, 32'd834328203, 32'd832367382,
    32'd830420321, 32'd828486860, 32'd826566842, 32'd824660110, 32'd822766514, 32'd820885902,
    32'd819018128, 32'd817163045, 32'd815320510, 32'd813490383, 32'd811672525, 32'd809866800,
    32'd808073073, 32'd806291212, 32'd804521086, 32'd802762568, 32'd801015531, 32'd799279851,
    32'd797555404, 32'd795842072, 32'd794139734, 32'd792448274, 32'd790767575, 32'd789097526,
    32'd787438013, 32'd785788926, 32'd784150157, 32'd782521599, 32'd780903145, 32'd779294692,
    32'd777696137, 32'd776107379, 32'd774528319, 32'd772958857, 32'd771398898, 32'd769848346,
    32'd768307107, 32'd766775087, 32'd765252196, 32'd763738342, 32'd762233438, 32'd760737394,
    32'd759250125 };

  logic        s;
  logic [7:0]  e_in;
  logic [22:0] m_in;
  logic        nan_in, inf_in, zero_in, neg_in;
  logic signed [9:0] e, q, qexp;
  logic [7:0]  idx, idx1;
  logic [15:0] frac;
  logic        r_odd;
  logic [31:0] t0u, t1u, base, factor;
  // verilator lint_off UNUSEDSIGNAL
  logic signed [32:0] dels;
  logic signed [63:0] prods, base_s;
  logic [63:0] mprod;
  logic [31:0] mfx, mf, mf_n;       // mf_n[31] possibly unused
  // verilator lint_on UNUSEDSIGNAL
  logic        addexp_m1;
  logic [22:0] mant23, mant_f;
  logic        guard_e, sticky_e, roundup_e;
  logic [23:0] mant24;
  logic signed [10:0] biased, bexp;
  logic [31:0] core_enc, conv_result;

  always_comb begin : datapath
    s = in_data_0[31]; e_in = in_data_0[30:23]; m_in = in_data_0[22:0];
    nan_in  = (e_in == 8'hFF) & (|m_in);
    inf_in  = (e_in == 8'hFF) & (~|m_in);
    zero_in = (e_in == 8'd0);                  // FTZ
    neg_in  = s & ~zero_in;                    // x < 0 (incl -Inf)

    // exponent split: e = 2q + r
    e     = $signed({2'b00, e_in}) - 10'sd127;
    q     = e >>> 1;
    r_odd = e[0];
    qexp  = op_sel ? -q : q;

    // mantissa LUT interpolation (Q.30); rsqrt table decreases -> signed delta
    idx   = {1'b0, m_in[22:16]};
    idx1  = idx + 8'd1;
    frac  = m_in[15:0];
    t0u   = op_sel ? RSQRT_M[idx]  : SQRT_M[idx];
    t1u   = op_sel ? RSQRT_M[idx1] : SQRT_M[idx1];
    dels  = $signed({1'b0, t1u}) - $signed({1'b0, t0u});
    prods = $signed({1'b0, frac}) * dels;
    base_s = $signed({32'd0, t0u}) + (prods >>> 16);
    base  = base_s[31:0];

    // odd-exponent factor (sqrt2 / invsqrt2)
    factor = op_sel ? INVSQRT2 : SQRT2;
    mprod  = base * factor;
    mfx    = mprod[61:30];                      // (base*factor) >> 30, Q.30
    mf     = r_odd ? mfx : base;

    // normalize mf to [1,2) i.e. [2^30, 2^31)
    if (mf[30]) begin mf_n = mf;       addexp_m1 = 1'b0; end
    else        begin mf_n = mf << 1;  addexp_m1 = 1'b1; end
    biased = 11'(qexp) - (addexp_m1 ? 11'sd1 : 11'sd0) + 11'sd127;

    // encode (Q.30, bit30 = leading 1) -> binary32, RNE
    mant23   = mf_n[29:7];
    guard_e  = mf_n[6];
    sticky_e = |mf_n[5:0];
    roundup_e = guard_e & (sticky_e | mant23[0]);
    mant24   = {1'b0, mant23} + {23'd0, roundup_e};
    if (mant24[23]) begin mant_f = 23'd0;          bexp = biased + 11'sd1; end
    else            begin mant_f = mant24[22:0];   bexp = biased;          end
    if (bexp >= 11'sd255)     core_enc = POSINF;
    else if (bexp <= 11'sd0)  core_enc = 32'd0;
    else                      core_enc = {1'b0, bexp[7:0], mant_f};

    // specials (priority)
    if (nan_in)        conv_result = QNAN;
    else if (neg_in)   conv_result = QNAN;                          // x < 0
    else if (inf_in)   conv_result = op_sel ? 32'd0 : POSINF;        // rsqrt(+Inf)=0, sqrt(+Inf)=+Inf
    else if (zero_in)  conv_result = op_sel ? (s ? NEGINF : POSINF) : {s, 31'd0};
    else               conv_result = core_enc;
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

endmodule : fu_sqrt_rsqrt
