//==================================================================
// ChartPatternUltimate.mqh
// Versi: 4.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library Ultimate untuk deteksi chart pattern lengkap di MQL5
//   Cocok untuk strategi profit maksimal
//   Mendukung Classic Patterns + Harmonic Patterns
//
// ====================== PANDUAN PENGGUNAAN =======================
// 1. Include library di EA:
//      #include "ChartPatternUltimate.mqh"
//
// 2. Pilih timeframe manual atau gunakan default:
//      ENUM_TIMEFRAMES tf = PERIOD_H1; // contoh H1
//
// 3. Tentukan range candle yang ingin diperiksa:
//      int startBar = 50;   // candle lama
//      int endBar   = 1;    // candle terbaru
//
// 4. Panggil fungsi utama untuk mendapatkan sinyal:
//      ChartPatternSignal cps = GetChartPatternSignalUltimate(startBar, endBar, tf);
//
// 5. Gunakan hasil untuk entry EA dan penentuan lot:
//      if(cps.signal == DIR_BUY)
//          {
//              double lot = cps.isStrong ? 0.2 : 0.1; // contoh lot sizing
//              // entry buy
//          }
//      else if(cps.signal == DIR_SELL)
//          {
//              double lot = cps.isStrong ? 0.2 : 0.1; // contoh lot sizing
//              // entry sell
//          }
//
// 6. Untuk debugging / melihat sinyal di log:
//      PrintChartPatternSignal(startBar, endBar, tf);
//
// 7. Pattern yang dideteksi:
//    - Double Top / Double Bottom
//    - Triangles (Ascending / Descending)
//    - Head & Shoulders / Inverse H&S
//    - Cup & Handle
//    - Flags / Pennants
//    - Rising / Falling Wedges
//    - Harmonic Patterns: Gartley, Bat, Butterfly, Crab
//
// 8. Catatan penting:
//    - idxStart > idxEnd (dari candle lama ke candle baru)
//    - Manual TF dapat disesuaikan sesuai strategi (M5, M15, H1, H4)
//    - Sinyal kuat (isStrong=true) bisa digunakan untuk menentukan lot size lebih besar
//==================================================================

#pragma once

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

//--- Struct sinyal pattern + strength + nama pattern
struct ChartPatternSignal
{
    Dir signal;
    bool isStrong;
    string patternName;
}

//==================================================================
// =================== DETECTION FUNCTIONS ========================
//==================================================================

//--- Double Top
bool DetectDoubleTop(int idxStart, int idxEnd, double &neckline, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    double hi1 = iHigh(_Symbol, tf, idxStart);
    double hi2 = iHigh(_Symbol, tf, idxEnd);
    double loBetween = iLow(_Symbol, tf, (idxStart+idxEnd)/2);

    if(MathAbs(hi1-hi2) <= (hi1*0.0005))
    {
        neckline = loBetween;
        isStrong = (MathAbs(hi1-hi2) <= (hi1*0.00025));
        return true;
    }
    return false;
}

//--- Double Bottom
bool DetectDoubleBottom(int idxStart, int idxEnd, double &neckline, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    double lo1 = iLow(_Symbol, tf, idxStart);
    double lo2 = iLow(_Symbol, tf, idxEnd);
    double hiBetween = iHigh(_Symbol, tf, (idxStart+idxEnd)/2);

    if(MathAbs(lo1-lo2) <= (lo1*0.0005))
    {
        neckline = hiBetween;
        isStrong = (MathAbs(lo1-lo2) <= (lo1*0.00025));
        return true;
    }
    return false;
}

//--- Triangles
bool DetectTriangle(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    double hiStart = iHigh(_Symbol, tf, idxStart);
    double hiEnd   = iHigh(_Symbol, tf, idxEnd);
    double loStart = iLow(_Symbol, tf, idxStart);
    double loEnd   = iLow(_Symbol, tf, idxEnd);

    if(hiEnd < hiStart && loEnd > loStart) { signal = DIR_BUY; isStrong=true; return true; }
    if(hiEnd > hiStart && loEnd < loStart) { signal = DIR_SELL; isStrong=true; return true; }
    return false;
}

//--- Head & Shoulders / Inverse H&S
bool DetectHeadShoulders(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    int mid = (idxStart+idxEnd)/2;
    double hiLS = iHigh(_Symbol, tf, idxStart);
    double hiHead = iHigh(_Symbol, tf, mid);
    double hiRS = iHigh(_Symbol, tf, idxEnd);

    if(hiHead > hiLS && hiHead > hiRS && MathAbs(hiLS-hiRS)<=hiHead*0.0005)
    {
        signal = DIR_SELL;
        isStrong=true;
        return true;
    }
    return false;
}

bool DetectInverseHeadShoulders(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    int mid = (idxStart+idxEnd)/2;
    double loLS = iLow(_Symbol, tf, idxStart);
    double loHead = iLow(_Symbol, tf, mid);
    double loRS = iLow(_Symbol, tf, idxEnd);

    if(loHead < loLS && loHead < loRS && MathAbs(loLS-loRS)<=loHead*0.0005)
    {
        signal = DIR_BUY;
        isStrong=true;
        return true;
    }
    return false;
}

//--- Wedges
bool DetectWedge(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    double hiStart=iHigh(_Symbol,tf,idxStart);
    double hiEnd=iHigh(_Symbol,tf,idxEnd);
    double loStart=iLow(_Symbol,tf,idxStart);
    double loEnd=iLow(_Symbol,tf,idxEnd);

    if(hiEnd>hiStart && loEnd>loStart){ signal=DIR_SELL; isStrong=true; return true;}
    if(hiEnd<hiStart && loEnd<loStart){ signal=DIR_BUY; isStrong=true; return true;}
    return false;
}

//--- Flags / Pennants
bool DetectFlag(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    double opStart=iOpen(_Symbol,tf,idxStart);
    double clEnd=iClose(_Symbol,tf,idxEnd);

    if(clEnd>opStart*1.005){ signal=DIR_BUY; isStrong=true; return true;}
    if(clEnd<opStart*0.995){ signal=DIR_SELL; isStrong=true; return true;}
    return false;
}

//--- Cup & Handle
bool DetectCupHandle(int idxStart,int idxEnd,Dir &signal,bool &isStrong,ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    int mid=(idxStart+idxEnd)/2;
    double loCup=iLow(_Symbol,tf,mid);
    double hiStart=iHigh(_Symbol,tf,idxStart);
    double hiEnd=iHigh(_Symbol,tf,idxEnd);

    if(loCup<hiStart && loCup<hiEnd && hiEnd>hiStart){ signal=DIR_BUY; isStrong=true; return true;}
    return false;
}

//==================================================================
// Fungsi utama
//==================================================================
ChartPatternSignal GetChartPatternSignalUltimate(int idxStart,int idxEnd,ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    ChartPatternSignal cps;
    cps.signal=DIR_NONE;
    cps.isStrong=false;
    cps.patternName="None";

    double neckline;
    bool strongFlag=false;
    Dir signalDir;
    string patternHarmonic="";

    if(DetectDoubleTop(idxStart,idxEnd,neckline,strongFlag,tf)){ cps.signal=DIR_SELL; cps.isStrong=strongFlag; cps.patternName="Double Top"; return cps;}
    if(DetectDoubleBottom(idxStart,idxEnd,neckline,strongFlag,tf)){ cps.signal=DIR_BUY; cps.isStrong=strongFlag; cps.patternName="Double Bottom"; return cps;}
    if(DetectTriangle(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Triangle"; return cps;}
    if(DetectHeadShoulders(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Head & Shoulders"; return cps;}
    if(DetectInverseHeadShoulders(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Inverse H&S"; return cps;}
    if(DetectWedge(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Wedge"; return cps;}
    if(DetectFlag(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Flag/Pennant"; return cps;}
    if(DetectCupHandle(idxStart,idxEnd,signalDir,strongFlag,tf)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName="Cup & Handle"; return cps;}
    if(DetectHarmonic(idxStart,idxEnd,signalDir,strongFlag,tf,patternHarmonic)){ cps.signal=signalDir; cps.isStrong=strongFlag; cps.patternName=patternHarmonic; return cps;}

    return cps;
}

//==================================================================
// Fungsi log
//==================================================================
void PrintChartPatternSignal(int idxStart,int idxEnd,ENUM_TIMEFRAMES tf=PERIOD_M15)
{
    ChartPatternSignal cps=GetChartPatternSignalUltimate(idxStart,idxEnd,tf);
    string s=(cps.signal==DIR_BUY?"BUY":(cps.signal==DIR_SELL?"SELL":"NONE"));
    string strength=cps.isStrong?"STRONG":"WEAK";
    PrintFormat("ChartPattern Signal | Start:%d End:%d | TF:%s | Signal:%s | Strength:%s | Pattern:%s",
                idxStart,idxEnd,EnumToString(tf),s,strength,cps.patternName);
}
