//==================================================================
// TrailingBreakCloseUltimate.mqh
// Versi: 4.0 Ultimate
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Modul ultimate untuk Trailing Stop & BreakClose + Multi-TF Confirmation
//==================================================================


/*
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA:
   #include "TrailingBreakCloseUltimate.mqh"

2. Set parameter input MT5:
   - BE_Pips, BE_Buffer
   - TrailLevel1/2/3, TrailDistance1/2/3
   - LevelsCount
   - ConfirmTF (TF konfirmasi trend)
   - UseTrendFilter

3. Panggil fungsi di OnTick():
   ManageTrailingBreakCloseUltimate();

4. Integrasi dengan TradeExecutor:
   - Buka posisi pakai OpenTrade()
   - Jalankan ManageTrailingBreakCloseUltimate() tiap tick

5. Fitur utama:
   - Trailing dinamis mengikuti harga
   - Multi-level trailing mengunci profit bertahap
   - BreakEven dinamis
   - Close otomatis jika SL ditembus
   - Filter trend multi-TF

TrailDistance1 = 10; // untuk level 1, SL mengikuti harga dengan jarak 10 pip
TrailDistance2 = 15; // level 2 → SL mengikuti harga dengan jarak 15 pip
TrailDistance3 = 25; // level 3 → SL mengikuti harga dengan jarak 25 pip
==================================================================*/


#pragma once

//===================== INPUT / VARIABEL ===========================
input double BE_Pips        = 10;  // profit minimal untuk BE
input double BE_Buffer      = 2;   // buffer setelah BE
input int LevelsCount       = 3;   // jumlah level trailing aktif
input double TrailLevel1    = 15;  // level profit pip 1
input double TrailDistance1 = 10;  // trailing pip 1
input double TrailLevel2    = 30;
input double TrailDistance2 = 15;
input double TrailLevel3    = 50;
input double TrailDistance3 = 25;
input ENUM_TIMEFRAMES ConfirmTF = PERIOD_M5; // TF konfirmasi arah trend
input bool UseTrendFilter   = true;

//===================== STRUCT PARAM ==============================
struct TrailingUltimateParams
{
    double bePips;
    double beBuffer;
    double trailLevels[5];
    double trailDistances[5];
    int levelsCount;
    ENUM_TIMEFRAMES tfConfirm;
    bool useTrendFilter;
};

//===================== FUNGSI TREND FILTER =======================
Dir GetTrendDirection(ENUM_TIMEFRAMES tf)
{
    double emaFast = iMA(_Symbol,tf,9,0,MODE_EMA,PRICE_CLOSE,0);
    double emaSlow = iMA(_Symbol,tf,21,0,MODE_EMA,PRICE_CLOSE,0);
    if(emaFast>emaSlow) return DIR_BUY;
    if(emaFast<emaSlow) return DIR_SELL;
    return DIR_NONE;
}

//===================== FUNGSI TRAILING & BREAK-CLOSE =============
void ManageTrailingBreakCloseUltimate()
{
    TrailingUltimateParams params;
    params.bePips = BE_Pips;
    params.beBuffer = BE_Buffer;
    params.trailLevels[0] = TrailLevel1; params.trailDistances[0] = TrailDistance1;
    params.trailLevels[1] = TrailLevel2; params.trailDistances[1] = TrailDistance2;
    params.trailLevels[2] = TrailLevel3; params.trailDistances[2] = TrailDistance3;
    params.levelsCount = LevelsCount;
    params.tfConfirm = ConfirmTF;
    params.useTrendFilter = UseTrendFilter;

    Dir trendDir = GetTrendDirection(params.tfConfirm);

    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        if(PositionSelectByIndex(i))
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double type  = PositionGetInteger(POSITION_TYPE);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl    = PositionGetDouble(POSITION_SL);
            double price = (type==POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                                     : SymbolInfoDouble(_Symbol,SYMBOL_ASK));
            double profitPips = (type==POSITION_TYPE_BUY ? price-entry : entry-price)/_Point;

            // Skip posisi jika TF konfirmasi bertentangan
            if(params.useTrendFilter)
            {
                if(type==POSITION_TYPE_BUY && trendDir==DIR_SELL) continue;
                if(type==POSITION_TYPE_SELL && trendDir==DIR_BUY) continue;
            }

            // --- BreakEven Dinamis ---
            if(profitPips >= params.bePips)
            {
                double newSL = entry + (type==POSITION_TYPE_BUY ? params.beBuffer*_Point : -params.beBuffer*_Point);
                if(type==POSITION_TYPE_BUY && newSL>sl) sl=newSL;
                if(type==POSITION_TYPE_SELL && newSL<sl) sl=newSL;
            }

            // --- Multi-Level Trailing ---
            for(int lvl=0; lvl<params.levelsCount; lvl++)
            {
                if(profitPips >= params.trailLevels[lvl])
                {
                    double newSL = (type==POSITION_TYPE_BUY ? price - params.trailDistances[lvl]*_Point
                                                             : price + params.trailDistances[lvl]*_Point);
                    if(type==POSITION_TYPE_BUY && newSL>sl) sl=newSL;
                    if(type==POSITION_TYPE_SELL && newSL<sl) sl=newSL;
                }
            }

            // --- Close jika menembus SL ---
            bool closeNow=false;
            if(type==POSITION_TYPE_BUY && price<=sl) closeNow=true;
            if(type==POSITION_TYPE_SELL && price>=sl) closeNow=true;

            MqlTradeRequest req;
            MqlTradeResult  res;
            ZeroMemory(req);
            ZeroMemory(res);

            if(closeNow)
            {
                req.action   = TRADE_ACTION_DEAL;
                req.position = ticket;
                req.symbol   = _Symbol;
                req.volume   = PositionGetDouble(POSITION_VOLUME);
                req.type     = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
                req.price    = price;
                req.deviation= 3;
                if(OrderSend(req,res))
                    PrintFormat("Position closed by Ultimate Trailing: Ticket %d",ticket);
                else
                    PrintFormat("Close failed: %d | %s",GetLastError(),res.comment);
            }
            else
            {
                // Update SL
                req.action   = TRADE_ACTION_SLTP;
                req.position = ticket;
                req.sl       = sl;
                if(!OrderSend(req,res))
                    PrintFormat("Update SL failed: %d | %s",GetLastError(),res.comment);
            }
        }
    }
}

