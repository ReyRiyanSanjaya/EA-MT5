//==================================================================
// Logger.mqh
// Utility logging & notifikasi (Journal + Alert + Telegram + Chart)
//==================================================================
//==================================================================
// Logger.mqh (diperbarui untuk screenshot chart otomatis)
//==================================================================
#pragma once
#include "SignalNotifierTelegram.mqh"

namespace Logger
{
   enum LogLevel { INFO, SUCCESS, WARNING, ERROR };

   // --- format prefix level ---
   string LevelToStr(LogLevel level)
   {
      switch(level)
      {
         case INFO:    return "[INFO]    ";
         case SUCCESS: return "[SUCCESS] ";
         case WARNING: return "[WARNING] ";
         case ERROR:   return "[ERROR]   ";
      }
      return "[INFO]   ";
   }

   // --- fungsi utama log ---
   void Log(string module, string message, LogLevel level=INFO, bool notify=false)
   {
      string logMsg = StringFormat("[%s] %s %s | %s",
                                   TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                                   LevelToStr(level),
                                   module,
                                   message);

      // Journal
      Print(logMsg);

      // Pop-up
      if(level==ERROR || level==WARNING) Alert("⚠️ ", logMsg);

      // Telegram
      if(notify) SendTelegramMessage("📝 *LOG ["+module+"]*\n"+message);
   }

   // --- log sinyal trading (diperbarui otomatis screenshot) ---
   void LogSignals(string symbol, string direction, double confidence,
                   string &sources[], int sourcesCount, bool notify=true)
   {
      string srcList="";
      for(int i=0; i<sourcesCount; i++)
      {
         srcList += sources[i];
         if(i<sourcesCount-1) srcList += ", ";
      }

      string msg = StringFormat("Detected %d signal(s) [%s] | Confidence=%.2f | Sources={%s}",
                                sourcesCount, direction, confidence, srcList);

      Log("SignalEngine", msg, INFO, notify);

      // --- buat dan update signal chart + Telegram otomatis ---
      SignalInfo sig;
      sig.name = "Signal_"+symbol+"_"+TimeToString(TimeCurrent(),TIME_SECONDS);
      sig.signal = (direction=="BUY"?DIR_BUY:(direction=="SELL"?DIR_SELL:DIR_NONE));
      sig.strength = (confidence>=0.75?STRONG:(confidence>=0.5?MEDIUM:WEAK));
      sig.lot = 0; sig.sl = 0; sig.tp = 0;

      // Panggil UpdateSignal versi baru (otomatis screenshot STRONG)
      UpdateSignal(sig, notify);
   }

   // --- log trade execution ---
   void LogTrade(string symbol, string direction, double lot, double price,
                 double sl, double tp, bool success, string reason="", bool notify=true)
   {
      string msg = StringFormat("%s %s on %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f",
                                (success ? "EXECUTED" : "FAILED"),
                                direction, symbol, lot, price, sl, tp);

      if(reason!="") msg += " | Reason: "+reason;
      Log("TradeExecutor", msg, (success?SUCCESS:ERROR), notify);

      // --- buat label chart & Telegram detail ---
      if(success)
      {
         SignalInfo sig;
         sig.name="Trade_"+symbol+"_"+TimeToString(TimeCurrent(),TIME_SECONDS);
         sig.signal=(direction=="BUY"?DIR_BUY:(direction=="SELL"?DIR_SELL:DIR_NONE));
         sig.strength=STRONG;
         sig.lot=lot; sig.sl=sl; sig.tp=tp;

         // Panggil UpdateSignal versi baru
         UpdateSignal(sig, notify);
      }
   }

   // --- log alasan entry ---
   void LogEntryReason(string symbol, string direction, string pattern, string rationale, bool notify=true)
   {
      string msg = StringFormat("Entry rationale on %s [%s] | Pattern: %s | Detail: %s",
                                symbol,direction,pattern,rationale);

      Log("EntryReason", msg, SUCCESS, notify);

      if(notify)
      {
         string tg=StringFormat("📊 *ENTRY RATIONALE*\n"
                                "📈 Symbol: %s\n"
                                "➡️ Direction: %s\n"
                                "📐 Pattern: %s\n"
                                "📝 Reason: %s\n"
                                "🕒 Time: %s",
                                symbol,direction,pattern,rationale,
                                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
         SendTelegramMessage(tg);
      }
   }
}
