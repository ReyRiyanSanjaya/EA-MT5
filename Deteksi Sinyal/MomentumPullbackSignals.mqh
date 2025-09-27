// MomentumPullbackSignals.mqh
// Library untuk deteksi sinyal momentum + pullback untuk scalping (M5 default)
// ==============================================================
// Ringkasan
// --------------------------------------------------------------
// Library ini mendeteksi pola "momentum 3+ candle" lalu pullback candle
// yang body-nya lebih besar dari candle sebelumnya (sinyal masuk). Dirancang
// untuk scalping timeframe M5 (juga bekerja di M1). Fitur:
// - Deteksi 3 atau lebih candle naik/ turun beruntun
// - Identifikasi candle pullback: arah berlawanan, body lebih besar dari candle sebelumnya
// - Filter pola candle (engulfing, pinbar/hammer) untuk akurasi
// - Fungsi optimasi parameter (SL/TP, minimal body, konfirmasi)
// - Perhitungan lot berdasarkan risk percent + opsi fixed lot
// - Fungsi manajemen posisi: close on profit ketika pullback baru muncul, dan re-entry
// - API publik mudah dipanggil dari App.mqh
//
// Catatan: lakukan backtest & optimasi di Strategy Tester untuk mendapatkan
// parameter terbaik pada simbol / broker Anda.
// ==============================================================

// ==============================================================
// Dokumentasi lengkap (cara penggunaan)
// --------------------------------------------------------------
// 1) Simpan file ini sebagai MomentumPullbackSignals.mqh ke folder Include/ proyek Anda.
// 2) Di App.mqh atau EA utama tambahkan:
//    #include "MomentumPullbackSignals.mqh"
//    void OnInit() { InitMomentumSignals(); }
//    void OnTick() { CallSignalsAndTrade(PERIOD_M5); }
// 3) Atur parameter sesuai kebutuhan sebelum trading (opsional):
//    SetMomentumRiskPercent(1.0);        // % balance per trade
//    SetMomentumSLTP(15,25);             // SL 15 pips, TP 25 pips
//    SetMomentumFixedLot(0.0);           // 0 => gunakan riskPercent
//    SetMomentumMinBodyMultiplier(1.15); // body pullback harus 15% lebih besar dr body prev
//    SetMomentumUseEngulfing(true);
//    SetMomentumUsePinbar(false);
// 4) Optimasi: jalankan Strategy Tester (M5) dan variakan parameter:
//    - minConsecutive (3..6)
//    - minBodyMultiplier (1.05..1.5)
//    - slPipsDefault, tpPipsDefault
//    - confirmationCandles (0 atau 1)
// 5) Tips optimasi untuk scalping M5:
//    - fokus pada pasangan berlikuid tinggi (EURUSD, GBPUSD, USDJPY)
//    - gunakan spread kecil, dan cek slippage broker
//    - aktifkan hanya engulfing filter bila ingin akurasi lebih tinggi (mengurangi frekuensi)
// 6) Manajemen posisi:
//    - library akan menutup posisi yang sedang profit saat pullback baru terdeteksi
//      dan kemudian mencoba entry baru berdasarkan sinyal.
//    - lot dihitung berdasarkan riskPercent dan SL. Anda dapat mengunci fixed lot.
// 7) Batasan & catatan:
//    - Ini adalah strategi mekanis; selalu backtest pada data historis dan forward-test pada demo.
//    - Perhitungan pip-value adalah perkiraan; hasil terbaik diperoleh jika Anda verifikasi
//      pip value dengan aset yang diperdagangkan di broker Anda.
//    - Konfirmasi candle (confirmationCandles) dapat mencegah false-signal namun
//      juga memberikan delay yang mungkin buruk untuk scalping.
// ==============================================================


#ifndef __MOMENTUM_PULLBACK_SIGNALS_MQH__
#define __MOMENTUM_PULLBACK_SIGNALS_MQH__

#include <Trade/Trade.mqh>
CTrade trade;

// ------------------------ struct & enum ------------------------
struct MomentumSignal
{
  bool    found;          // true jika ada sinyal
  datetime time;          // time candle sinyal (close time)
  double  entryPrice;     // harga entry (market entry)
  double  stopLoss;       // SL
  double  takeProfit;     // TP
  double  lot;            // lot yang dihitung
  int     dir;            // +1=buy, -1=sell
  string  reason;         // keterangan (pattern)
};

// ------------------------ konfigurasi default ------------------------
namespace MomentumCfg
{
  // deteksi
  int    minConsecutive = 3;        // minimal candle momentum (3+)
  double minBodyMultiplier = 1.15;  // body pullback harus > multiplier * body previous
  ENUM_TIMEFRAMES defaultTF = PERIOD_M5; // default timeframe (scalping)

  // money management
  double riskPercent = 1.0;     // % balance per trade
  double fixedLot = 0.0;        // jika >0 maka gunakan fixed lot, else kalkulasi dari riskPercent
  double slPipsDefault = 15;    // default SL dalam pips
  double tpPipsDefault = 25;    // default TP dalam pips
  double maxLotPerTrade = 5.0;  // batasi maksimal lot

  // filter tambahan
  int    confirmationCandles = 0; // jika >0, butuh konfirmasi (berisiko delay)
  bool   useEngulfingFilter = true;
  bool   usePinbarFilter = false; // default false — pinbar kurang cocok utk scalping cepat

  // eksekusi
  bool   useMarketEntry = true;   // true = market order, false = limit (tidak diimplementasikan)
  string orderComment = "MomentumPullback";
}

// ------------------------ helper fungsi ------------------------

// Konversi pips: jumlah poin per pip (5-digit broker menggunakan 10 poin per pip)
int PipsFactor()
{
  if(_Digits==3 || _Digits==5) return 10;
  return 1;
}

double PipsToPrice(double pips)
{
  return pips * _Point * PipsFactor();
}

// Body size: absolute difference antara Open dan Close
double CandleBody(int shift, ENUM_TIMEFRAMES tf)
{
  double o = iOpen(_Symbol, tf, shift);
  double c = iClose(_Symbol, tf, shift);
  return MathAbs(c - o);
}

// Candle direction: +1 bullish (close>open), -1 bearish (close<open), 0 doji
int CandleDir(int shift, ENUM_TIMEFRAMES tf)
{
  double o = iOpen(_Symbol, tf, shift);
  double c = iClose(_Symbol, tf, shift);
  if(c > o) return 1;
  if(c < o) return -1;
  return 0;
}

// Engulfing check: apakah candle 'shift' engulf candle 'shift+1'
bool IsEngulfing(int shift, ENUM_TIMEFRAMES tf)
{
  double o1 = iOpen(_Symbol, tf, shift);
  double c1 = iClose(_Symbol, tf, shift);
  double o2 = iOpen(_Symbol, tf, shift+1);
  double c2 = iClose(_Symbol, tf, shift+1);

  // bullish engulfing: current bullish and body engulfs previous bearish body
  if(c1 > o1 && c2 < o2)
  {
    if(c1 >= o2 && o1 <= c2) return true;
  }
  // bearish engulfing
  if(c1 < o1 && c2 > o2)
  {
    if(o1 >= c2 && c1 <= o2) return true;
  }
  return false;
}

// Pinbar check (sederhana): badan kecil, salah satu shadow jauh lebih panjang
bool IsPinbar(int shift, ENUM_TIMEFRAMES tf)
{
  double o = iOpen(_Symbol, tf, shift);
  double c = iClose(_Symbol, tf, shift);
  double h = iHigh(_Symbol, tf, shift);
  double l = iLow(_Symbol, tf, shift);

  double body = MathAbs(c-o);
  double upShadow = h - MathMax(o,c);
  double downShadow = MathMin(o,c) - l;

  double biggestShadow = MathMax(upShadow, downShadow);
  if(body==0) body = _Point; // avoid div0
  // aturan: shadow >= 2.5 * body dan lebih besar dari shadow lainnya
  if(biggestShadow >= 2.5*body && biggestShadow >= 2.0 * MathMin(upShadow, downShadow))
    return true;
  return false;
}

// Hitung nilai per-pip per-lot (perkiraan) menggunakan SYMBOL_TRADE_TICK_VALUE/ SIZE
// Jika tidak ada, fallback ke metode konservatif
double PipValuePerLot()
{
  double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
  double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
  if(tickValue<=0 || tickSize<=0)
  {
    // fallback: anggap pip value ~ $10 untuk major (per lot)
    return 10.0;
  }
  double valuePerPoint = tickValue / tickSize; // nilai per 1 point
  // pipsize dalam price = _Point * PipsFactor()
  double pipPrice = _Point * PipsFactor();
  return valuePerPoint * pipPrice;
}

// ------------------------ deteksi pola ------------------------
// Implementasi fokus: momentum di bars 2..L+1 (closed), pullback adalah bar 1 (last closed)
// alasan: deteksi sinyal pada candle terakhir (index 1) setelah momentum yang lebih tua
bool DetectMomentumPullback(ENUM_TIMEFRAMES tf, MomentumSignal &outSignal, int lookbackBars=50)
{
  outSignal.found = false;
  // Pastikan ada minimal bars
  if(lookbackBars < MomentumCfg::minConsecutive + 1) lookbackBars = MomentumCfg::minConsecutive + 1;

  // Ambil bar 1 sebagai pullback candidate (paling recent closed candle)
  int pullShift = 1;
  int dirPull = CandleDir(pullShift, tf);
  if(dirPull==0) return false; // doji, skip

  // Cek berbagai panjang momentum L >= minConsecutive
  int maxPossibleL = MathMin(lookbackBars-1, 20); // batasi 20 untuk efisiensi
  for(int L = maxPossibleL; L>=MomentumCfg::minConsecutive; L--)
  {
    // momentum bars adalah indices 2..(L+1)
    int start = 2; int end = L+1;
    int firstDir = CandleDir(start, tf);
    if(firstDir==0) continue;
    bool okSeq = true;
    for(int s = start+1; s<=end; s++)
    {
      if(CandleDir(s, tf) != firstDir) { okSeq = false; break; }
    }
    if(!okSeq) continue;

    // momentum direction is firstDir; pullback must be opposite
    if(dirPull == firstDir) continue; // not a pullback

    // body condition: body(pull) > multiplier * body(previous)
    double bodyPull = CandleBody(pullShift, tf);
    double bodyPrev = CandleBody(2, tf); // previous candle (first of momentum)
    if(bodyPrev<=0) bodyPrev = _Point;
    if(bodyPull < MomentumCfg::minBodyMultiplier * bodyPrev) continue;

    // Optional filters
    if(MomentumCfg::useEngulfingFilter)
    {
      if(!IsEngulfing(pullShift, tf)) continue;
    }
    if(MomentumCfg::usePinbarFilter)
    {
      if(!IsPinbar(pullShift, tf)) continue;
    }

    // Confirmation: (optional) cek candle 0 (current) telah menunjang arah pullback
    if(MomentumCfg::confirmationCandles>0)
    {
      int confNeeded = MomentumCfg::confirmationCandles;
      bool confOk = true;
      for(int c=0;c<confNeeded;c++)
      {
        int idx = 0 + c; // termasuk bar 0 (belum closed mungkin)
        if(CandleDir(idx, tf) != dirPull) { confOk = false; break; }
      }
      if(!confOk) continue;
    }

    // Siapkan sinyal
    outSignal.found = true;
    outSignal.time = iTime(_Symbol, tf, pullShift);
    outSignal.dir = dirPull; // +1 buy, -1 sell
    // entryPrice: gunakan Ask/Bid market
    if(dirPull==1) outSignal.entryPrice = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    else outSignal.entryPrice = SymbolInfoDouble(_Symbol,SYMBOL_BID);

    double slP = MomentumCfg::slPipsDefault;
    double tpP = MomentumCfg::tpPipsDefault;
    outSignal.stopLoss = outSignal.entryPrice - dirPull * PipsToPrice(slP);
    outSignal.takeProfit = outSignal.entryPrice + dirPull * PipsToPrice(tpP);

    // lot calculation
    outSignal.lot = CalculateLotFromRisk(outSignal.stopLoss, outSignal.entryPrice);
    outSignal.lot = MathMin(outSignal.lot, MomentumCfg::maxLotPerTrade);

    outSignal.reason = StringFormat("Momentum L=%d + pullback idx=%d", L, pullShift);

    return true; // return first (most-recent) valid L
  }

  return false;
}

// ------------------------ money management ------------------------
// Hitung lot dari risk percent dan SL
// - stopLossPrice: level SL
// - entryPrice: harga entry
// Return: lot size
double CalculateLotFromRisk(double stopLossPrice, double entryPrice)
{
  if(MomentumCfg::fixedLot > 0.0) return NormalizeLot(MomentumCfg::fixedLot);

  double accBal = AccountInfoDouble(ACCOUNT_BALANCE);
  if(accBal<=0) accBal = AccountInfoDouble(ACCOUNT_EQUITY);
  double riskAmount = accBal * (MomentumCfg::riskPercent/100.0);

  double slPriceDistance = MathAbs(entryPrice - stopLossPrice);
  if(slPriceDistance <= 0) slPriceDistance = PipsToPrice(1);

  double pipValue = PipValuePerLot(); // value per pip per 1 lot
  if(pipValue<=0) pipValue = 10.0;

  // lot = riskAmount / (sl (in pips) * pipValue)
  double slPips = slPriceDistance / ( _Point * PipsFactor() );
  double lot = riskAmount / (slPips * pipValue);

  // normalize lot to allowed step
  double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if(minLot<=0) minLot = 0.01;
  if(lotStep<=0) lotStep = 0.01;

  double normalized = MathMax(minLot, MathFloor(lot/lotStep)*lotStep);
  // Ensure at least minLot
  if(normalized < minLot) normalized = minLot;

  // Safety cap
  double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  if(maxLot>0) normalized = MathMin(normalized, maxLot);

  return NormalizeLot(normalized);
}

// helper: normalize lot to step precision
double NormalizeLot(double lot)
{
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if(step<=0) step = 0.01;
  double v = MathFloor(lot/step+0.0000001)*step;
  return MathMax(v, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
}

// ------------------------ manajemen posisi ------------------------
// Jika muncul pullback baru dan posisi dalam profit, close posisi dan re-enter sesuai sinyal
void ManagePositionsOnNewPullback(MomentumSignal &s)
{
  // Periksa posisi terbuka untuk simbol
  for(int i=PositionsTotal()-1; i>=0; i--)
  {
    if(!PositionSelectByIndex(i)) continue;
    string sym = PositionGetString(POSITION_SYMBOL);
    if(sym != _Symbol) continue;
    ulong ticket = PositionGetInteger(POSITION_TICKET);
    double volume = PositionGetDouble(POSITION_VOLUME);
    int posDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentProfit = PositionGetDouble(POSITION_PROFIT);

    // jika posisi profit >0 dan arah berlawanan dengan pullback direction? spec: close on profit when pullback baru muncul
    if(currentProfit > 0)
    {
      // Close position
      bool closed = trade.PositionClose(sym);
      if(closed)
      {
        // optional: log
      }
    }
  }
}

// ------------------------ eksekusi sinyal & API publik ------------------------

// Panggil ini tiap OnTick atau OnTimer. Jika sinyal ditemukan, buka posisi.
bool CallSignalsAndTrade(ENUM_TIMEFRAMES tf=MomentumCfg::defaultTF)
{
  MomentumSignal s;
  if(DetectMomentumPullback(tf, s, 50))
  {
    // tutup posisi profit jika perlu
    ManagePositionsOnNewPullback(s);

    // open position
    double lot = s.lot;
    double price = s.entryPrice;
    double sl = s.stopLoss;
    double tp = s.takeProfit;

    bool ok = false;
    trade.SetExpertMagicNumber(123456);
    trade.SetComment(MomentumCfg::orderComment);

    if(s.dir==1)
    {
      if(MomentumCfg::useMarketEntry)
        ok = trade.Buy(lot, NULL, price, sl, tp);
    }
    else
    {
      if(MomentumCfg::useMarketEntry)
        ok = trade.Sell(lot, NULL, price, sl, tp);
    }

    if(ok)
    {
      // success
      return true;
    }
    else
    {
      // gagal eksekusi — coba rekam error
      int err = GetLastError();
      ResetLastError();
      return false;
    }
  }
  return false;
}

void InitMomentumSignals()
{
  // kosong untuk sekarang, tapi dapat dipakai untuk inisialisasi variabel / register timer
}

void SetMomentumRiskPercent(double pct)
{
  MomentumCfg::riskPercent = pct;
}

void SetMomentumSLTP(double slPips, double tpPips)
{
  MomentumCfg::slPipsDefault = slPips;
  MomentumCfg::tpPipsDefault = tpPips;
}

void SetMomentumFixedLot(double lot)
{
  MomentumCfg::fixedLot = lot;
}

void SetMomentumMinBodyMultiplier(double m)
{
  MomentumCfg::minBodyMultiplier = m;
}

void SetMomentumUseEngulfing(bool onoff)
{
  MomentumCfg::useEngulfingFilter = onoff;
}

void SetMomentumUsePinbar(bool onoff)
{
  MomentumCfg::usePinbarFilter = onoff;
}

#endif // __MOMENTUM_PULLBACK_SIGNALS_MQH__

