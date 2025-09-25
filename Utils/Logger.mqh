//==================================================================
// Logger.mqh
// Versi: 1.0
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library logging untuk EA / Library MQL5
//   - Mencatat log ke Journal dan / atau file
//   - Level log: INFO, WARN, ERROR
//   - Format timestamp
//==================================================================

#pragma once

enum LogLevel
{
    LOG_INFO,
    LOG_WARN,
    LOG_ERROR
};

// Path default log file (di folder MQL5/Files)
input string LogFileName = "EA_Log.txt";

//==================================================================
// Fungsi: WriteLog
// Deskripsi: Menulis log dengan level dan timestamp
// Parameter:
//   level = LOG_INFO / LOG_WARN / LOG_ERROR
//   message = string pesan log
//==================================================================
void WriteLog(LogLevel level, string message)
{
    string levelStr="";
    switch(level)
    {
        case LOG_INFO:  levelStr="INFO";  break;
        case LOG_WARN:  levelStr="WARN";  break;
        case LOG_ERROR: levelStr="ERROR"; break;
    }

    string logLine = StringFormat("[%s] [%s] %s", TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS), levelStr, message);

    // Print ke Journal
    Print(logLine);

    // Append ke file
    int fileHandle = FileOpen(LogFileName, FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON);
    if(fileHandle != INVALID_HANDLE)
    {
        FileSeek(fileHandle,0,SEEK_END);
        FileWrite(fileHandle, logLine);
        FileClose(fileHandle);
    }
}

//==================================================================
// Fungsi: LogInfo / LogWarn / LogError
// Deskripsi: Shortcut untuk menulis log sesuai level
//==================================================================
void LogInfo(string msg)  { WriteLog(LOG_INFO, msg);  }
void LogWarn(string msg)  { WriteLog(LOG_WARN, msg);  }
void LogError(string msg) { WriteLog(LOG_ERROR,msg); }

//==================================================================
// PANDUAN PENGGUNAAN
/*
1. Include library di EA atau modul:
      #include "Logger.mqh"

2. Menulis log:
      LogInfo("EA started");
      LogWarn("Slippage tinggi");
      LogError("Order gagal");

3. Log otomatis bisa dipanggil di semua library:
      WriteLog(LOG_INFO, "Sinyal deteksi momentum: BUY");

4. Semua log dicatat di:
      - Journal MetaTrader
      - File MQL5/Files/EA_Log.txt (sesuai LogFileName)
==================================================================
*/
