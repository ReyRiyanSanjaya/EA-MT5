//==================================================================
// TradeExecutor.mqh (Versi 2.0 - Integrasi RiskManager)
// Author: Rey Riyan Sanjaya
// Deskripsi:
//   Library eksekusi trading untuk MT5 dengan manajemen risiko terintegrasi
//   - Buy / Sell / Close
//   - Lot dihitung otomatis berdasarkan risiko account (RiskManager.mqh)
//   - SL / TP otomatis sesuai stopLossPips dan Risk/Reward Ratio
//   - Trailing Stop
//   - Cocok untuk scalping, swing, dan strategi news trading
//
// ====================== PANDUAN PENGGUNAAN =======================
//
// 1. Include library di EA:
//      #include "RiskManager.mqh"
//      #include "TradeExecutor.mqh"
//
// 2. Membuka posisi dengan manajemen risiko:
//      double entryPrice = Ask;       // atau Bid untuk sell
//      double stopLossPips = 20;      // jarak SL dalam pip
//      double rrRatio = 2.0;          // Risk/Reward Ratio
//      double riskPercent = 1.0;      // risiko % dari balance
//
//      // Hitung lot, SL, TP otomatis
//      NISignalRisk risk = ApplyRiskManagement(DIR_BUY, entryPrice, stopLossPips, rrRatio, riskPercent);
//
//      // Eksekusi order
//      OpenTrade(DIR_BUY, risk.lot, risk.sl, risk.tp, "Scalping");
//
// 3. Menutup posisi:
//      CloseTrade(ticket);
//
// 4. Trailing Stop:
//      TrailingStop(15); // trailing stop 15 pips
//
// 5. Integrasi dengan library sinyal (contoh NewsImpact):
//      NISignal sig = DetectNewsImpactSignal();
//      if(sig.signal==DIR_BUY)
//      {
//          NISignalRisk risk = ApplyRiskManagement(DIR_BUY, sig.entryPrice, 20, 2, 1.0);
//          OpenTrade(DIR_BUY, risk.lot, risk.sl, risk.tp, "News Scalping");
//      }
//
//==================================================================

#pragma once
#include "RiskManager.mqh"   // pastikan RiskManager.mqh sudah ada

enum Dir
{
    DIR_NONE,
    DIR_BUY,
    DIR_SELL
};

//==================================================================
// Fungsi: OpenTrade
// Deskripsi: Membuka order Buy / Sell
// Parameter:
//   dir     = DIR_BUY / DIR_SELL
//   lot     = ukuran lot
//   sl      = stop loss
//   tp      = take profit
//   comment = komentar order
//==================================================================
bool OpenTrade(Dir dir,double lot,double sl,double tp,string comment="")
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action   = TRADE_ACTION_DEAL;
    request.symbol   = _Symbol;
    request.volume   = lot;
    request.sl       = sl;
    request.tp       = tp;
    request.deviation= 3;
    request.type     = (dir==DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
    request.type_filling = ORDER_FILLING_FOK;
    request.comment  = comment;

    if(!OrderSend(request,result))
    {
        PrintFormat("OpenTrade failed: %d | %s",GetLastError(),result.comment);
        return false;
    }
    else
    {
        PrintFormat("Trade executed: %s | Lot: %.2f | SL: %.5f | TP: %.5f",
                    (dir==DIR_BUY?"BUY":"SELL"),lot,sl,tp);
        return true;
    }
}

//==================================================================
// Fungsi: CloseTrade
// Deskripsi: Menutup posisi aktif
// Parameter:
//   ticket = nomor ticket posisi
//==================================================================
bool CloseTrade(ulong ticket)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    double price=0;
    ENUM_ORDER_TYPE type;

    if(!HistorySelectByTicket(ticket))
    {
        Print("CloseTrade failed: Ticket not found");
        return false;
    }

    if(!PositionSelectByTicket(ticket))
    {
        Print("CloseTrade failed: Position not found");
        return false;
    }

    type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
    price = (type==ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK));

    request.action   = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol   = _Symbol;
    request.volume   = PositionGetDouble(POSITION_VOLUME);
    request.type     = (type==ORDER_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
    request.price    = price;
    request.deviation= 3;

    if(!OrderSend(request,result))
    {
        PrintFormat("CloseTrade failed: %d | %s",GetLastError(),result.comment);
        return false;
    }
    else
    {
        PrintFormat("Trade closed: Ticket %d",ticket);
        return true;
    }
}

//==================================================================
// Fungsi: TrailingStop
// Deskripsi: Mengatur trailing stop untuk posisi terbuka
// Parameter:
//   trailPips = jarak trailing dalam pips
//==================================================================
void TrailingStop(double trailPips)
{
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        if(PositionSelectByIndex(i))
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double type  = PositionGetInteger(POSITION_TYPE);
            double sl    = PositionGetDouble(POSITION_SL);
            double price = (type==POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK));
            double newSL = 0;

            if(type==POSITION_TYPE_BUY)
            {
                newSL = price - trailPips*_Point;
                if(newSL>sl) sl=newSL;
            }
            else
            {
                newSL = price + trailPips*_Point;
                if(newSL<sl) sl=newSL;
            }

            MqlTradeRequest request;
            MqlTradeResult  result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action   = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl       = sl;

            OrderSend(request,result);
        }
    }
}
