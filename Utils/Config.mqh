//==================================================================
// Config.mqh
// Versi: 1.0
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   File konfigurasi utama untuk EA / Library trading
//   - Semua parameter input disimpan di sini
//   - Mudah diubah tanpa mengedit library lain
//==================================================================

#pragma once

//===================== GENERAL ===========================
input string EA_Name           = "UltimateScalper";
input double AccountRisk       = 1.0;    // Risiko per trade (%)
input double LotMin            = 0.01;   // Lot minimum
input bool   EnableAutoTrading = true;   // Aktifkan eksekusi otomatis

//===================== TRAILING & BREAKEVEN =============
input bool   EnableTrailing    = true;
input double TrailDistance1    = 10;     // Trailing pip 1
input double TrailLevel2       = 30;     // Level profit pip untuk Trail 2
input double TrailDistance2    = 15;     // Trailing pip 2
input double TrailLevel3       = 50;     // Level profit pip untuk Trail 3
input double TrailDistance3    = 25;     // Trailing pip 3
input bool   EnableBreakEven   = true;
input double BreakEvenProfit   = 15;     // Pip profit untuk set BE

//===================== INDICATOR SETTINGS =====================
input int EMA_Fast_Period      = 9;
input int EMA_Slow_Period      = 21;
input int SMA_Period           = 50;
input int RSI_Period           = 14;
input int Stoch_K              = 14;
input int Stoch_D              = 3;
input int Stoch_Slowing        = 3;
input int MACD_FastEMA         = 12;
input int MACD_SlowEMA         = 26;
input int MACD_SignalSMA       = 9;
input int ATR_Period           = 14;
input int CCI_Period           = 20;

//===================== TIMEFRAMES ============================
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M1;  // TF untuk entry
input ENUM_TIMEFRAMES TF_Trend = PERIOD_M5;  // TF untuk trend / filter

//===================== NEWS IMPACT ===========================
input bool  EnableNewsScalp    = true;
input int   NewsDelaySec       = 5;      // Delay setelah news candle selesai
input double NewsCandleMinPct  = 0.5;    // Minimal body candle dibanding rata-rata

//===================== SCALPING / PULLBACK ===================
input bool EnablePullbackScalp = true;
input double PullbackMinPips   = 10;
input double PullbackMaxPips   = 50;

//===================== ORDER BLOCK / SUPPLY-DEMAND ===========
input bool EnableOrderBlock    = true;
input int  OBLookbackBars      = 50;     // Jarak candle untuk deteksi OB

//===================== HARMONIC PATTERN =====================
input bool EnableHarmonic      = true;
input double GartleyRatios[4]  = {0.618, 0.786, 1.27, 1.618}; // contoh rasio
input double BatRatios[4]      = {0.382, 0.5, 0.886, 1.618};
input double ButterflyRatios[4] = {0.786, 0.886, 1.27, 1.618};
input double CrabRatios[4]     = {0.618, 0.786, 1.618, 2.618};

//===================== MOMENTUM & CANDLE PATTERN =============
input bool EnableCandlePattern3Plus1 = true;
input int  CandlePatternMinBars       = 3;
input double CandlePatternWickFactor  = 0.5;

//===================== SMC / SCM ===============================
input bool EnableSMCFilter       = true;
input int  SMCLookbackBars       = 50;

//===================== DEBUG / LOG =============================
input bool EnableDebug           = true;
input int  PrintIntervalSec      = 5;     // interval print log

namespace AppConfig
{
   double riskPercent   = 1.0;   // risiko per trade (% balance)
   double slPips        = 30;    // default Stop Loss (dalam pips)
   double tpPips        = 60;    // default Take Profit (dalam pips)
   bool   useFilters    = true;  // apakah aktifkan filter
}

/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA atau modul:
      #include "Config.mqh"

2. Semua library lain (TradeExecutor, RiskManager, IndicatorLoader, dll)
   dapat membaca parameter dari Config.mqh.

3. Contoh penggunaan:
      if(EnableTrailing)
          StartTrailing(TrailDistance1, TrailDistance2, TrailDistance3);

      MultiTFIndicators ind = LoadMultiTFIndicators(TF_Entry, TF_Trend);

      if(EnableNewsScalp)
          NISignal sig = DetectNewsImpactSignal(LotMin, NewsCandleMinPct, NewsDelaySec);

4. Untuk tuning strategi, cukup ubah nilai di Config.mqh tanpa mengubah library lain.

==================================================================
*/
