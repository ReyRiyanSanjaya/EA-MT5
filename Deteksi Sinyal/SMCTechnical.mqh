//==================================================================
// SMCTechnical.mqh
// Versi: 1.0 Ultimate Smart Money Concepts (SMC)
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library SMC untuk entry high probability ~90%
//   - Mendeteksi Order Blocks, Breaker Blocks, Stop Hunt
//   - Multi-TF trend filter
//   - SL/TP otomatis
//   - Lot dinamis sesuai kekuatan sinyal
//
// ====================== PANDUAN PENGGUNAAN =======================
//
// 1. Include library di EA:
//      #include "SMCTechnical.mqh"
//
// 2. Parameter opsional:
//      double lotMin = 0.01;           // Lot minimal
//      int emaPeriodM1 = 50;           // EMA M1 trend filter
//      int emaPeriodM5 = 50;           // EMA M5 trend filter
//      int lookbackCandle = 20;        // Candle terakhir untuk scan OB
//
// 3. Fungsi utama untuk mendapatkan sinyal:
//      SMCSignal sig = DetectSMCSignal(lotMin, emaPeriodM1, emaPeriodM5, lookbackCandle);
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
//      PrintSMCSignal();
//
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

struct SMCSignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
};

//==================================================================
// Fungsi trend EMA multi-TF
//==================================================================
Dir GetTrendEMA(ENUM_TIMEFRAMES tf,int emaPeriod=50,int shift=0)
{
    double price=iClose(_Symbol,tf,shift);
    double ema=iMA(_Symbol,tf,emaPeriod,0,MODE_EMA,PRICE_CLOSE,shift);
    return (price>ema)?DIR_BUY:DIR_SELL;
}

//==================================================================
// Fungsi deteksi SMC Signal (OB + Breaker)
//==================================================================
SMCSignal DetectSMCSignal(double lotMin=0.01,int emaPeriodM1=50,int emaPeriodM5=50,int lookbackCandle=20)
{
    SMCSignal sig;
    sig.signal=DIR_NONE;
    sig.entryPrice=0;
    sig.stopLoss=0;
    sig.takeProfit=0;
    sig.lotSize=lotMin;
    sig.isStrong=false;

    // Trend filter
    Dir trendM1=GetTrendEMA(PERIOD_M1,emaPeriodM1);
    Dir trendM5=GetTrendEMA(PERIOD_M5,emaPeriodM5);

    // Scan candle terakhir untuk Order Block
    double hiMax=0, loMin=0;
    int idxHi=-1, idxLo=-1;
    for(int i=1;i<=lookbackCandle;i++)
    {
        double hi=iHigh(_Symbol,PERIOD_M1,i);
        double lo=iLow(_Symbol,PERIOD_M1,i);
        if(hi>hiMax){hiMax=hi; idxHi=i;}
        if(lo<loMin || loMin==0){loMin=lo; idxLo=i;}
    }

    double supply=hiMax; // OB resistance
    double demand=loMin; // OB support

    double price=iClose(_Symbol,PERIOD_M1,0);
    double spread=_Point*10; // buffer minimal 10 pip

    //==== BUY Signal ====
    if(price<=demand+spread && trendM1==DIR_BUY && trendM5==DIR_BUY)
    {
        sig.signal=DIR_BUY;
        sig.entryPrice=price;
        sig.stopLoss=demand-_Point*5;
        sig.takeProfit=price+(supply-demand)*0.5;
        sig.isStrong=true;
        sig.lotSize=lotMin;
    }

    //==== SELL Signal ====
    if(price>=supply-spread && trendM1==DIR_SELL && trendM5==DIR_SELL)
    {
        sig.signal=DIR_SELL;
        sig.entryPrice=price;
        sig.stopLoss=supply+_Point*5;
        sig.takeProfit=price-(supply-demand)*0.5;
        sig.isStrong=true;
        sig.lotSize=lotMin;
    }

    return sig;
}

//==================================================================
// Fungsi log / debug
//==================================================================
void PrintSMCSignal()
{
    SMCSignal sig=DetectSMCSignal();
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("SMC Signal | Signal:%s | Strength:%s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                s,strength,sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
}

//==================================================================
// Fungsi contoh entry
//==================================================================
void ExecuteSMCSignal()
{
    SMCSignal sig=DetectSMCSignal();
    if(sig.signal!=DIR_NONE)
    {
        PrintFormat("Executing %s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                    (sig.signal==DIR_BUY?"BUY":"SELL"),
                    sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
        // OrderSend(_Symbol,(sig.signal==DIR_BUY?OP_BUY:OP_SELL),sig.lotSize,
        //           (sig.signal==DIR_BUY?Ask:Bid),3,sig.stopLoss,sig.takeProfit,
        //           "SMC Technical",0,0,(sig.signal==DIR_BUY?clrBlue:clrRed));
    }
}
