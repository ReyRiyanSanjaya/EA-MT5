//==================================================================
// MomentumDetectorTFUltimate.mqh
// Versi: 1.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library Ultimate untuk mendeteksi momentum price action
//   berbasis candle di MQL5.
//
// Cara kerja:
//   1. Mengambil data candle (open, close, high, low) untuk timeframe tertentu.
//   2. Menghitung body candle vs range total (wick + body).
//   3. Menilai strength signal (strong signal jika body besar dan tren jelas).
//   4. Menghitung level stop loss, take profit, dan risk/reward ratio.
//
// Cara pakai di EA:
//   #include "MomentumDetectorTFUltimate.mqh"
//   RiskRewardInfo rr;
//   bool strongSignal;
//   Dir momentum = DetectMomentumTF(PERIOD_M5, 0, strongSignal, rr);
//   if(momentum == DIR_BUY) { /* entry buy */ }
//   if(momentum == DIR_SELL) { /* entry sell */ }
//==================================================================

#pragma once

enum Dir
{
   DIR_NONE,
   DIR_BUY,
   DIR_SELL
};

//--- Struct untuk menyimpan info risiko & reward
struct RiskRewardInfo
{
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double riskRewardRatio;
};

//--- Default settings
input int MinBodyPoints        = 20;   // minimal body candle untuk valid signal
input double MaxWickPercent    = 0.3;  // wick maksimal dibanding range
input double AggressiveMultiplier = 1.5; // multiplier untuk take profit
input int StrongSignalMinBody  = 40;   // body minimum untuk strong signal

//==================================================================
// Fungsi: DetectMomentumTF
// Parameters:
//   tf           : timeframe (ENUM_TIMEFRAMES)
//   idx          : bar index (0 = bar terakhir)
//   isStrongSignal : reference boolean untuk menandai momentum kuat
//   rrInfo       : reference struct untuk level entry/SL/TP & RR
// Return: Dir (DIR_BUY / DIR_SELL / DIR_NONE)
//==================================================================
Dir DetectMomentumTF(ENUM_TIMEFRAMES tf, int idx, bool &isStrongSignal, RiskRewardInfo &rrInfo)
{
   double op = iOpen(_Symbol, tf, idx);
   double cl = iClose(_Symbol, tf, idx);
   double hi = iHigh(_Symbol, tf, idx);
   double lo = iLow(_Symbol, tf, idx);

   if(op == 0 || cl == 0 || hi == 0 || lo == 0) return DIR_NONE;

   double bodyPts  = MathAbs(cl - op)/_Point;
   double rangePts = (hi - lo)/_Point;
   if(rangePts <= 0) return DIR_NONE;

   double wickTop    = hi - MathMax(op, cl);
   double wickBottom = MathMin(op, cl) - lo;
   double maxWick    = MathMax(wickTop, wickBottom)/rangePts;

   // Reset awal
   isStrongSignal = false;
   rrInfo.entryPrice = cl;
   rrInfo.stopLoss   = 0;
   rrInfo.takeProfit = 0;
   rrInfo.riskRewardRatio = 0;

   // Filter minimal body & maksimal wick
   if(bodyPts < MinBodyPoints) return DIR_NONE;
   if(maxWick > MaxWickPercent) return DIR_NONE;

   Dir dir = DIR_NONE;
   if(cl > op) dir = DIR_BUY;
   if(cl < op) dir = DIR_SELL;

   // Tentukan strong signal
   if(bodyPts >= StrongSignalMinBody) isStrongSignal = true;

   // Hitung RR: stop loss di ujung wick berlawanan, TP = stopLoss * multiplier
   if(dir == DIR_BUY)
   {
      rrInfo.stopLoss   = lo;
      rrInfo.takeProfit = cl + (cl - lo) * AggressiveMultiplier;
      rrInfo.riskRewardRatio = (rrInfo.takeProfit - cl)/(cl - rrInfo.stopLoss);
   }
   else if(dir == DIR_SELL)
   {
      rrInfo.stopLoss   = hi;
      rrInfo.takeProfit = cl - (hi - cl) * AggressiveMultiplier;
      rrInfo.riskRewardRatio = (cl - rrInfo.takeProfit)/(rrInfo.stopLoss - cl);
   }

   return dir;
}

//==================================================================
// Fungsi: PrintMomentumSignal
// Deskripsi: Print signal + strong + RR ke Experts tab
//==================================================================
void PrintMomentumSignal(ENUM_TIMEFRAMES tf, int idx)
{
   RiskRewardInfo rr;
   bool strong;
   Dir dir = DetectMomentumTF(tf, idx, strong, rr);

   string sDir = (dir==DIR_BUY?"BUY":(dir==DIR_SELL?"SELL":"NONE"));
   string sStrong = strong ? "STRONG" : "WEAK";

   PrintFormat("Momentum %s | CandleIdx:%d | Signal:%s | Strength:%s | Entry:%.5f SL:%.5f TP:%.5f RR:%.2f",
               _Symbol, idx, sDir, sStrong, rr.entryPrice, rr.stopLoss, rr.takeProfit, rr.riskRewardRatio);
}
