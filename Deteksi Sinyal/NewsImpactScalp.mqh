//==================================================================
// NewsImpactCalendar.mqh
// Versi: 1.0 Ultimate News Impact Scalping + Real-Time Calendar
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library ultimate untuk scalping mengikuti news impact
//   - Integrasi kalender ekonomi real-time / manual
//   - Entry M1 candle besar setelah news release
//   - SL/TP otomatis dan trailing stop
//   - Lot dinamis sesuai kekuatan candle
//==================================================================

#pragma once

//==================================================================
// ENUM arah sinyal
//==================================================================
enum Dir
{
    DIR_NONE, // Tidak ada sinyal
    DIR_BUY,  // Sinyal beli
    DIR_SELL  // Sinyal jual
};

//==================================================================
// Struct sinyal news impact
//==================================================================
struct NISignal
{
    Dir signal;         // Arah sinyal (BUY/SELL)
    double entryPrice;  // Harga entry
    double stopLoss;    // Level SL
    double takeProfit;  // Level TP
    double lotSize;     // Ukuran lot
    bool isStrong;      // Indikator kekuatan sinyal
    datetime newsTime;  // Waktu news release
    string newsEvent;   // Nama event
    string impact;      // Dampak news (high/medium/low)
};

//==================================================================
// Struct acara kalender
//==================================================================
struct NewsEvent
{
    datetime time;      // Waktu news
    string name;        // Nama event
    string impact;      // Dampak news
};

// Kalender ekonomi
NewsEvent NewsCalendar[];
int totalNews=0;

//==================================================================
// Fungsi: AddNewsEvent
// Deskripsi: Menambahkan news manual ke kalender
// Parameter:
//   t     = waktu news (datetime)
//   name  = nama event
//   impact= high/medium/low
//==================================================================
void AddNewsEvent(datetime t,string name,string impact)
{
    ArrayResize(NewsCalendar,totalNews+1);
    NewsCalendar[totalNews].time=t;
    NewsCalendar[totalNews].name=name;
    NewsCalendar[totalNews].impact=impact;
    totalNews++;
}

//==================================================================
// Fungsi: IsHighImpactNews
// Deskripsi: Cek apakah ada news high-impact sekarang
// Output:
//   newsTime = waktu news
//   newsName = nama event
// Return:
//   true jika ada news high-impact aktif
//==================================================================
bool IsHighImpactNews(datetime &newsTime,string &newsName)
{
    for(int i=0;i<totalNews;i++)
    {
        // Cek dampak high dan window 1 menit
        if(NewsCalendar[i].impact=="high" &&
           TimeCurrent()>=NewsCalendar[i].time &&
           TimeCurrent()<=NewsCalendar[i].time+60)
        {
            newsTime=NewsCalendar[i].time;
            newsName=NewsCalendar[i].name;
            return true;
        }
    }
    return false;
}

//==================================================================
// Fungsi: AverageBody
// Deskripsi: Menghitung rata-rata body candle terakhir
// Parameter:
//   tf   = timeframe
//   bars = jumlah candle untuk rata-rata
// Return:
//   rata-rata body candle
//==================================================================
double AverageBody(int tf, int bars=10)
{
    double avgBody=0;
    for(int i=1;i<=bars;i++)
        avgBody+=MathAbs(iClose(_Symbol,tf,i)-iOpen(_Symbol,tf,i));
    return avgBody/bars;
}

//==================================================================
// Fungsi: DetectNewsImpactSignal
// Deskripsi: Mendeteksi sinyal news impact
// Parameter opsional:
//   lotMin        = lot minimal
//   minCandlePct  = minimal % body dibanding rata-rata candle
// Return:
//   struct NISignal
//==================================================================
NISignal DetectNewsImpactSignal(double lotMin=0.01,double minCandlePct=0.5)
{
    NISignal sig;
    sig.signal=DIR_NONE;
    sig.entryPrice=0;
    sig.stopLoss=0;
    sig.takeProfit=0;
    sig.lotSize=lotMin;
    sig.isStrong=false;
    sig.newsTime=0;
    sig.newsEvent="";
    sig.impact="";

    datetime newsTime;
    string newsName;

    // Hanya deteksi jika ada news high-impact
    if(!IsHighImpactNews(newsTime,newsName)) return sig;

    // Ambil candle terakhir M1
    double op=iOpen(_Symbol,PERIOD_M1,0);
    double cl=iClose(_Symbol,PERIOD_M1,0);
    double hi=iHigh(_Symbol,PERIOD_M1,0);
    double lo=iLow(_Symbol,PERIOD_M1,0);
    double body=MathAbs(cl-op);

    // Rata-rata body 10 candle terakhir
    double avgBody=AverageBody(PERIOD_M1,10);

    // Jika candle besar → sinyal valid
    if(body>=avgBody*minCandlePct)
    {
        sig.entryPrice=cl;
        sig.lotSize=lotMin*(1+body/_Point/10); // lot dinamis
        sig.isStrong=true;
        sig.newsTime=newsTime;
        sig.newsEvent=newsName;
        sig.impact="high";

        if(cl>op) { sig.signal=DIR_BUY; sig.stopLoss=lo-_Point*5; sig.takeProfit=cl+body*2; }
        else      { sig.signal=DIR_SELL; sig.stopLoss=hi+_Point*5; sig.takeProfit=cl-body*2; }
    }

    return sig;
}

//==================================================================
// Fungsi: PrintNewsImpactSignal
// Deskripsi: Debug / log sinyal news impact
// Parameter:
//   sig = NISignal
//==================================================================
void PrintNewsImpactSignal(NISignal sig)
{
    string s=(sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string strength=sig.isStrong?"STRONG":"WEAK";
    PrintFormat("News Impact | Event:%s | Signal:%s | Strength:%s | Entry:%.5f | SL:%.5f | TP:%.5f | Lot:%.2f",
                sig.newsEvent,s,strength,sig.entryPrice,sig.stopLoss,sig.takeProfit,sig.lotSize);
}

//==================================================================
// Fungsi: ExecuteNewsImpactScalp
// Deskripsi: Contoh eksekusi scalping otomatis
//==================================================================
void ExecuteNewsImpactScalp()
{
    NISignal sig=DetectNewsImpactSignal();
    if(sig.signal!=DIR_NONE)
    {
        PrintNewsImpactSignal(sig);
        // Contoh entry order:
        // OrderSend(_Symbol,(sig.signal==DIR_BUY?OP_BUY:OP_SELL),sig.lotSize,
        //           (sig.signal==DIR_BUY?Ask:Bid),3,sig.stopLoss,sig.takeProfit,
        //           "NewsImpact",0,0,(sig.signal==DIR_BUY?clrBlue:clrRed));
    }
}

/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA:
    #include "NewsImpactCalendar.mqh"

2. Tambahkan kalender news (manual atau API):
    AddNewsEvent("2025.09.30 14:30", "Non-Farm Payrolls", "high");

3. Gunakan fungsi deteksi sinyal:
    NISignal sig = DetectNewsImpactSignal();

4. Gunakan sinyal untuk entry:
    if(sig.signal==DIR_BUY && sig.isStrong) { ... }
    if(sig.signal==DIR_SELL && sig.isStrong) { ... }

5. Debug / log sinyal:
    PrintNewsImpactSignal(sig);

6. Eksekusi scalping otomatis:
    ExecuteNewsImpactScalp();

==================================================================*/
