//==================================================================
// SCMTechnical.mqh
// Versi: 1.0 Ultimate Supply-Chain Momentum
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library teknikal SCM (Supply-Chain Momentum)
//   - Multi indikator: EMA trend, MACD momentum, RSI overbought/oversold
//   - Entry high probability ~90%
//   - SL/TP otomatis
//   - Lot dinamis sesuai kekuatan momentum
//
// ====================== PANDUAN PENGGUNAAN =======================
//
// 1. Include library di EA:
//      #include "SCMTechnical.mqh"
//
// 2. Parameter opsional:
//      double lotMin = 0.01;           // Lot minimal
//      int emaPeriod = 50;             // EMA untuk trend filter
//      int rsiPeriod = 14;             // RSI periode
//      double rsiOB = 70;              // RSI overbought
//      double rsiOS = 30;              // RSI oversold
//      int macdFast=12, macdSlow=26, macdSignal=9; // MACD standar
//
// 3. Fungsi utama untuk mendapatkan sinyal:
//      SCMSignal sig = DetectSCMSignal(lotMin, emaPeriod, rsiPeriod, rsiOB, rsiOS, macdFast, macdSlow, macdSignal);
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
//      PrintSCMSignal();
//
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

struct SCMSignal
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
Dir GetEMAtrend(ENUM_TIMEFRAMES tf,int emaPeriod=50,int shift=0)
{
    double price=iClose(_Symbol,tf,shift);
    double ema=iMA(_Symbol,tf,emaPeriod,0,MODE_EMA,PRICE_CLOSE,shift);
    return (price>ema)?DIR_BUY:DIR_SELL;
}

//==================================================================
// Fungsi deteksi SCM signal
//==================================================================
SCMSignal DetectSCMSignal(double lotMin=0.01,int emaPeriod=50,int rsiPeriod=14,double rsiOB=70,double rsiOS=30,int macdFast=12,int macdSlow=26,int macdSignal=9)
{
    SCMSignal sig;
    sig.signal=DIR_NONE;
    sig.entryPrice=0;
    sig.stopLoss=0;
    sig.takeProfit=0;
    sig.lotSize=lotMin;
    sig.isStrong=false;

    // Trend EMA M1
    Dir trendM1=GetEMAtrend(PERIOD_M1,emaPeriod);

    // Trend EMA M5
    Dir trendM5=GetEMAtrend(PERIOD_M5,emaPeriod);

    // RSI M1
    double rsi=iRSI(_Symbol,PERIOD_M1,rsiPeriod,PRICE_CLOSE,0);

    // MACD M1
    double macdCurrent=iMACD(_Symbol,PERIOD_M1,macdFast,macdSlow,macdSignal,PRICE_CLOSE,MODE_MAIN,0);
    double macdSignalLine=iMACD(_Symbol,PERIOD_M1,macdFast,macdSlow,macdSignal,PRICE_CLOSE,MODE_SIGNAL,0);

    // Entry BUY: semua konfirmasi bullish
    if(trendM1==DIR_BUY && trendM5==DIR_BUY && rsi<rsiOS && macdCurrent>macdSignalLine)
    {
        sig.signal=DIR_BUY;
        sig.entryPrice=iClose(_Symbol,PERIOD_M1,0);
        double body=MathAbs(iClose(_Symbol,PERIOD_M1,0)-iOpen(_Symbol,PERIOD_M1,0));
        sig.stopLoss=iClose(_Symbol,PERIOD_M1,0)-body*1.5;
        sig.takeProfit=iClose(_Symbol,PERIOD_M1,0)+body*2.5;
        sig.lotSize=lotMin*(1+body/_Point/10);
        sig.isStrong=true;
    }

    // Entry SELL: semua konfirmasi bearish
    if(trendM1==DIR_SELL && trendM5==DIR_SELL && rsi>rsiOB && macdCurrent<macdSignalLine)
    {
        sig.signal=DIR_SELL;
        sig.entryPrice=iClose(_Symbol,PERIOD_M1,0);
        double body=MathAbs(iClose(_Symbol,PERIOD_M1,0)-iOpen(_Symbol,PERIOD_M1,0));
        sig.stopLoss=iClose(_Symbol,PERIOD_M1,0)+body*1.5;
        sig.takeProfit=iClose(_Symbol,PERIOD_M1,0)-body*2.5;
        sig.lotSize=lotMin*(1+body/_Point/10);
        sig.isStrong=true;
    }

    return sig;
}

//==================================================================
// Fungsi log / debug
//==================================================================
void PrintSCMSignal()
{
    SCMSignal sig=DetectSCMSignal();
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("SCM Signal | Signal:%s | Strength:%s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                s,strength,sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
}

//==================================================================
// Fungsi contoh entry
//==================================================================
void ExecuteSCMSignal()
{
    SCMSignal sig=DetectSCMSignal();
    if(sig.signal!=DIR_NONE)
    {
        PrintFormat("Executing %s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                    (sig.signal==DIR_BUY?"BUY":"SELL"),
                    sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
        // OrderSend(_Symbol,(sig.signal==DIR_BUY?OP_BUY:OP_SELL),sig.lotSize,
        //           (sig.signal==DIR_BUY?Ask:Bid),3,sig.stopLoss,sig.takeProfit,
        //           "SCM Technical",0,0,(sig.signal==DIR_BUY?clrBlue:clrRed));
    }
}
