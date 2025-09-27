//==================================================================
// SignalEngine.mqh
// Integrasi semua modul deteksi sinyal
//==================================================================

//==================================================================
// SignalEngine.mqh
//
// 📌 TUJUAN:
// - Mengumpulkan sinyal dari berbagai modul (MarketStructure, 
//   MacroSignals, ChartPatternUltimate, HarmonicPatterns, IcebergDetector).
// - Menghitung konsensus sinyal (arah mayoritas).
// - Menentukan confidence (seberapa kuat sinyal mayoritas).
//
// 📌 FUNGSI UTAMA:
// - SignalEngine::GetConsensusSignal(Dir &direction, double &confidence)
//     -> Menghasilkan arah trade (BUY / SELL / NONE) berdasarkan mayoritas sinyal.
//     -> Confidence ditentukan dari jumlah sinyal yang searah.
//
// 📌 CARA PAKAI:
// - Dipanggil dari TradeExecutor.mqh untuk menentukan arah trade.
// - Tidak perlu dipanggil langsung dari EA, karena sudah otomatis 
//   dipanggil lewat TradeExecutor.
//
// 📌 CATATAN:
// - Tambahkan modul sinyal baru dengan memasukkannya ke dalam daftar di sini.
// - Confidence digunakan oleh RiskManager untuk mengatur lot.
//==================================================================

#pragma once

#include "MacroSignals.mqh"
#include "MarketStructure.mqh"
#include "ChartPatternUltimate.mqh"
#include "HarmonicPatterns.mqh"
#include "IcebergDetector.mqh"

struct TradeSignal {
   string   source;       // asal sinyal
   string   description;  // deskripsi sinyal
   int      direction;    // 1=Buy, -1=Sell, 0=Netral
   double   confidence;   // 0.0 - 1.0
   datetime timestamp;    // waktu sinyal
};

namespace SignalEngine
{
   // ---------------------------------------------------------
   // Momentum Candle Detector (contoh custom rule)
   bool DetectMomentumCandle(TradeSignal &sig)
   {
      int countUp=0, countDown=0;
      for(int i=1; i<=3; i++)
      {
         if(Close[i] > Open[i]) countUp++;
         else if(Close[i] < Open[i]) countDown++;
      }

      double lastBody = MathAbs(Close[0] - Open[0]);
      double prevBody = MathAbs(Close[1] - Open[1]);

      if(countUp==3 && lastBody > prevBody && Close[0] < Open[0]) {
         sig = {"MomentumCandle","Bullish momentum exhausted → bearish pullback",-1,0.7,TimeCurrent()};
         return true;
      }
      if(countDown==3 && lastBody > prevBody && Close[0] > Open[0]) {
         sig = {"MomentumCandle","Bearish momentum exhausted → bullish pullback",1,0.7,TimeCurrent()};
         return true;
      }
      return false;
   }

   // ---------------------------------------------------------
   // Integrasi modul lain
   bool DetectMacro(TradeSignal &sig)
   {
      if(MacroSignals::CheckDXYBullish()) {
         sig = {"MacroSignals","DXY bullish - USD strength",1,0.6,TimeCurrent()};
         return true;
      }
      return false;
   }

   bool DetectMarketStructure(TradeSignal &sig)
   {
      if(MarketStructure::IsBreakout()) {
         sig = {"MarketStructure","Market breakout detected",1,0.65,TimeCurrent()};
         return true;
      }
      return false;
   }

   bool DetectChartPattern(TradeSignal &sig)
   {
      if(ChartPatternUltimate::DetectTriangle()) {
         sig = {"ChartPattern","Triangle breakout",1,0.7,TimeCurrent()};
         return true;
      }
      return false;
   }

   bool DetectHarmonic(TradeSignal &sig)
   {
      if(HarmonicPatterns::DetectGartley()) {
         sig = {"HarmonicPatterns","Bullish Gartley detected",1,0.75,TimeCurrent()};
         return true;
      }
      return false;
   }

   bool DetectIceberg(TradeSignal &sig)
   {
      if(IcebergDetector::DetectHiddenOrder()) {
         sig = {"IcebergDetector","Hidden order detected",-1,0.8,TimeCurrent()};
         return true;
      }
      return false;
   }

   // ---------------------------------------------------------
   // Ambil semua sinyal
   int GetAllSignals(TradeSignal &sig[])
   {
      ArrayResize(sig,0);
      TradeSignal s;

      if(DetectMomentumCandle(s)) ArrayPush(sig,s);
      if(DetectMacro(s))          ArrayPush(sig,s);
      if(DetectMarketStructure(s))ArrayPush(sig,s);
      if(DetectChartPattern(s))   ArrayPush(sig,s);
      if(DetectHarmonic(s))       ArrayPush(sig,s);
      if(DetectIceberg(s))        ArrayPush(sig,s);

      return ArraySize(sig);
   }

   // ---------------------------------------------------------
   // Konsensus mayoritas
   bool GetConsensusSignal(TradeSignal &finalSig)
   {
      TradeSignal sigs[];
      int count = GetAllSignals(sigs);
      if(count==0) return false;

      int bullish=0, bearish=0;
      double avgConf=0;
      for(int i=0;i<count;i++)
      {
         avgConf += sigs[i].confidence;
         if(sigs[i].direction==1) bullish++;
         if(sigs[i].direction==-1) bearish++;
      }
      avgConf /= count;

      if(bullish > bearish) {
         finalSig = {"Consensus","Majority bullish ("+IntegerToString(bullish)+") signals",1,avgConf*(double)bullish/count,TimeCurrent()};
         return true;
      }
      if(bearish > bullish) {
         finalSig = {"Consensus","Majority bearish ("+IntegerToString(bearish)+") signals",-1,avgConf*(double)bearish/count,TimeCurrent()};
         return true;
      }
      return false; // imbang
   }
}
