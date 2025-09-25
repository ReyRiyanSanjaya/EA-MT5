//==================================================================
// MacroSignalsUltimate.mqh
// Versi: 1.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library Ultimate untuk EA MQ5 untuk mendapatkan sinyal trading
//   dari indikator makro: DXY, Gold, Yield.
//   Memiliki weighting, filter tren, dan gabungan sinyal otomatis.
//
// Cara kerja:
//   1. Ambil harga simbol makro.
//   2. Hitung MA dan ATR, evaluasi kekuatan tren.
//   3. Setiap indikator diberi score sesuai arah dan weighting.
//   4. Total score dibandingkan threshold → DIR_BUY / DIR_SELL / DIR_NONE.
//
// Cara pakai di EA:
//   #include "MacroSignalsUltimate.mqh"
//   Dir sig = GetMacroSignalUltimate();
//   if(sig == DIR_BUY) { /* Buy logic */ }
//   if(sig == DIR_SELL) { /* Sell logic */ }
//==================================================================

#pragma once

enum Dir
{
   DIR_NONE,
   DIR_BUY,
   DIR_SELL
};

//--- default MA & ATR
input int MAPeriod = 50;
input ENUM_MA_METHOD MAMethod = MODE_SMA;
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE;
input int ATRPeriod = 14;

//--- Weighting tiap indikator makro (0-1)
input double WeightDXY   = 0.5;
input double WeightGold  = 0.3;
input double WeightYield = 0.2;

//--- Threshold total score untuk entry
input double BuyThreshold  = 0.6;
input double SellThreshold = -0.6;

//==================================================================
// Fungsi: GetMacroScore
// Parameter:
//   symbolName : string
//   timeframe  : ENUM_TIMEFRAMES
// Return: double (-1..1) → -1 strong sell, +1 strong buy
//==================================================================
double GetMacroScore(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   if(!SymbolSelect(symbolName,true)) return 0;

   double closePrice = iClose(symbolName,timeframe,0);
   double prevClose  = iClose(symbolName,timeframe,1);

   double maCurrent  = iMA(symbolName,timeframe,MAPeriod,0,MAMethod,MAPrice,0);
   double maPrev     = iMA(symbolName,timeframe,MAPeriod,0,MAMethod,MAPrice,1);

   double maSlope = maCurrent - maPrev;
   double atr      = iATR(symbolName,timeframe,ATRPeriod,0);

   // jika volatilitas terlalu rendah dibanding slope → sinyal netral
   if(atr < 0.1 * MathAbs(maSlope)) return 0;

   // cross MA
   if(prevClose < maPrev && closePrice > maCurrent && maSlope > 0)
      return 1.0;   // buy
   if(prevClose > maPrev && closePrice < maCurrent && maSlope < 0)
      return -1.0;  // sell

   return 0;        // netral
}

//==================================================================
// Fungsi: GetMacroSignalUltimate
// Return: Dir
// Deskripsi:
//   Menggabungkan semua indikator makro menggunakan weighting dan threshold
//==================================================================
Dir GetMacroSignalUltimate()
{
   double score = 0;
   score += GetMacroScore("DXY",PERIOD_H1) * WeightDXY;
   score += GetMacroScore("XAUUSD",PERIOD_H1) * WeightGold;
   score += GetMacroScore("US10Y",PERIOD_H1) * WeightYield;

   if(score >= BuyThreshold) return DIR_BUY;
   if(score <= SellThreshold) return DIR_SELL;

   return DIR_NONE;
}

//==================================================================
// Fungsi: PrintMacroUltimate
// Deskripsi:
//   Print semua sinyal makro + skor total + sinyal gabungan
//==================================================================
void PrintMacroUltimate()
{
   double sDXY   = GetMacroScore("DXY",PERIOD_H1);
   double sGold  = GetMacroScore("XAUUSD",PERIOD_H1);
   double sYield = GetMacroScore("US10Y",PERIOD_H1);
   double total  = sDXY*WeightDXY + sGold*WeightGold + sYield*WeightYield;
   Dir combined  = GetMacroSignalUltimate();

   string SigStr = (combined==DIR_BUY?"BUY":(combined==DIR_SELL?"SELL":"NONE"));

   PrintFormat("Macro Ultimate Scores | DXY:%.2f Gold:%.2f Yield:%.2f | Total:%.2f | COMBINED:%s",
               sDXY,sGold,sYield,total,SigStr);
}
