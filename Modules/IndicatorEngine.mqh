//==================================================================
// IndicatorLoaderMultiTF.mqh
// Versi: 1.1 Multi-TF Loader
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library untuk load indikator multi-TF sekaligus
//   - Data siap pakai untuk semua modul sinyal
//   - Mendukung EMA, SMA, RSI, Stochastic, MACD, ATR, CCI
//==================================================================


/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library:
      #include "IndicatorLoaderMultiTF.mqh"

2. Load indikator multi-TF:
      MultiTFIndicators ind = LoadMultiTFIndicators(PERIOD_M1, PERIOD_M5);

3. Akses data indikator:
      // TF Entry (M1)
      Print("EMA Fast M1: ", ind.tfEntry.emaFast);
      Print("RSI M1: ", ind.tfEntry.rsi);

      // TF Trend (M5)
      Print("EMA Fast M5: ", ind.tfTrend.emaFast);
      Print("MACD M5: ", ind.tfTrend.macdMain);

4. Gunakan data ini untuk semua modul sinyal:
      - MomentumDetector
      - ChartPatternUltimate
      - Harmonic Patterns
      - Order Block / Supply-Demand
      - NewsImpactScalp
      - Candle Pattern 3+1
      - SMC / SCM
      - Multi-TF Confirmation
      - Scalping / Trend + Pullback

5. Library ini hanya **load data indikator**, tidak melakukan eksekusi trading.

==================================================================
*/


#pragma once

enum Dir { DIR_NONE, DIR_BUY, DIR_SELL };

struct IndicatorData
{
    double emaFast;
    double emaSlow;
    double sma;
    double rsi;
    double stochasticK;
    double stochasticD;
    double macdMain;
    double macdSignal;
    double atr;
    double cci;
};

struct MultiTFIndicators
{
    IndicatorData tfEntry;   // TF entry, misal M1
    IndicatorData tfTrend;   // TF trend, misal M5 atau M15
};

//===================== FUNGSI LOAD INDIKATOR ====================
double LoadEMA(ENUM_TIMEFRAMES tf,int period,int shift=0){ return iMA(_Symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE, shift);}
double LoadSMA(ENUM_TIMEFRAMES tf,int period,int shift=0){ return iMA(_Symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE, shift);}
double LoadRSI(ENUM_TIMEFRAMES tf,int period,int shift=0){ return iRSI(_Symbol, tf, period, PRICE_CLOSE, shift);}
void LoadStochastic(ENUM_TIMEFRAMES tf,int Kperiod,int Dperiod,int slowing,double &K,double &D,int shift=0)
{
    K = iStochastic(_Symbol, tf, Kperiod, Dperiod, slowing, MODE_SMA, 0, MODE_MAIN, shift);
    D = iStochastic(_Symbol, tf, Kperiod, Dperiod, slowing, MODE_SMA, 0, MODE_SIGNAL, shift);
}
void LoadMACD(ENUM_TIMEFRAMES tf,int fastEMA,int slowEMA,int signalSMA,double &macdMain,double &macdSignal,int shift=0)
{
    macdMain = iMACD(_Symbol, tf, fastEMA, slowEMA, signalSMA, PRICE_CLOSE, MODE_MAIN, shift);
    macdSignal = iMACD(_Symbol, tf, fastEMA, slowEMA, signalSMA, PRICE_CLOSE, MODE_SIGNAL, shift);
}
double LoadATR(ENUM_TIMEFRAMES tf,int period,int shift=0){ return iATR(_Symbol, tf, period, shift);}
double LoadCCI(ENUM_TIMEFRAMES tf,int period,int shift=0){ return iCCI(_Symbol, tf, period, PRICE_TYPICAL, shift);}

//===================== FUNGSI LOAD SEMUA =========================
IndicatorData LoadIndicators(ENUM_TIMEFRAMES tf)
{
    IndicatorData data;
    data.emaFast = LoadEMA(tf,9);
    data.emaSlow = LoadEMA(tf,21);
    data.sma     = LoadSMA(tf,50);
    data.rsi     = LoadRSI(tf,14);
    LoadStochastic(tf,14,3,3,data.stochasticK,data.stochasticD);
    LoadMACD(tf,12,26,9,data.macdMain,data.macdSignal);
    data.atr     = LoadATR(tf,14);
    data.cci     = LoadCCI(tf,20);
    return data;
}

//===================== FUNGSI LOAD MULTI-TF ======================
MultiTFIndicators LoadMultiTFIndicators(ENUM_TIMEFRAMES tfEntry, ENUM_TIMEFRAMES tfTrend)
{
    MultiTFIndicators mtf;
    mtf.tfEntry = LoadIndicators(tfEntry);
    mtf.tfTrend = LoadIndicators(tfTrend);
    return mtf;
}

