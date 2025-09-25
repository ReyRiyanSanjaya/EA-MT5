//==================================================================
// StochasticUltimate.mqh
// Versi: 3.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library Stochastic Ultimate untuk MQL5
//   Multi-TF cross confirmation, filter trend EMA
//   Oversold <20, Overbought >80
//   SL otomatis berbasis lebar crossover
//
// ====================== PANDUAN PENGGUNAAN =======================
// 1. Include library di EA:
//      #include "StochasticUltimate.mqh"
//
// 2. Pilih TF rendah (entry) dan TF tinggi (konfirmasi):
//      ENUM_TIMEFRAMES tfLow = PERIOD_M5;
//      ENUM_TIMEFRAMES tfHigh = PERIOD_H1;
//
// 3. Tentukan parameter Stochastic dan EMA:
//      int kPeriod=14, dPeriod=3, slowing=3, emaPeriod=50;
//
// 4. Panggil fungsi untuk mendapatkan sinyal:
//      StochSignal sig = GetStochasticSignalUltimate(tfLow, tfHigh, kPeriod, dPeriod, slowing, emaPeriod);
//
// 5. Gunakan sinyal untuk entry dan lot sizing:
//      if(sig.signal==DIR_BUY && sig.isStrong){ lot=0.2; }
//      if(sig.signal==DIR_SELL && sig.isStrong){ lot=0.2; }
//
// 6. Hitung SL otomatis berdasarkan crossover:
//      double sl = CalculateSL(tfLow, kPeriod, dPeriod, slowing);
//
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

struct StochSignal
{
    Dir signal;           // BUY / SELL / NONE
    double kValueLow;     // nilai K TF rendah
    double dValueLow;     // nilai D TF rendah
    double kValueHigh;    // nilai K TF tinggi
    double dValueHigh;    // nilai D TF tinggi
    bool isStrong;        // sinyal kuat/lemah
};

//==================================================================
// Fungsi trend EMA
//==================================================================
Dir GetTrendEMA(ENUM_TIMEFRAMES tf,int emaPeriod=50,int shift=0)
{
    double price=iClose(_Symbol,tf,shift);
    double ema=iMA(_Symbol,tf,emaPeriod,0,MODE_EMA,PRICE_CLOSE,shift);
    return (price>ema)?DIR_BUY:DIR_SELL;
}

//==================================================================
// Fungsi utama multi-TF cross confirmation
//==================================================================
StochSignal GetStochasticSignalUltimate(ENUM_TIMEFRAMES tfLow,
                                        ENUM_TIMEFRAMES tfHigh,
                                        int kPeriod=14,
                                        int dPeriod=3,
                                        int slowing=3,
                                        int emaPeriod=50,
                                        int shift=0)
{
    StochSignal sig;
    sig.signal=DIR_NONE;
    sig.isStrong=false;

    //--- TF rendah (entry cepat)
    double kLow=iStochastic(_Symbol,tfLow,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_MAIN,shift);
    double dLow=iStochastic(_Symbol,tfLow,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_SIGNAL,shift);
    sig.kValueLow=kLow;
    sig.dValueLow=dLow;

    //--- TF tinggi (konfirmasi trend)
    double kHigh=iStochastic(_Symbol,tfHigh,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_MAIN,shift);
    double dHigh=iStochastic(_Symbol,tfHigh,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_SIGNAL,shift);
    sig.kValueHigh=kHigh;
    sig.dValueHigh=dHigh;

    Dir trendHigh = GetTrendEMA(tfHigh, emaPeriod, shift);

    //--- Tentukan sinyal
    if(kLow<20 && trendHigh==DIR_BUY)
    {
        sig.signal=DIR_BUY;
        sig.isStrong=true;
    }
    else if(kLow>80 && trendHigh==DIR_SELL)
    {
        sig.signal=DIR_SELL;
        sig.isStrong=true;
    }
    else if(kLow<20) { sig.signal=DIR_BUY; sig.isStrong=false; }
    else if(kLow>80) { sig.signal=DIR_SELL; sig.isStrong=false; }

    return sig;
}

//==================================================================
// Fungsi hitung SL berdasarkan lebar crossover Stochastic
//==================================================================
double CalculateSL(ENUM_TIMEFRAMES tfLow,
                   int kPeriod=14,
                   int dPeriod=3,
                   int slowing=3,
                   double riskMultiplier=1.0)
{
    double k=iStochastic(_Symbol,tfLow,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_MAIN,0);
    double d=iStochastic(_Symbol,tfLow,kPeriod,dPeriod,slowing,MODE_SMA,0,MODE_SIGNAL,0);

    double diff=MathAbs(k-d);
    double pointSize=_Point;
    double slPips=0;

    // Crossover besar (>40) → SL lebar
    if(diff>40) slPips=diff*1.5*pointSize*riskMultiplier;
    else slPips=diff*0.8*pointSize*riskMultiplier;

    // minimal SL tetap >0
    if(slPips<10*pointSize) slPips=10*pointSize;

    return slPips;
}

//==================================================================
// Fungsi log
//==================================================================
void PrintStochasticSignalUltimate(ENUM_TIMEFRAMES tfLow,
                                   ENUM_TIMEFRAMES tfHigh,
                                   int kPeriod=14,
                                   int dPeriod=3,
                                   int slowing=3,
                                   int emaPeriod=50,
                                   int shift=0)
{
    StochSignal sig=GetStochasticSignalUltimate(tfLow,tfHigh,kPeriod,dPeriod,slowing,emaPeriod,shift);
    double sl = CalculateSL(tfLow,kPeriod,dPeriod,slowing);
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("Stochastic Ultimate | Signal:%s | Strength:%s | SL:%.5f | K_Low:%.2f | D_Low:%.2f | K_High:%.2f | D_High:%.2f",
                s,strength,sl,sig.kValueLow,sig.dValueLow,sig.kValueHigh,sig.dValueHigh);
}

//==================================================================
// Fungsi contoh order (bisa dipakai di EA)
//==================================================================
void ExecuteStochasticTrade(ENUM_TIMEFRAMES tfLow, ENUM_TIMEFRAMES tfHigh, double lotSize=0.1)
{
    StochSignal sig=GetStochasticSignalUltimate(tfLow,tfHigh);
    double sl=CalculateSL(tfLow);

    if(sig.signal==DIR_BUY)
    {
        double slPrice=iClose(_Symbol,tfLow,0)-sl;
        PrintFormat("BUY Signal | SL: %.5f", slPrice);
        // OrderSend(_Symbol,OP_BUY,lotSize,Ask,3,slPrice,0,"Stoch BUY",0,0,clrGreen);
    }
    else if(sig.signal==DIR_SELL)
    {
        double slPrice=iClose(_Symbol,tfLow,0)+sl;
        PrintFormat("SELL Signal | SL: %.5f", slPrice);
        // OrderSend(_Symbol,OP_SELL,lotSize,Bid,3,slPrice,0,"Stoch SELL",0,0,clrRed);
    }
}
