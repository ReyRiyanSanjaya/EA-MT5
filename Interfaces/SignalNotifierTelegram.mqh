//==================================================================
// SignalNotifierTelegram.mqh
// Versi: 1.0
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library interface notifikasi sinyal untuk EA / library MQL5
//   - Menampilkan label chart multi-signal
//   - Warna sesuai kekuatan sinyal (Weak/Medium/Strong)
//   - Pop-up alert MetaTrader
//   - Kirim otomatis ke Telegram Bot
//   - Auto-update setiap tick
//==================================================================

/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA atau modul:
      #include "SignalNotifierTelegram.mqh"

2. Konfigurasi Telegram:
      - Buat bot via BotFather di Telegram
      - Ambil BotToken (contoh: "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11")
      - Ambil ChatID (chat pribadi atau grup)
      - Set TelegramBotToken & TelegramChatID pada input parameter

3. Membuat dan menampilkan sinyal chart:
      SignalInfo sig;
      sig.name="HarmonicGartley";   // Nama unik sinyal
      sig.signal=DIR_BUY;           // DIR_BUY, DIR_SELL, DIR_NONE
      sig.strength=STRONG;          // WEAK, MEDIUM, STRONG
      sig.lot=0.01;                 // Lot sinyal
      sig.sl=1.2345;                // Stop Loss
      sig.tp=1.2380;                // Take Profit
      UpdateSignal(sig);            // Update chart + alert + Telegram

4. Menghapus semua sinyal:
      ClearAllSignals();

5. Auto-update sinyal:
      Panggil UpdateSignal() di OnTick() EA
      → label chart dan Telegram otomatis diperbarui

6. Notifikasi Telegram:
      - Set sendTelegram=true untuk mengirim ke Telegram
      - Bisa integrasi filter hanya untuk sinyal STRONG

7. Catatan:
      - Nama label harus unik per sinyal
      - Posisi label bisa diatur lewat OBJPROP_XDISTANCE / OBJPROP_YDISTANCE
      - Alert pop-up MetaTrader tetap muncul meskipun Telegram nonaktif
      - Telegram memerlukan izin WebRequest di MetaTrader

==================================================================
*/

#pragma once
#include <ChartObjects\ChartObjectsTxtControls.mqh>

//==================================================================
// ENUM untuk arah sinyal dan kekuatan
//==================================================================
enum Dir { DIR_NONE, DIR_BUY, DIR_SELL };
enum SignalStrength { WEAK, MEDIUM, STRONG };

//==================================================================
// Struct informasi sinyal
//==================================================================
struct SignalInfo
{
    string name;              // Nama unik sinyal
    Dir signal;               // DIR_BUY, DIR_SELL, DIR_NONE
    SignalStrength strength;  // WEAK, MEDIUM, STRONG
    double lot;               // Lot trading
    double sl;                // Stop Loss
    double tp;                // Take Profit
};

//==================================================================
// Konfigurasi Telegram (input bisa diubah di EA)
//==================================================================
input string TelegramBotToken = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11";
input string TelegramChatID  = "987654321";

//==================================================================
// Array global untuk menyimpan sinyal aktif
//==================================================================
SignalInfo Signals[];
int SignalCount=0;

//==================================================================
// Fungsi: SendTelegramPhoto
// Deskripsi: Kirim screenshot chart ke Telegram
//==================================================================
void SendTelegramPhoto(string filePath, string caption="")
{
    string url = StringFormat("https://api.telegram.org/bot%s/sendPhoto?chat_id=%s", 
                              TelegramBotToken, TelegramChatID);
    
    // Telegram API versi sederhana: kirim file dari folder MQL5/Files
    // File harus ada di terminal path /MQL5/Files/
    string fileName = StringSubstr(filePath, StringFind(filePath,"/Files/")+7);
    string fullUrl = url+"&caption="+caption+"&photo=@"+fileName;
    
    char result[];
    int res = WebRequest("GET", fullUrl, "", NULL, 0, result, NULL);
    if(res<=0) Print("Telegram photo send failed: ", GetLastError());
}

//==================================================================
// Fungsi: UpdateSignalsVoting_CombinedScreenshot_Rapih
// Deskripsi: Update semua sinyal, kirim full report + 1 screenshot gabungan STRONG
// Posisi label STRONG diatur rapi agar screenshot jelas
//==================================================================
void UpdateSignalsVoting_CombinedScreenshot_Rapih(bool sendTelegram=true)
{
    if(SignalCount==0) return;

    // Hitung voting BUY / SELL
    int countBuy=0, countSell=0;
    for(int i=0;i<SignalCount;i++)
    {
        if(Signals[i].signal==DIR_BUY) countBuy++;
        else if(Signals[i].signal==DIR_SELL) countSell++;
    }
    Dir votedSignal = (countBuy >= countSell ? DIR_BUY : DIR_SELL);
    string voteText = (votedSignal==DIR_BUY ? "🚀 BUY" : (votedSignal==DIR_SELL ? "🔻 SELL" : "⏹️ NONE"));

    // Siapkan pesan Telegram
    string txt = "*📊 Signal Full Report (Voting Result: "+voteText+")*\n\n";

    // Array untuk label STRONG
    string strongLabels[]; int strongCount=0;

    // Posisi label STRONG di chart
    int xBase = 20;
    int yBase = 20;
    int xStep = 200; // jarak horizontal antar label
    int yStep = 50;  // jarak vertikal antar label jika lebih dari 5 STRONG

    int row=0, col=0;

    for(int i=0;i<SignalCount;i++)
    {
        SignalInfo sig = Signals[i];

        // Emoji hanya untuk Signal & Strength
        string signalEmoji = (sig.signal==DIR_BUY ? "🚀 BUY" : (sig.signal==DIR_SELL ? "🔻 SELL" : "⏹️ NONE"));
        string strengthEmoji = (sig.strength==STRONG ? "🟢 Strong" : (sig.strength==MEDIUM ? "🟠 Medium" : "⚪ Weak"));
        string votedTag = (sig.signal==votedSignal ? " [VOTED]" : "");

        // Tambahkan ke pesan Telegram
        txt += StringFormat("%d️⃣ Name: %s\nSignal: %s%s\nStrength: %s\nLot: %.2f\nSL: %.5f\nTP: %.5f\n\n",
                            i+1, sig.name, signalEmoji, votedTag, strengthEmoji, sig.lot, sig.sl, sig.tp);

        // Tentukan warna label
        color colColor = clrWhite;
        switch(sig.strength) { case WEAK: colColor=clrYellow; break; case MEDIUM: colColor=clrOrange; break; case STRONG: colColor=clrGreen; break; }

        // Hapus label lama jika ada
        if(ObjectFind(0,sig.name)>=0) ObjectDelete(0,sig.name);

        // Buat label chart
        if(sig.signal!=DIR_NONE)
        {
            ObjectCreate(0,sig.name,OBJ_LABEL,0,0,0);
            int xPos=xBase + col*xStep;
            int yPos=yBase + row*yStep;
            ObjectSetInteger(0,sig.name,OBJPROP_XDISTANCE,xPos);
            ObjectSetInteger(0,sig.name,OBJPROP_YDISTANCE,yPos);
            ObjectSetInteger(0,sig.name,OBJPROP_COLOR,colColor);
            ObjectSetInteger(0,sig.name,OBJPROP_FONTSIZE,12);
            ObjectSetString(0,sig.name,OBJPROP_TEXT,StringFormat("%s %.2f Lot", (sig.signal==DIR_BUY?"BUY":"SELL"), sig.lot));

            // Hanya simpan STRONG untuk screenshot gabungan
            if(sig.strength==STRONG)
            {
                ArrayResize(strongLabels,strongCount+1);
                strongLabels[strongCount] = sig.name;
                strongCount++;

                // Atur posisi rapi: max 5 label per baris
                col++;
                if(col>=5) { col=0; row++; }
            }
        }
    }

    // Kirim screenshot gabungan STRONG jika ada
    if(strongCount>0)
    {
        string screenshotPath = "MQL5/Files/StrongSignalsCombined.png";
        ChartScreenShot(0, screenshotPath, 1024, 768);
        SendTelegramPhoto(screenshotPath, "📊 Strong Signals Combined Chart");
    }

    // Kirim Telegram full report
    if(sendTelegram) SendTelegramMessage(txt);

    // Alert pop-up
    Alert("Signal Voting Report with combined STRONG screenshot sent to Telegram.");
}
