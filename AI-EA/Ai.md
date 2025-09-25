//==================================================================
// ExampleEA.mq5
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Contoh penggunaan AI Signal Filter API di MT5
//   - Mengirim 10 sinyal per pair ke server Python
//   - Menerima sinyal terbaik untuk eksekusi
//   - Menggunakan TradeExecutor.mqh untuk entry
//==================================================================

#include <TradeExecutor.mqh>
#include <stdlib.mqh>
#include <Wininet.mqh>  // Untuk HTTP request

//==================================================================
// CONFIG
//==================================================================
string AI_SERVER_URL = "http://127.0.0.1:5000/filter_signals";
double AccountBalance = 1000; // Contoh, bisa ambil AccountInfoDouble(ACCOUNT_BALANCE)

//==================================================================
// Fungsi kirim data sinyal ke server AI
//==================================================================
string SendSignalsToAI(string symbol, double balance, string signals_json)
{
    char post[], result[];
    StringToCharArray(signals_json, post);
    int res = WebRequest(
        "POST",
        AI_SERVER_URL,
        "",
        5000,
        post,
        result
    );
    if(res>0)
    {
        string response;
        CharArrayToString(result,response);
        return response;
    }
    else
    {
        Print("WebRequest failed: ", GetLastError());
        return "";
    }
}

//==================================================================
// Fungsi contoh main
//==================================================================
void OnTick()
{
    // Contoh 10 sinyal per pair (dummy)
    string signals_json = "{ \"symbol\":\"EURUSD\", \"balance\":1000, \"signals\":["
                          "{\"signal\":\"BUY\",\"feature1\":0.5,\"feature2\":0.7},"
                          "{\"signal\":\"SELL\",\"feature1\":0.3,\"feature2\":0.1},"
                          "{\"signal\":\"BUY\",\"feature1\":0.6,\"feature2\":0.4},"
                          "{\"signal\":\"BUY\",\"feature1\":0.2,\"feature2\":0.9},"
                          "{\"signal\":\"SELL\",\"feature1\":0.7,\"feature2\":0.5},"
                          "{\"signal\":\"BUY\",\"feature1\":0.8,\"feature2\":0.2},"
                          "{\"signal\":\"SELL\",\"feature1\":0.4,\"feature2\":0.3},"
                          "{\"signal\":\"BUY\",\"feature1\":0.9,\"feature2\":0.8},"
                          "{\"signal\":\"SELL\",\"feature1\":0.1,\"feature2\":0.6},"
                          "{\"signal\":\"BUY\",\"feature1\":0.3,\"feature2\":0.7}"
                          "]}";

    // Kirim ke server AI
    string response = SendSignalsToAI("EURUSD", AccountBalance, signals_json);
    if(StringLen(response)==0) return;

    Print("Response from AI: ", response);

    // Parsing JSON sederhana
    // Contoh format: {"Signal":"BUY","Lot":0.05,"SL":1.2345,"TP":1.2370,"Probability":0.85,"IsStrong":1}
    string signal = GetJSONValue(response,"Signal");
    double lot    = StrToDouble(GetJSONValue(response,"Lot"));
    double sl     = StrToDouble(GetJSONValue(response,"SL"));
    double tp     = StrToDouble(GetJSONValue(response,"TP"));

    // Eksekusi trade
    if(signal=="BUY")
        OpenTrade(DIR_BUY, lot, sl, tp, "AI Filter BUY");
    else if(signal=="SELL")
        OpenTrade(DIR_SELL, lot, sl, tp, "AI Filter SELL");
}

//==================================================================
// Fungsi helper parsing JSON sederhana (key harus string dan value simple)
//==================================================================
string GetJSONValue(string json, string key)
{
    string pattern = "\"" + key + "\":";
    int pos = StringFind(json, pattern);
    if(pos<0) return "";
    int start = pos + StringLen(pattern);
    int end = StringFind(json,",",start);
    if(end<0) end = StringFind(json,"}",start);
    string val = StringSubstr(json,start,end-start);
    val = StringTrim(val);
    val = StringReplace(val,"\"","");
    return val;
}



Dokumentasi penggunaan:

Syarat:

Jalankan server Python ai_signal_filter_server.py.

Pastikan EA bisa melakukan WebRequest ke URL server (aktifkan domain di Tools → Options → Expert Advisors → Allow WebRequest for listed URL).

Alur:

EA mengumpulkan 10+ sinyal berbeda per pair (hasil deteksi indikator, candle pattern, news impact, dll).

EA membuat JSON berisi sinyal dan fitur relevan.

EA mengirim JSON ke server AI melalui WebRequest.

Server AI menggunakan model XGBoost / RF untuk menentukan satu sinyal terbaik.

Server mengembalikan Signal, Lot, SL, TP, Probability, IsStrong.

EA mengeksekusi trade menggunakan TradeExecutor.mqh.

Keuntungan:

AI memfilter sinyal yang paling layak entry.

Mengurangi entry yang lemah / tidak menguntungkan.

Memungkinkan integrasi multi-sinyal dari berbagai library deteksi.