//==================================================================
// TradeExecutor.mqh
// Eksekusi order berdasarkan sinyal + risk manager
//==================================================================
#pragma once

#include "Modules/SignalEngine.mqh"
#include "RiskManager.mqh"
#include "App.mqh"   // untuk AppConfig (SL/TP, risk%)

//==================================================================
// TradeExecutor.mqh
//
// 📌 TUJUAN:
// - Mengeksekusi order berdasarkan sinyal konsensus.
// - Menghubungkan SignalEngine + RiskManager + fungsi entry (buy/sell).
//
// 📌 FUNGSI UTAMA:
// - ExecuteTradeFromSignals()
//     -> Ambil sinyal konsensus dari SignalEngine.
//     -> Hitung lot via RiskManager.
//     -> Jalankan Buy/Sell order dengan SL & TP default dari AppConfig.
//
// 📌 CARA PAKAI:
// - Di App.mqh → panggil fungsi ini di dalam OnTick():
//       void OnTick() { ExecuteTradeFromSignals(); }
//
// 📌 CATATAN:
// - Semua keputusan entry hanya berdasarkan mayoritas sinyal.
// - Lot otomatis disesuaikan berdasarkan confidence.
// - SL & TP default diatur di AppConfig.
//==================================================================


// penggunaan di ontick()
// #include "TradeExecutor.mqh"

// void OnTick()
// {
//    ExecuteTradeFromSignals();
// }


void ExecuteBuy(double lot)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = ask - AppConfig::slPips * _Point;
   double tp  = ask + AppConfig::tpPips * _Point;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = ORDER_TYPE_BUY;
   request.volume   = lot;
   request.price    = ask;
   request.sl       = sl;
   request.tp       = tp;
   request.deviation= 10;
   request.magic    = 12345;
   request.comment  = "AutoTrade Buy";

   if(!OrderSend(request,result))
      Print("❌ Buy failed: ", result.retcode);
   else
      Print("✅ Buy executed @", ask, " lot=", lot);
}

void ExecuteSell(double lot)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = bid + AppConfig::slPips * _Point;
   double tp  = bid - AppConfig::tpPips * _Point;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = ORDER_TYPE_SELL;
   request.volume   = lot;
   request.price    = bid;
   request.sl       = sl;
   request.tp       = tp;
   request.deviation= 10;
   request.magic    = 12345;
   request.comment  = "AutoTrade Sell";

   if(!OrderSend(request,result))
      Print("❌ Sell failed: ", result.retcode);
   else
      Print("✅ Sell executed @", bid, " lot=", lot);
}

// ---------------------------------------------------------
// Fungsi utama: eksekusi trade dari konsensus sinyal
// --- Fungsi eksekusi utama ---
void ExecuteTradeFromSignals()
{
   Dir    direction;
   double confidence;

   // Ambil sinyal konsensus dari SignalEngine
   if(!SignalEngine::GetConsensusSignal(direction, confidence))
      return; // tidak ada sinyal

   // ✅ Cek proteksi RiskManager sebelum entry
   if(!RiskManager::CanOpenTrade())
   {
      Print("⚠️ Kondisi tidak aman, tidak entry (margin/spread/DD limit).");
      return;
   }

   // Hitung lot dinamis dengan proteksi margin
   double lotSize = RiskManager::GetDynamicLot(confidence, AppConfig::slPips);

   // Entry BUY / SELL sesuai sinyal
   if(direction == DIR_BUY)
   {
      ExecuteBuy(lotSize, AppConfig::slPips, AppConfig::tpPips);
   }
   else if(direction == DIR_SELL)
   {
      ExecuteSell(lotSize, AppConfig::slPips, AppConfig::tpPips);
   }
}