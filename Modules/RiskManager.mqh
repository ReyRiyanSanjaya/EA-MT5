//==================================================================
// RiskManager.mqh
// Versi: 1.0
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library manajemen risiko untuk MT5
//   - Menghitung ukuran lot berdasarkan risiko account
//   - Menghitung Stop Loss (SL) dan Take Profit (TP) otomatis
//   - Bisa digunakan untuk scalping, swing, news trading
//==================================================================


/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA:
   #include "RiskManager.mqh"

2. Contoh menghitung lot dengan risiko 1% dan SL 20 pip:
   double lot = CalculateRiskLot(1.0,20);

3. Contoh menghitung SL dan TP dengan RR 2:
   double sl,tp;
   CalculateSLTP(DIR_BUY,Ask,20,2,sl,tp);

4. Contoh menggunakan ApplyRiskManagement untuk integrasi:
   NISignalRisk risk = ApplyRiskManagement(DIR_BUY,Ask,20,2,1.0);
   // hasil: risk.lot, risk.sl, risk.tp

5. Integrasi dengan TradeExecutor.mqh:
   NISignalRisk risk = ApplyRiskManagement(DIR_BUY,Ask,20,2,1.0);
   OpenTrade(DIR_BUY,risk.lot,risk.sl,risk.tp,"Scalping");

==================================================================*/

#pragma once

//==================================================================
// ENUM arah posisi
//==================================================================
enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

//==================================================================
// Fungsi: CalculateRiskLot
// Deskripsi: Menghitung ukuran lot berdasarkan risiko account
// Parameter:
//   riskPercent  = persentase risiko dari saldo (misal 1%)
//   stopLossPips = jarak SL dalam pip
// Return:
//   lot yang aman untuk trade
//==================================================================
double CalculateRiskLot(double riskPercent, double stopLossPips)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);          // saldo account
    double riskAmount = balance * riskPercent / 100.0;           // uang yang berisiko
    double tickValue  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE); // nilai tick
    double tickSize   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);  // ukuran tick
    double lot       = riskAmount / ((stopLossPips * tickValue / tickSize));

    // Sesuaikan dengan minimum/maksimum lot broker
    double lotStep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
    double lotMin  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
    double lotMax  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

    lot = MathMax(lot,lotMin);
    lot = MathMin(lot,lotMax);
    lot = MathFloor(lot/lotStep)*lotStep;

    return lot;
}

//==================================================================
// Fungsi: CalculateSLTP
// Deskripsi: Menghitung Stop Loss dan Take Profit otomatis
// Parameter:
//   dir         = DIR_BUY / DIR_SELL
//   entry       = harga entry
//   stopLossPips= jarak SL (pips)
//   rrRatio     = Risk/Reward Ratio (misal 2 → TP 2x SL)
// Output:
//   sl, tp melalui reference
//==================================================================
void CalculateSLTP(Dir dir,double entry,double stopLossPips,double rrRatio,
                   double &sl,double &tp)
{
    double pipValue = _Point;

    if(dir==DIR_BUY)
    {
        sl = entry - stopLossPips*pipValue;
        tp = entry + stopLossPips*pipValue*rrRatio;
    }
    else if(dir==DIR_SELL)
    {
        sl = entry + stopLossPips*pipValue;
        tp = entry - stopLossPips*pipValue*rrRatio;
    }
    else
    {
        sl=0; tp=0;
    }
}

//==================================================================
// Fungsi: ApplyRiskManagement
// Deskripsi: Menggabungkan perhitungan lot, SL, TP sekaligus
// Parameter:
//   dir         = DIR_BUY / DIR_SELL
//   entry       = harga entry
//   stopLossPips= jarak SL (pips)
//   rrRatio     = risk/reward ratio
//   riskPercent = % risiko account
// Return:
//   NISignalRisk struct yang bisa langsung dipakai di TradeExecutor
//==================================================================
struct NISignalRisk
{
    double lot;
    double sl;
    double tp;
};

NISignalRisk ApplyRiskManagement(Dir dir,double entry,double stopLossPips,
                                 double rrRatio,double riskPercent)
{
    NISignalRisk result;
    result.lot = CalculateRiskLot(riskPercent,stopLossPips);
    CalculateSLTP(dir,entry,stopLossPips,rrRatio,result.sl,result.tp);
    return result;
}


