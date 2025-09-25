//+------------------------------------------------------------------+
//| Types.mqh                                                       |
//| Definisi tipe data umum untuk EA                                |
//+------------------------------------------------------------------
#pragma once

//=== Arah trading ===
enum Dir
  {
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
  };

//=== Risk Reward Info ===
struct RiskRewardInfo
  {
   double entryPrice;       // harga entry
   double stopLoss;         // harga SL
   double takeProfit;       // harga TP
   double riskRewardRatio;  // rasio RR
  };
