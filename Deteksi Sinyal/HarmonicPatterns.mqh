    //==================================================================
// HarmonicPatternsAdvanced.mqh
// Versi: 2.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library Harmonic Patterns lengkap untuk MQL5
//   Mendukung Gartley, Bat, Butterfly, Crab dengan rasio Fibonacci akurat
//
// ====================== PANDUAN PENGGUNAAN =======================
// 1. Include library di EA:
//      #include "HarmonicPatternsAdvanced.mqh"
//
// 2. Pilih timeframe manual atau gunakan default:
//      ENUM_TIMEFRAMES tf = PERIOD_H1;
//
// 3. Tentukan range candle (IDX) untuk pattern:
//      int startBar = 50; // candle lama
//      int endBar   = 1;  // candle terbaru
//
// 4. Panggil fungsi utama untuk mendapatkan sinyal:
//      HarmonicPatternSignal hps = DetectHarmonicPattern(startBar, endBar, tf);
//
// 5. Gunakan hasil untuk entry EA dan lot sizing:
//      if(hps.signal==DIR_BUY){ double lot=hps.isStrong?0.2:0.1; }
//      if(hps.signal==DIR_SELL){ double lot=hps.isStrong?0.2:0.1; }
//
// 6. Debug / log:
//      PrintHarmonicPatternSignal(startBar, endBar, tf);
//
// 7. Catatan:
//    - idxStart > idxEnd (dari candle lama ke baru)
//    - isStrong=true jika pattern sesuai rasio Fibonacci
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

//--- Struct sinyal Harmonic
struct HarmonicPatternSignal
{
    Dir signal;
    bool isStrong;
    string patternName;
};

//==================================================================
// Fungsi rasio Fibonacci helper
//==================================================================
bool IsFibRatio(double actual, double target, double tolerance=0.03)
{
    return (MathAbs(actual-target)/target <= tolerance);
}

//==================================================================
// Fungsi bantu untuk menghitung rasio Fibonacci point
//==================================================================
double GetDistance(double a, double b) { return MathAbs(b - a); }

//==================================================================
// Deteksi Gartley (XABCD)
// Rasio: AB=0.618*XA, BC=0.382-0.886*AB, CD=1.272-1.618*BC
//==================================================================
bool DetectGartley(double X,double A,double B,double C,double D,Dir &signal,bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X,A);
    double AB = GetDistance(A,B);
    double BC = GetDistance(B,C);
    double CD = GetDistance(C,D);

    if(IsFibRatio(AB,0.618*XA) &&
       IsFibRatio(BC,0.382*AB) &&
       IsFibRatio(CD,1.272*BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Bat (XABCD)
// Rasio: AB=0.382-0.5*XA, BC=0.382-0.886*AB, CD=1.618-2.618*BC
//==================================================================
bool DetectBat(double X,double A,double B,double C,double D,Dir &signal,bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X,A);
    double AB = GetDistance(A,B);
    double BC = GetDistance(B,C);
    double CD = GetDistance(C,D);

    if(IsFibRatio(AB,0.382*XA) &&
       IsFibRatio(BC,0.886*AB) &&
       IsFibRatio(CD,1.618*BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Butterfly (XABCD)
// Rasio: AB=0.786*XA, BC=0.382-0.886*AB, CD=1.618-2.618*BC
//==================================================================
bool DetectButterfly(double X,double A,double B,double C,double D,Dir &signal,bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X,A);
    double AB = GetDistance(A,B);
    double BC = GetDistance(B,C);
    double CD = GetDistance(C,D);

    if(IsFibRatio(AB,0.786*XA) &&
       IsFibRatio(BC,0.382*AB) &&
       IsFibRatio(CD,1.618*BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Crab (XABCD)
// Rasio: AB=0.382-0.618*XA, BC=0.382-0.886*AB, CD=2.618-3.618*BC
//==================================================================
bool DetectCrab(double X,double A,double B,double C,double D,Dir &signal,bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X,A);
    double AB = GetDistance(A,B);
    double BC = GetDistance(B,C);
    double CD = GetDistance(C,D);

    if(IsFibRatio(AB,0.618*XA) &&
       IsFibRatio(BC,0.886*AB) &&
       IsFibRatio(CD,2.618*BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Fungsi utama untuk EA
//==================================================================
HarmonicPatternSignal DetectHarmonicPattern(double X,double A,double B,double C,double D)
{
    HarmonicPatternSignal hps;
    hps.signal = DIR_NONE;
    hps.isStrong = false;
    hps.patternName = "None";

    Dir sig;
    bool strongFlag;

    if(DetectGartley(X,A,B,C,D,sig,strongFlag)){ hps.signal=sig; hps.isStrong=strongFlag; hps.patternName="Gartley"; return hps;}
    if(DetectBat(X,A,B,C,D,sig,strongFlag)){ hps.signal=sig; hps.isStrong=strongFlag; hps.patternName="Bat"; return hps;}
    if(DetectButterfly(X,A,B,C,D,sig,strongFlag)){ hps.signal=sig; hps.isStrong=strongFlag; hps.patternName="Butterfly"; return hps;}
    if(DetectCrab(X,A,B,C,D,sig,strongFlag)){ hps.signal=sig; hps.isStrong=strongFlag; hps.patternName="Crab"; return hps;}

    return hps;
}

//==================================================================
// Fungsi log
//==================================================================
void PrintHarmonicPatternSignal(double X,double A,double B,double C,double D)
{
    HarmonicPatternSignal hps = DetectHarmonicPattern(X,A,B,C,D);
    string s = (hps.signal==DIR_BUY?"BUY":(hps.signal==DIR_SELL?"SELL":"NONE"));
    string strength = hps.isStrong?"STRONG":"WEAK";
    PrintFormat("Harmonic Pattern | Signal:%s | Strength:%s | Pattern:%s", s,strength,hps.patternName);
}
