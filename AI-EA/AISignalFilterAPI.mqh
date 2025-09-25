//==================================================================
// AISignalFilterAPI.mqh
// Versi: 1.0
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library MQL5 untuk integrasi AI Signal Filter via REST API
//   - Mendapatkan sinyal real-time dari AI model (XGBoost / Random Forest)
//   - Memilih sinyal terbaik untuk dieksekusi
//   - Menyediakan lot, SL, TP, probabilitas, dan flag sinyal kuat
//==================================================================

/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA:
      #include "AISignalFilterAPI.mqh"

2. Siapkan REST API server AI:
   - API mengembalikan JSON:
     {"Signal":"BUY","Lot":0.05,"SL":1.2345,"TP":1.2370,"Probability":0.85,"IsStrong":1}
   - Bisa menggunakan Python Flask/FastAPI dengan model XGBoost/Random Forest.

3. Set URL API:
      string apiURL = "http://127.0.0.1:5000/get_latest_signal";

4. Ambil sinyal AI:
      AISignal sig = GetAISignalFromAPI(apiURL);

5. Debug / log sinyal:
      PrintAISignal(sig);

6. Integrasi ke TradeExecutor atau EA lain:
      if(sig.probability > 0.7 && sig.signal != DIR_NONE)
          OpenTrade(sig.signal, sig.lotSize, sig.stopLoss, sig.takeProfit, "AI Filter API");

7. Catatan:
   - EA tidak melatih AI, hanya membaca output dari server.
   - API harus real-time untuk scalping atau trading aktif.
   - Probabilitas > 0.7 disarankan sebagai threshold sinyal layak entry.
*/

#pragma once
#include <stdlib.mqh>
#include <Wininet.mqh>

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

//--- Struct sinyal AI
struct AISignal
{
    Dir signal;          // Arah sinyal
    double lotSize;      // Lot sesuai AI / RiskManager
    double stopLoss;     // Stop Loss
    double takeProfit;   // Take Profit
    double probability;  // Probabilitas sinyal layak entry (0-1)
    bool isStrong;       // Flag sinyal kuat
};

//==================================================================
// Fungsi: GetAISignalFromAPI
// Deskripsi: Mendapatkan sinyal AI via REST API
// Parameter:
//    url = alamat API
// Return:
//    AISignal struct berisi sinyal, lot, SL, TP, probabilitas
//==================================================================
AISignal GetAISignalFromAPI(string url)
{
    AISignal sig;
    sig.signal = DIR_NONE;
    sig.lotSize = 0.01;
    sig.stopLoss = 0;
    sig.takeProfit = 0;
    sig.probability = 0;
    sig.isStrong = false;

    char result[];
    int res = WebRequest("GET", url, "", "", 5000, result, NULL);
    if(res==200)
    {
        string json = CharArrayToString(result);
        string s_signal, s_lot, s_sl, s_tp, s_prob, s_isStrong;
        s_signal = JsonGet(json,"Signal");
        s_lot    = JsonGet(json,"Lot");
        s_sl     = JsonGet(json,"SL");
        s_tp     = JsonGet(json,"TP");
        s_prob   = JsonGet(json,"Probability");
        s_isStrong = JsonGet(json,"IsStrong");

        if(s_signal=="BUY") sig.signal = DIR_BUY;
        else if(s_signal=="SELL") sig.signal = DIR_SELL;

        sig.lotSize     = StrToDouble(s_lot);
        sig.stopLoss    = StrToDouble(s_sl);
        sig.takeProfit  = StrToDouble(s_tp);
        sig.probability = StrToDouble(s_prob);
        sig.isStrong    = (s_isStrong=="1");
    }
    else
    {
        PrintFormat("GetAISignalFromAPI failed: HTTP code %d", res);
    }

    return sig;
}

//==================================================================
// Fungsi: PrintAISignal
// Deskripsi: Debug / log sinyal AI
//==================================================================
void PrintAISignal(AISignal &sig)
{
    string s = (sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE"));
    string str = sig.isStrong?"STRONG":"WEAK";
    PrintFormat("AI Signal API | Signal:%s | Prob:%.2f | Lot:%.2f | SL:%.5f | TP:%.5f | Strength:%s",
                s,sig.probability,sig.lotSize,sig.stopLoss,sig.takeProfit,str);
}

//==================================================================
// Fungsi bantu sederhana JSON parser
//==================================================================
string JsonGet(string json, string key)
{
    string pattern = "\"" + key + "\":";
    int pos = StringFind(json, pattern);
    if(pos>=0)
    {
        int start = pos + StringLen(pattern);
        int end = StringFind(json,",",start);
        if(end<0) end = StringFind(json,"}",start);
        string val = StringTrim(StringSubstr(json,start,end-start));
        val = StringReplace(val,"\"","");
        return val;
    }
    return "";
}
