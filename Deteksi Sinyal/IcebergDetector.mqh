//==================================================================
// IcebergDetector.mqh
// Versi: 1.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library untuk mendeteksi iceberg order di MQL5.
//   Fitur:
//     - Simple detection: volume besar vs rata-rata normal
//     - Advanced detection: volume + candle pattern + price spike
//     - Multi-TF detection: gabungkan beberapa timeframe
//
// Cara pakai:
//   #include "IcebergDetector.mqh"
//   bool detected = DetectIcebergSimple(0); // candle terakhir
//   bool detected = DetectIcebergAdvanced(0, level);
//   bool detected = DetectIcebergMultiTF(PERIOD_M5, PERIOD_H1, 0);
//==================================================================

#pragma once

//--- Enum untuk level sinyal iceberg
enum IcebergLevel
{
    ICE_NONE,
    ICE_WEAK,
    ICE_STRONG
};

//--- default settings
input double VolumeMultiplierSimple   = 3.0;   // simple: volume candle / average >= 3
input double VolumeMultiplierAdvanced = 2.5;   // advanced: adjusted
input int LookbackCandlesSimple       = 20;    // periode rata-rata volume simple
input int LookbackCandlesAdvanced     = 50;    // periode volume advanced

//==================================================================
// Fungsi: DetectIcebergSimple
// Parameter: idx = candle index
// Return: bool → true jika iceberg terdeteksi
// Deskripsi: bandingkan volume candle terakhir dengan rata-rata 20 candle sebelumnya
//==================================================================
bool DetectIcebergSimple(int idx)
{
    int lookback = LookbackCandlesSimple;
    if(Bars(_Symbol, PERIOD_CURRENT) <= lookback) return false;

    double sumVolume = 0;
    for(int i=idx+1; i<=idx+lookback; i++)
        sumVolume += iVolume(_Symbol, PERIOD_CURRENT, i);

    double avgVolume = sumVolume/lookback;
    double lastVolume = iVolume(_Symbol, PERIOD_CURRENT, idx);

    if(lastVolume >= avgVolume * VolumeMultiplierSimple)
        return true;

    return false;
}

//==================================================================
// Fungsi: DetectIcebergAdvanced
// Parameter: idx = candle index
// Return: IcebergLevel → ICE_NONE, ICE_WEAK, ICE_STRONG
// Deskripsi: volume tinggi + candle spike + body besar
//==================================================================
IcebergLevel DetectIcebergAdvanced(int idx)
{
    int lookback = LookbackCandlesAdvanced;
    if(Bars(_Symbol, PERIOD_CURRENT) <= lookback) return ICE_NONE;

    double sumVolume = 0;
    for(int i=idx+1; i<=idx+lookback; i++)
        sumVolume += iVolume(_Symbol, PERIOD_CURRENT, i);

    double avgVolume = sumVolume/lookback;
    double lastVolume = iVolume(_Symbol, PERIOD_CURRENT, idx);

    double op = iOpen(_Symbol, PERIOD_CURRENT, idx);
    double cl = iClose(_Symbol, PERIOD_CURRENT, idx);
    double hi = iHigh(_Symbol, PERIOD_CURRENT, idx);
    double lo = iLow(_Symbol, PERIOD_CURRENT, idx);

    double body = MathAbs(cl-op);
    double range = hi-lo;

    bool volumeSpike = lastVolume >= avgVolume * VolumeMultiplierAdvanced;
    bool strongBody  = body >= 0.5*range; // minimal body 50% dari range

    if(volumeSpike && strongBody)
        return ICE_STRONG;
    if(volumeSpike)
        return ICE_WEAK;

    return ICE_NONE;
}

//==================================================================
// Fungsi: DetectIcebergMultiTF
// Parameter: tfFast, tfSlow = timeframe, idx = candle index
// Return: IcebergLevel
// Deskripsi: gabungkan deteksi di dua timeframe
//==================================================================
IcebergLevel DetectIcebergMultiTF(ENUM_TIMEFRAMES tfFast, ENUM_TIMEFRAMES tfSlow, int idx)
{
    IcebergLevel fast = DetectIcebergAdvanced(idx); // TF current
    // switch symbol ke slow TF
    double sumVolumeSlow = 0;
    int lookback = LookbackCandlesAdvanced;
    if(Bars(_Symbol, tfSlow) <= lookback) return ICE_NONE;
    for(int i=idx+1; i<=idx+lookback; i++)
        sumVolumeSlow += iVolume(_Symbol, tfSlow, i);
    double avgVolumeSlow = sumVolumeSlow/lookback;
    double lastVolumeSlow = iVolume(_Symbol, tfSlow, idx);

    bool slowSpike = lastVolumeSlow >= avgVolumeSlow * VolumeMultiplierAdvanced;

    // Gabungkan logika: jika keduanya spike → STRONG, jika salah satu → WEAK
    if(fast==ICE_STRONG && slowSpike) return ICE_STRONG;
    if(fast!=ICE_NONE || slowSpike) return ICE_WEAK;

    return ICE_NONE;
}

//==================================================================
// Fungsi: PrintIcebergSignal
// Parameter: idx = candle index
//==================================================================
void PrintIcebergSignal(int idx)
{
    bool simple = DetectIcebergSimple(idx);
    IcebergLevel adv = DetectIcebergAdvanced(idx);
    IcebergLevel multi = DetectIcebergMultiTF(PERIOD_M5, PERIOD_H1, idx);

    string sAdv = (adv==ICE_STRONG?"STRONG":(adv==ICE_WEAK?"WEAK":"NONE"));
    string sMulti = (multi==ICE_STRONG?"STRONG":(multi==ICE_WEAK?"WEAK":"NONE"));

    PrintFormat("Iceberg | CandleIdx:%d | Simple:%s | Advanced:%s | MultiTF:%s",
                idx, simple?"YES":"NO", sAdv, sMulti);
}
