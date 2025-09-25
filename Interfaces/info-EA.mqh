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
// Fungsi: SendTelegramMessage
// Deskripsi: Kirim pesan ke Telegram Bot via WebRequest
//==================================================================
void SendTelegramMessage(string text)
{
    string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
                              TelegramBotToken, TelegramChatID, text);
    char result[];
    int res = WebRequest("GET", url, "", NULL, 0, result, NULL);
    if(res<=0) Print("Telegram send failed: ", GetLastError());
}

//==================================================================
// Fungsi: UpdateSignal
// Deskripsi: Menambahkan atau memperbarui sinyal chart, alert, dan Telegram
//==================================================================
void UpdateSignal(SignalInfo sig, bool sendTelegram=true)
{
    color col=clrWhite;
    switch(sig.strength)
    {
        case WEAK:   col=clrYellow; break;
        case MEDIUM: col=clrOrange; break;
        case STRONG: col=clrGreen; break;
    }

    string txt=StringFormat("%s\nLot: %.2f\nSL: %.5f\nTP: %.5f",
                            (sig.signal==DIR_BUY?"BUY":(sig.signal==DIR_SELL?"SELL":"NONE")),
                            sig.lot,sig.sl,sig.tp);

    // Cari index sinyal di array
    int idx=-1;
    for(int i=0;i<SignalCount;i++)
        if(Signals[i].name==sig.name) { idx=i; break; }

    if(idx==-1) // Sinyal baru
    {
        ArrayResize(Signals,SignalCount+1);
        Signals[SignalCount]=sig;
        idx=SignalCount;
        SignalCount++;
    }
    else // update
        Signals[idx]=sig;

    // Hapus objek lama jika ada
    if(ObjectFind(0,sig.name)>=0)
        ObjectDelete(0,sig.name);

    // Buat label chart
    if(sig.signal!=DIR_NONE)
    {
        ObjectCreate(0,sig.name,OBJ_LABEL,0,0,0);
        ObjectSetInteger(0,sig.name,OBJPROP_XDISTANCE,20+idx*150);
        ObjectSetInteger(0,sig.name,OBJPROP_YDISTANCE,20);
        ObjectSetInteger(0,sig.name,OBJPROP_COLOR,col);
        ObjectSetInteger(0,sig.name,OBJPROP_FONTSIZE,12);
        ObjectSetString(0,sig.name,OBJPROP_TEXT,txt);

        // Alert pop-up
        Alert("Signal: ", txt);

        // Kirim Telegram
        if(sendTelegram) SendTelegramMessage(txt);
    }
}

//==================================================================
// Fungsi: ClearAllSignals
// Deskripsi: Hapus semua label chart dan reset array
//==================================================================
void ClearAllSignals()
{
    for(int i=0;i<SignalCount;i++)
        if(ObjectFind(0,Signals[i].name)>=0)
            ObjectDelete(0,Signals[i].name);
    ArrayFree(Signals);
    SignalCount=0;
}
