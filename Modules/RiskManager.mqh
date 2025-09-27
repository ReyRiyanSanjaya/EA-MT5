//==================================================================
// RiskManager.mqh
//
// 📌 TUJUAN:
// - Mengatur manajemen risiko agar tidak MC.
// - Hitung lot dinamis berdasarkan confidence, balance, dan free margin.
// - Cek margin call level broker sebelum entry.
// - Tambah proteksi drawdown, spread, dan slippage.
//
//==================================================================
#pragma once

namespace RiskManager
{
   // --- Konfigurasi dasar ---
   double baseLot    = 0.1;    // minimal lot
   double maxLot     = 1.0;    // maksimal lot
   double riskPercent= 1.0;    // risiko per trade (% balance)
   double maxDDaily  = 10.0;   // max loss harian (% equity)
   double maxSpread  = 30;     // max spread (point)
   double slippage   = 3;      // max slippage (point)
   double minMarginLevel = 200; // minimal margin level (%) aman untuk entry

   // --- Hitung balance, equity, margin ---
   double GetBalance() { return AccountInfoDouble(ACCOUNT_BALANCE); }
   double GetEquity()  { return AccountInfoDouble(ACCOUNT_EQUITY); }
   double GetFreeMargin() { return AccountInfoDouble(ACCOUNT_FREEMARGIN); }
   double GetMarginLevel() { return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); }

   // --- Hitung nilai 1 pip ---
   double GetPipValue(string symbol=NULL)
   {
      if(symbol==NULL) symbol = _Symbol;
      return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   }

   // --- Hitung lot berdasarkan risk% dan SL (dalam pips) ---
   double CalculateLotByRisk(double stopLossPips, string symbol=NULL)
   {
      if(symbol==NULL) symbol = _Symbol;
      double balance   = GetBalance();
      double riskMoney = balance * (riskPercent/100.0);
      double pipValue  = GetPipValue(symbol);
      if(pipValue<=0) pipValue=0.0001;

      double lot = riskMoney / (stopLossPips * pipValue);
      return lot;
   }

   // --- Hitung lot dinamis dari confidence + risk ---
   double GetDynamicLot(double confidence, double stopLossPips=30, string symbol=NULL)
   {
      if(symbol==NULL) symbol = _Symbol;

      // Hitung lot dari confidence
      double lotFromConfidence = baseLot + (maxLot - baseLot) * confidence;

      // Hitung lot dari risk %
      double lotByRisk = CalculateLotByRisk(stopLossPips, symbol);

      // Ambil lot terkecil (biar aman)
      double lot = MathMin(lotFromConfidence, lotByRisk);

      // --- Validasi margin ---
      double freeMargin = GetFreeMargin();
      double marginReq  = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lot, SymbolInfoDouble(symbol, SYMBOL_ASK), marginReq))
         marginReq = 0;

      if(marginReq > freeMargin)
      {
         // Turunkan lot biar cukup margin
         lot = (freeMargin / marginReq) * lot;
      }

      // --- Batasi maxLot ---
      lot = MathMin(lot, maxLot);

      return NormalizeDouble(lot, 2);
   }

   // --- Cek apakah boleh entry ---
   bool CanOpenTrade()
   {
      // Cek margin level
      if(GetMarginLevel() < minMarginLevel) return false;

      // Cek spread
      double spread = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      if(spread > maxSpread) return false;

      // Cek max drawdown harian
      static double equityStart = GetEquity();
      double ddPercent = ((equityStart - GetEquity()) / equityStart) * 100.0;
      if(ddPercent > maxDDaily) return false;

      return true;
   }
}
