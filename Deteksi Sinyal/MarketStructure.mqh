//+------------------------------------------------------------------+
//| MarketStructure.mqh                                             |
//| Library: Analisis Struktur Pasar (Basic + Advanced)             |
//+------------------------------------------------------------------+
//
// 📌 Dokumentasi:
// Library ini menyediakan 2 level analisis struktur pasar:
// 1. AnalyzeMarketStructure() → metode dasar (3 candle terakhir).
// 2. AnalyzeMarketStructureAdvanced() → metode advanced menggunakan fractal.
//
// Cara Pakai:
//   #include "Strategies/MarketStructure.mqh"
//
//   void OnTick()
//   {
//       Dir msBasic = AnalyzeMarketStructure(PERIOD_H1, 0);
//       Dir msAdv   = AnalyzeMarketStructureAdvanced(PERIOD_H1, 20);
//
//       if(msAdv == DIR_BUY)  Print("📈 Struktur bullish di H1 (fractal)");
//       if(msAdv == DIR_SELL) Print("📉 Struktur bearish di H1 (fractal)");
//   }
//
// Parameter:
//   - tf       : ENUM_TIMEFRAMES → timeframe yang dianalisis (contoh PERIOD_H1)
//   - shift    : index bar (0 = candle saat ini, 1 = candle sebelumnya) [untuk basic]
//   - lookback : jumlah bar untuk scanning fractal swing [untuk advanced]
//
// Return:
//   - DIR_BUY  → struktur pasar bullish (HH/HL dominan)
//   - DIR_SELL → struktur pasar bearish (LH/LL dominan)
//   - DIR_NONE → tidak ada sinyal jelas
//
// Cara Kerja Advanced:
//   1. Scan "lookback" bar untuk mencari fractal high & fractal low.
//   2. Bandingkan urutan fractal terakhir:
//      - Jika fractal high makin tinggi (HH) dan fractal low makin tinggi (HL) → bullish.
//      - Jika fractal high makin rendah (LH) dan fractal low makin rendah (LL) → bearish.
//   3. Jika campur (misalnya high naik tapi low turun) → netral.
//
//+------------------------------------------------------------------
#pragma once
#include "..\Interfaces\Types.mqh"

//----------------------------------------
// Basic Market Structure (3 candle saja)
//----------------------------------------
Dir AnalyzeMarketStructure(ENUM_TIMEFRAMES tf, int shift)
{
   if(Bars(_Symbol, tf) < shift+3)
      return DIR_NONE;

   double high1 = iHigh(_Symbol, tf, shift+2);
   double low1  = iLow(_Symbol, tf, shift+2);

   double high2 = iHigh(_Symbol, tf, shift+1);
   double low2  = iLow(_Symbol, tf, shift+1);

   double high3 = iHigh(_Symbol, tf, shift);
   double low3  = iLow(_Symbol, tf, shift);

   if(high3 > high2 && low3 > low2 && high2 > high1 && low2 > low1)
      return DIR_BUY;

   if(high3 < high2 && low3 < low2 && high2 < high1 && low2 < low1)
      return DIR_SELL;

   return DIR_NONE;
}

//----------------------------------------
// Advanced Market Structure (Fractal-based)
//----------------------------------------
Dir AnalyzeMarketStructureAdvanced(ENUM_TIMEFRAMES tf, int lookback)
{
   if(Bars(_Symbol, tf) < lookback+5)
      return DIR_NONE;

   int lastFractalHigh = -1;
   int lastFractalLow  = -1;

   // Cari fractal terakhir
   for(int i=2; i<lookback; i++)
   {
      double h = iHigh(_Symbol, tf, i);
      double l = iLow(_Symbol, tf, i);

      // Fractal High
      if(h > iHigh(_Symbol, tf, i+1) && h > iHigh(_Symbol, tf, i+2) &&
         h > iHigh(_Symbol, tf, i-1) && h > iHigh(_Symbol, tf, i-2))
      {
         lastFractalHigh = i;
         break;
      }
   }

   for(int i=2; i<lookback; i++)
   {
      double l = iLow(_Symbol, tf, i);

      // Fractal Low
      if(l < iLow(_Symbol, tf, i+1) && l < iLow(_Symbol, tf, i+2) &&
         l < iLow(_Symbol, tf, i-1) && l < iLow(_Symbol, tf, i-2))
      {
         lastFractalLow = i;
         break;
      }
   }

   // Kalau tidak ketemu fractal → netral
   if(lastFractalHigh == -1 || lastFractalLow == -1)
      return DIR_NONE;

   // Ambil 2 fractal terakhir untuk analisis arah
   double high1 = iHigh(_Symbol, tf, lastFractalHigh+5);
   double high2 = iHigh(_Symbol, tf, lastFractalHigh);

   double low1  = iLow(_Symbol, tf, lastFractalLow+5);
   double low2  = iLow(_Symbol, tf, lastFractalLow);

   // Bullish → HH & HL
   if(high2 > high1 && low2 > low1)
      return DIR_BUY;

   // Bearish → LH & LL
   if(high2 < high1 && low2 < low1)
      return DIR_SELL;

   return DIR_NONE;
}
