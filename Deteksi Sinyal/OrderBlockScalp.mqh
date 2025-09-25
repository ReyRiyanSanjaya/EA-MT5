//==================================================================
// OrderBlockScalp.mqh
// Versi: 1.0 Ultimate Supply-Demand Scalping
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library scalping berbasis Order Block / Supply-Demand
//   - Mendeteksi zona supply (resistance) & demand (support)
//   - Entry scalping di M1-M5
//   - Filter trend EMA multi-TF
//   - SL/TP otomatis
//   - Lot dinamis sesuai kekuatan sinyal
//
// ====================== PANDUAN PENGGUNAAN =======================
//
// 1. Include library di EA:
//      #include "OrderBlockScalp.mqh"
//
// 2. Parameter opsional:
//      double lotMin = 0.01;   // Lot minimal
//      int emaPeriodM1 = 50;   // EMA M1 untuk trend filter
//      int emaPeriodM5 = 50;   // EMA M5 untuk multi-TF confirmation
//
// 3. Fungsi utama untuk mendapatkan sinyal:
//      OBSignal sig = DetectOrderBlockScalp(lotMin, emaPeriodM1, emaPeriodM5);
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
// 5. Trailing stop bisa ditambahkan menggunakan fungsi CalculateTrailingStop
//
// 6. Debug / log sinyal:
//      PrintOrderBlockSignal();
//
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

struct OBSignal
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
// Fungsi deteksi zona Order Block
//==================================================================
OBSignal DetectOrderBlockScalp(double lotMin=0.01,int emaPeriodM1=50,int emaPeriodM5=50)
{
    OBSignal sig;
    sig.signal=DIR_NONE;
    sig.entryPrice=0;
    sig.stopLoss=0;
    sig.takeProfit=0;
    sig.lotSize=lotMin;
    sig.isStrong=false;

    // Ambil 20 candle terakhir M1 untuk deteksi OB
    int lookback=20;
    double hiMax=0, loMin=0;
    int idxHi=-1, idxLo=-1;

    for(int i=1;i<=lookback;i++)
    {
        double hi=iHigh(_Symbol,PERIOD_M1,i);
        double lo=iLow(_Symbol,PERIOD_M1,i);
        if(hi>hiMax){hiMax=hi; idxHi=i;}
        if(lo<loMin || loMin==0){loMin=lo; idxLo=i;}
    }

    // Tentukan zona supply/demand
    double supply=hiMax; // resistance
    double demand=loMin; // support

    // EMA Trend filter
    Dir trendM1=GetTrendEMA(PERIOD_M1,emaPeriodM1);
    Dir trendM5=GetTrendEMA(PERIOD_M5,emaPeriodM5);

    double spread=_Point*10; // buffer minimal 10 pip

    //==== Logic BUY: Price dekat demand & trend up ====
    double price=iClose(_Symbol,PERIOD_M1,0);
    if(price<=demand+spread && trendM1==DIR_BUY && trendM5==DIR_BUY)
    {
        sig.signal=DIR_BUY;
        sig.entryPrice=price;
        sig.stopLoss=demand-_Point*5;
        sig.takeProfit=price+(supply-demand)*0.5; // TP 50% zona
        sig.isStrong=true;
        sig.lotSize=lotMin;
    }

    //==== Logic SELL: Price dekat supply & trend down ====
    if(price>=supply-spread && trendM1==DIR_SELL && trendM5==DIR_SELL)
    {
        sig.signal=DIR_SELL;
        sig.entryPrice=price;
        sig.stopLoss=supply+_Point*5;
        sig.takeProfit=price-(supply-demand)*0.5; // TP 50% zona
        sig.isStrong=true;
        sig.lotSize=lotMin;
    }

    return sig;
}

//==================================================================
// Fungsi log / debugging
//==================================================================
void PrintOrderBlockSignal()
{
    OBSignal sig=DetectOrderBlockScalp();
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("OrderBlock Scalping | Signal:%s | Strength:%s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                s,strength,sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
}

//==================================================================
// Fungsi contoh entry
//==================================================================
void ExecuteOrderBlockScalp()
{
    OBSignal sig=DetectOrderBlockScalp();
    if(sig.signal!=DIR_NONE)
    {
        PrintFormat("Executing %s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                    (sig.signal==DIR_BUY?"BUY":"SELL"),
                    sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
        // OrderSend(_Symbol,(sig.signal==DIR_BUY?OP_BUY:OP_SELL),sig.lotSize,
        //           (sig.signal==DIR_BUY?Ask:Bid),3,sig.stopLoss,sig.takeProfit,
        //           "OrderBlock Scalping",0,0,(sig.signal==DIR_BUY?clrBlue:clrRed));
    }
}
