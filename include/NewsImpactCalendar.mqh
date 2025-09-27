//==================================================================
// NewsImpactCalendar.mqh (Extended dengan API)
//==================================================================

//==================================================================
// Contoh penggunaan
//==================================================================
// #include "NewsImpactCalendar.mqh"

// int OnInit()
// {
//    // Load otomatis dari API ForexFactory
//    LoadNewsFromAPI();

//    return(INIT_SUCCEEDED);
// }

// void OnTick()
// {
//    NISignal sig = DetectNewsImpactSignal();
//    PrintNewsImpactSignal(sig);

//    if(sig.isStrong) {
//       ExecuteNewsImpactScalp();
//    }
// }
//==================================================================

#pragma once
#include <stdlib.mqh>   // untuk parsing string
#include <stderror.mqh>

//--- enum & struct tetap sama
enum Dir { DIR_NONE=0, DIR_BUY=1, DIR_SELL=2 };

struct NewsEvent {
   datetime time;
   string   title;
   string   impact;   // low, medium, high
};

struct NISignal {
   Dir      signal;
   bool     isStrong;
   string   reason;
};

//--- array kalender news
NewsEvent newsCalendar[];
int       totalNews = 0;

//==================================================================
// Fungsi manual tambah news
//==================================================================
void AddNewsEvent(string dt, string title, string impact)
{
   NewsEvent ev;
   ev.time   = StringToTime(dt);
   ev.title  = title;
   ev.impact = StringToLower(impact);

   ArrayResize(newsCalendar, totalNews+1);
   newsCalendar[totalNews] = ev;
   totalNews++;
}

//==================================================================
// Fungsi ambil data news dari API ForexFactory (JSON sederhana)
//==================================================================
bool LoadNewsFromAPI(string url="https://nfs.faireconomy.media/ff_calendar_thisweek.json")
{
   ResetLastError();
   string headers;
   char   data[];
   int    res = WebRequest("GET", url, "", 5000, data, headers);

   if(res==-1) {
      Print("❌ WebRequest error: ", GetLastError());
      return false;
   }

   string raw = CharArrayToString(data,0,-1);

   // Parsing JSON sederhana → cari field penting
   int pos=0;
   while((pos=StringFind(raw,"\"title\":",pos))>0)
   {
      string title   = ExtractJsonValue(raw, pos, "title");
      string impact  = ExtractJsonValue(raw, pos, "impact");
      string dateStr = ExtractJsonValue(raw, pos, "date");

      datetime dt    = StringToTime(dateStr);
      if(dt>0 && title!="")
      {
         AddNewsEvent(TimeToString(dt, TIME_DATE|TIME_MINUTES), title, impact);
      }
      pos++;
   }

   Print("✅ News loaded from API. Total: ", totalNews);
   return true;
}

//==================================================================
// Helper: Ambil nilai dari JSON berdasarkan key
//==================================================================
string ExtractJsonValue(string &raw, int start, string key)
{
   string find="\""+key+"\":";
   int p = StringFind(raw, find, start);
   if(p<0) return "";

   p += StringLen(find);

   // cari pembatas
   int q1 = StringFind(raw,"\"",p);
   int q2 = StringFind(raw,"\"",q1+1);

   if(q1>=0 && q2>q1) {
      return StringSubstr(raw,q1+1,q2-q1-1);
   }
   return "";
}

//==================================================================
// Fungsi deteksi sinyal tetap sama
//==================================================================
NISignal DetectNewsImpactSignal()
{
   NISignal sig;
   sig.signal  = DIR_NONE;
   sig.isStrong= false;
   sig.reason  = "No signal";

   datetime now = TimeCurrent();

   for(int i=0;i<totalNews;i++)
   {
      if(MathAbs(newsCalendar[i].time - now) <= 300)
      {
         if(newsCalendar[i].impact=="high")
         {
            sig.isStrong = true;
            sig.signal   = (MathRand()%2==0 ? DIR_BUY : DIR_SELL);
            sig.reason   = "High impact news: " + newsCalendar[i].title;
         }
         else if(newsCalendar[i].impact=="medium")
         {
            sig.isStrong = false;
            sig.signal   = (MathRand()%2==0 ? DIR_BUY : DIR_SELL);
            sig.reason   = "Medium impact news: " + newsCalendar[i].title;
         }
         else
         {
            sig.reason   = "Low impact news: " + newsCalendar[i].title;
         }
      }
   }
   return sig;
}

//==================================================================
// Print sinyal ke log
//==================================================================
void PrintNewsImpactSignal(NISignal &sig)
{
   string dir="";
   if(sig.signal==DIR_BUY)  dir="BUY";
   if(sig.signal==DIR_SELL) dir="SELL";
   if(sig.signal==DIR_NONE) dir="NONE";

   PrintFormat("[NewsImpact] Signal=%s | Strong=%s | Reason=%s",
               dir, (sig.isStrong?"YES":"NO"), sig.reason);
}

//==================================================================
// Eksekusi scalping otomatis
//==================================================================
void ExecuteNewsImpactScalp(double lot=0.1, int slPips=15, int tpPips=30)
{
   NISignal sig = DetectNewsImpactSignal();
   if(sig.signal==DIR_NONE) return;

   double price = (sig.signal==DIR_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                       : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   double sl = 0, tp = 0;
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(sig.signal==DIR_BUY) {
      sl = price - slPips * pip;
      tp = price + tpPips * pip;
      OrderSend(_Symbol, OP_BUY, lot, price, 3, sl, tp, sig.reason, 0, 0, clrGreen);
   }
   if(sig.signal==DIR_SELL) {
      sl = price + slPips * pip;
      tp = price - tpPips * pip;
      OrderSend(_Symbol, OP_SELL, lot, price, 3, sl, tp, sig.reason, 0, 0, clrRed);
   }

   PrintNewsImpactSignal(sig);
}
