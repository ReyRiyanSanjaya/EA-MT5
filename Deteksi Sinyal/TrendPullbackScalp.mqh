//==================================================================
// TrendPullbackScalp.mqh
// Versi: 1.0 Ultimate Trend+Pullback Scalping
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library scalping dengan strategi Trend + Pullback
//   - Trend filter EMA M1 & M5
//   - Entry saat harga pullback ke EMA sesuai arah trend
//   - SL/TP otomatis berdasarkan candle pullback
//   - Lot dinamis untuk profit maksimal
//
// ====================== PANDUAN PENGGUNAAN =======================
//
// 1. Include library di EA:
//      #include "TrendPullbackScalp.mqh"
//
// 2. Parameter opsional:
//      double lotMin = 0.01;        // Lot minimal
//      int emaPeriodM1 = 50;        // EMA periode TF M1
//      int emaPeriodM5 = 50;        // EMA periode TF M5 (multi-TF filter)
//      double pullbackPct = 0.5;    // Pullback rasio terhadap candle terakhir (50% default)
//
// 3. Fungsi utama untuk mendapatkan sinyal:
//      TPSignal sig = DetectTrendPullbackScalp(lotMin, emaPeriodM1, emaPeriodM5, pullbackPct);
//
// 4. Gunakan data signal untuk entry di EA:
//      if(sig.signal==DIR_BUY && sig.isStrong)
//      {
//          double entry = sig.entryPrice;
//          double sl    = sig.stopLoss;
//          double tp    = sig.takeProfit;
//          double lot   = sig.lotSize;
//      }
//      else if(sig.signal==DIR_SELL && sig.isStrong)
//      {
//          double entry = sig.entryPrice;
//          double sl    = sig.stopLoss;
//          double tp    = sig.takeProfit;
//          double lot   = sig.lotSize;
//      }
//
// 5. Fungsi debug / log:
//      PrintTrendPullbackSignal();
//
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

struct TPSignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
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
// Fungsi deteksi pullback scalping
//==================================================================
TPSignal DetectTrendPullbackScalp(double lotMin=0.01,int emaPeriodM1=50,int emaPeriodM5=50,double pullbackPct=0.5)
{
    TPSignal sig;
    sig.signal=DIR_NONE;
    sig.entryPrice=0;
    sig.stopLoss=0;
    sig.takeProfit=0;
    sig.lotSize=lotMin;
    sig.isStrong=false;

    // EMA Trend filter
    double emaM1=iMA(_Symbol,PERIOD_M1,emaPeriodM1,0,MODE_EMA,PRICE_CLOSE,0);
    double emaM5=iMA(_Symbol,PERIOD_M5,emaPeriodM5,0,MODE_EMA,PRICE_CLOSE,0);

    Dir trendM1=(iClose(_Symbol,PERIOD_M1,0)>emaM1)?DIR_BUY:DIR_SELL;
    Dir trendM5=(iClose(_Symbol,PERIOD_M5,0)>emaM5)?DIR_BUY:DIR_SELL;

    // Ambil candle terakhir M1
    double op=iOpen(_Symbol,PERIOD_M1,0);
    double cl=iClose(_Symbol,PERIOD_M1,0);
    double hi=iHigh(_Symbol,PERIOD_M1,0);
    double lo=iLow(_Symbol,PERIOD_M1,0);

    double body=MathAbs(cl-op);
    double pullbackLevel=(trendM1==DIR_BUY)?lo+body*pullbackPct:hi-body*pullbackPct;

    //==== Logic BUY ====
    if(trendM1==DIR_BUY && trendM5==DIR_BUY && cl>=pullbackLevel)
    {
        sig.signal=DIR_BUY;
        sig.entryPrice=cl;
        sig.stopLoss=lo-_Point*5;
        sig.takeProfit=cl+body*2;
        sig.isStrong=true;
        sig.lotSize=lotMin*(1+body/_Point/10);
    }

    //==== Logic SELL ====
    if(trendM1==DIR_SELL && trendM5==DIR_SELL && cl<=pullbackLevel)
    {
        sig.signal=DIR_SELL;
        sig.entryPrice=cl;
        sig.stopLoss=hi+_Point*5;
        sig.takeProfit=cl-body*2;
        sig.isStrong=true;
        sig.lotSize=lotMin*(1+body/_Point/10);
    }

    return sig;
}

//==================================================================
// Fungsi debug / log
//==================================================================
void PrintTrendPullbackSignal()
{
    TPSignal sig=DetectTrendPullbackScalp();
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("Trend+Pullback Scalping | Signal:%s | Strength:%s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                s,strength,sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
}

//==================================================================
// Fungsi contoh entry
//==================================================================
void ExecuteTrendPullbackScalp()
{
    TPSignal sig=DetectTrendPullbackScalp();
    if(sig.signal!=DIR_NONE)
    {
        PrintFormat("Executing %s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                    (sig.signal==DIR_BUY?"BUY":"SELL"),
                    sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
        // OrderSend(_Symbol,(sig.signal==DIR_BUY?OP_BUY:OP_SELL),sig.lotSize,
        //           (sig.signal==DIR_BUY?Ask:Bid),3,sig.stopLoss,sig.takeProfit,
        //           "Trend+Pullback Scalping",0,0,(sig.signal==DIR_BUY?clrBlue:clrRed));
    }
}
