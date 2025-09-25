//+------------------------------------------------------------------+
//| Pola-N.mqh                                                      |
//| Library Deteksi Pola Candlestick Populer                        |
//+------------------------------------------------------------------
#pragma once
#include "..\Interfaces\Types.mqh"
#include "..\Utils\MathUtils.mqh"

//==================================================================
// Cara Pakai :
//   RiskRewardInfo rr;
//   Dir signal = DetectPatternN(_Symbol, PERIOD_M15, 1, rr);
//
// Parameter :
//   - symbol : simbol yang dianalisis
//   - tf     : timeframe (contoh PERIOD_M15)
//   - shift  : index bar (0 = current, 1 = candle closed terakhir)
//   - rrInfo : struct RiskRewardInfo, akan diisi entry/SL/TP
//
// Return :
//   DIR_BUY, DIR_SELL, atau DIR_NONE
//==================================================================

//----------------------------------------
// Helper ambil candle
//----------------------------------------
struct Candle {
   double open;
   double close;
   double high;
   double low;
};

Candle GetCandle(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   Candle c;
   c.open  = iOpen(symbol, tf, shift);
   c.close = iClose(symbol, tf, shift);
   c.high  = iHigh(symbol, tf, shift);
   c.low   = iLow(symbol, tf, shift);
   return c;
}

//----------------------------------------
// Engulfing
//----------------------------------------
Dir DetectEngulfing(Candle prev, Candle cur, RiskRewardInfo &rr)
{
   if(prev.close < prev.open && cur.close > cur.open && cur.close > prev.open && cur.open < prev.close)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = prev.low;
      rr.takeProfit = rr.entryPrice + (cur.close - prev.low) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_BUY;
     }

   if(prev.close > prev.open && cur.close < cur.open && cur.close < prev.open && cur.open > prev.close)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = prev.high;
      rr.takeProfit = rr.entryPrice - (prev.high - cur.close) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_SELL;
     }

   return DIR_NONE;
}

//----------------------------------------
// Doji
//----------------------------------------
Dir DetectDoji(Candle cur, RiskRewardInfo &rr)
{
   double body = MathAbs(cur.close - cur.open);
   double range = cur.high - cur.low;

   if(range == 0) return DIR_NONE;

   if(body <= 0.1 * range)  // body < 10% dari range
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = (cur.close > cur.open ? cur.low : cur.high);
      rr.takeProfit = rr.entryPrice + (rr.entryPrice - rr.stopLoss) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_NONE; // Doji netral, butuh konfirmasi
     }

   return DIR_NONE;
}

//----------------------------------------
// Pin Bar
//----------------------------------------
Dir DetectPinBar(Candle cur, RiskRewardInfo &rr)
{
   double body = MathAbs(cur.close - cur.open);
   double upperWick = cur.high - MathMax(cur.close, cur.open);
   double lowerWick = MathMin(cur.close, cur.open) - cur.low;

   if(upperWick >= 2 * body && upperWick >= 0.6 * (cur.high - cur.low))
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = cur.high;
      rr.takeProfit = rr.entryPrice - (rr.stopLoss - rr.entryPrice) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_SELL;
     }

   if(lowerWick >= 2 * body && lowerWick >= 0.6 * (cur.high - cur.low))
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = cur.low;
      rr.takeProfit = rr.entryPrice + (rr.entryPrice - rr.stopLoss) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_BUY;
     }

   return DIR_NONE;
}

//----------------------------------------
// Morning Star / Evening Star
//----------------------------------------
Dir DetectStar(Candle c1, Candle c2, Candle c3, RiskRewardInfo &rr)
{
   if(c1.close < c1.open && MathAbs(c2.close - c2.open) < (c1.open - c1.close)*0.5 && c3.close > c3.open && c3.close > (c1.open + c1.close)/2)
     {
      rr.entryPrice = c3.close;
      rr.stopLoss   = MathMin(c1.low, c2.low);
      rr.takeProfit = rr.entryPrice + (rr.entryPrice - rr.stopLoss) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_BUY;
     }

   if(c1.close > c1.open && MathAbs(c2.close - c2.open) < (c1.close - c1.open)*0.5 && c3.close < c3.open && c3.close < (c1.open + c1.close)/2)
     {
      rr.entryPrice = c3.close;
      rr.stopLoss   = MathMax(c1.high, c2.high);
      rr.takeProfit = rr.entryPrice - (rr.stopLoss - rr.entryPrice) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_SELL;
     }

   return DIR_NONE;
}

//----------------------------------------
// Harami (Bullish & Bearish)
//----------------------------------------
Dir DetectHarami(Candle prev, Candle cur, RiskRewardInfo &rr)
{
   if(prev.close < prev.open && cur.close > cur.open && cur.open > prev.close && cur.close < prev.open)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = prev.low;
      rr.takeProfit = rr.entryPrice + (rr.entryPrice - rr.stopLoss) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_BUY;
     }

   if(prev.close > prev.open && cur.close < cur.open && cur.open < prev.close && cur.close > prev.open)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = prev.high;
      rr.takeProfit = rr.entryPrice - (rr.stopLoss - rr.entryPrice) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_SELL;
     }

   return DIR_NONE;
}

//----------------------------------------
// Hammer / Inverted Hammer
//----------------------------------------
Dir DetectHammer(Candle cur, RiskRewardInfo &rr)
{
   double body = MathAbs(cur.close - cur.open);
   double upperWick = cur.high - MathMax(cur.close, cur.open);
   double lowerWick = MathMin(cur.close, cur.open) - cur.low;
   double range = cur.high - cur.low;

   // Hammer (bullish reversal)
   if(lowerWick >= 2 * body && body <= 0.3 * range)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = cur.low;
      rr.takeProfit = rr.entryPrice + (rr.entryPrice - rr.stopLoss) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_BUY;
     }

   // Inverted Hammer (bearish reversal)
   if(upperWick >= 2 * body && body <= 0.3 * range)
     {
      rr.entryPrice = cur.close;
      rr.stopLoss   = cur.high;
      rr.takeProfit = rr.entryPrice - (rr.stopLoss - rr.entryPrice) * 2;
      rr.riskRewardRatio = 2.0;
      return DIR_SELL;
     }

   return DIR_NONE;
}

//==================================================================
// Fungsi utama: cek semua pola
//==================================================================
Dir DetectPatternN(string symbol, ENUM_TIMEFRAMES tf, int shift, RiskRewardInfo &rr)
{
   Candle c1 = GetCandle(symbol, tf, shift+2);
   Candle c2 = GetCandle(symbol, tf, shift+1);
   Candle c3 = GetCandle(symbol, tf, shift);

   Dir signal;

   signal = DetectEngulfing(c2, c3, rr);
   if(signal != DIR_NONE) return signal;

   signal = DetectDoji(c3, rr);
   if(signal != DIR_NONE) return signal;

   signal = DetectPinBar(c3, rr);
   if(signal != DIR_NONE) return signal;

   signal = DetectStar(c1, c2, c3, rr);
   if(signal != DIR_NONE) return signal;

   signal = DetectHarami(c2, c3, rr);
   if(signal != DIR_NONE) return signal;

   signal = DetectHammer(c3, rr);
   if(signal != DIR_NONE) return signal;

   return DIR_NONE;
}
