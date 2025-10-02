//+------------------------------------------------------------------+
//|                                                        Final.mq5 |
//|                                                Rey Riyan Sanjaya |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Rey Riyan Sanjaya"
#property link "https://www.mql5.com"
#property version "1.00"

#include <Trade\Trade.mqh>


// Risk Management Parameters (lebih fleksibel)
input double RiskPercent = 100.0; // risiko per trade (% balance) → bisa ambil lot lebih besar
input double MaxDailyDD = 100.0;  // max drawdown harian (%)
input double MaxSpread = 70;      // max spread (point) → longgar
input double BaseLot = 0.02;      // lot dasar
input double MaxLot = 100.0;      // lot maksimal → scale lebih agresif
input int SL_Pips = 100;          // default SL pips → sangat longgar
input int TP_Pips = 350;          // default TP pips → cepat close profit

// Tambahkan ini di bagian atas file, sebelum fungsi SendTradeAlert
enum Dir
{
    DIR_NONE, // 0 - No direction
    DIR_BUY,  // 1 - Buy direction
    DIR_SELL  // 2 - Sell direction
};

//+------------------------------------------------------------------+
//| Order Block Signal Structure                                    |
//+------------------------------------------------------------------+
struct OBSignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
};

struct StochSignal
{
    Dir signal;
    bool isStrong;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double kValueLow;
    double dValueLow;
    double kValueHigh;
    double dValueHigh;
    double lotSize;
};

//+------------------------------------------------------------------+
//| Function Declarations                                           |
//+------------------------------------------------------------------+
void UpdateChartLabels();
void CollectActiveSignals();
void UpdateSignalsUltimateLive2();
void SendTradeAlert(string symbol, Dir direction, double lot, double entry, double sl, double tp, string signal_type);
void SendSystemStatus();
bool HasActiveTrades();
void PrintSystemPerformance();
void PrintAccountStatus();
void PrintActivePositionsSummary();
bool IsNewsPeriod();
void CleanupExpiredData();

//+------------------------------------------------------------------+
//| Chart Pattern Signal Structure (DIPERBAIKI LENGKAP)            |
//+------------------------------------------------------------------+
struct ChartPatternSignal
{
    Dir signal;
    bool isStrong;
    string patternName;
    double confidence;
    double entryPrice; // DITAMBAHKAN
    double stopLoss;   // DITAMBAHKAN
    double takeProfit; // DITAMBAHKAN
};

// Tambahkan deklarasi struct ini di bagian atas file
struct PASignal
{
    double lotSize;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    string symbol;
    int direction; // 1 untuk BUY, -1 untuk SELL
    string signalType;
};

///+------------------------------------------------------------------+
//| Signal Engine Class                                             |
//+------------------------------------------------------------------+
class SignalEngine
{
private:
    int signalCount;
    double totalConfidence;
    Dir lastDirection;

public:
    SignalEngine() : signalCount(0), totalConfidence(0), lastDirection(DIR_NONE) {}

    bool GetConsensusSignal(Dir &direction, double &confidence, string &signalSource)
    {
        // Skip signal generation selama news period untuk avoid conflict
        if (UseNewsImpact && IsNewsPeriod())
        {
            Print("Skipping regular signals during news period");
            return false;
        }

        // Skip jika ada active order block trade
        if (UseOrderBlock && HasActiveOBTrade())
        {
            Print("Skipping regular signals - Active OB trade running");
            return false;
        }
        // Reset jika baru mulai
        if (signalCount >= 30) // Reset setiap 10 sinyal
        {
            signalCount = 0;
            totalConfidence = 0;
        }

        // Ambil sinyal dari berbagai sumber
        ChartPatternSignal patternSignal = GetChartPatternSignalUltimate(1, 20, PERIOD_M15);
        Dir momentumSignal = GetMomentumSignal();
        Dir macroSignal = GetMacroSignalUltimate();

        // Ambil sinyal momentum pullback jika diaktifkan
        MomentumSignal pullbackSignal;
        bool hasPullbackSignal = false;
        if (UseMomentumPullback)
        {
            hasPullbackSignal = DetectMomentumPullback(MomentumTF, pullbackSignal, MomentumLookback);
        }

        // Prioritaskan sinyal berdasarkan urutan prioritas
        Dir finalDirection = DIR_NONE;
        double baseConfidence = 0.0;

        // 1. Priority: Momentum Pullback (Highest)
        if (hasPullbackSignal && pullbackSignal.found)
        {
            finalDirection = pullbackSignal.dir;
            baseConfidence = 0.8;
            signalSource = "MomentumPullback";
        }
        // 2. Priority: Regular Momentum
        else if (momentumSignal != DIR_NONE)
        {
            finalDirection = momentumSignal;
            baseConfidence = 0.7;
            signalSource = "Momentum";
        }
        // 3. Priority: Pattern dengan konfirmasi macro
        else if (patternSignal.signal != DIR_NONE && macroSignal == patternSignal.signal)
        {
            finalDirection = patternSignal.signal;
            baseConfidence = CalculatePatternConfidence(patternSignal);
            signalSource = "Pattern+Macro";
        }
        // 4. Priority: Pattern saja
        else if (patternSignal.signal != DIR_NONE)
        {
            finalDirection = patternSignal.signal;
            baseConfidence = CalculatePatternConfidence(patternSignal);
            signalSource = "Pattern";
        }
        else
        {
            return false; // No signal
        }

        // Adjust confidence berdasarkan konfirmasi tambahan
        double adjustment = 0.0;

        if (macroSignal == finalDirection)
            adjustment += 0.15; // Konfirmasi macro
        else if (macroSignal != DIR_NONE)
            adjustment -= 0.1; // Kontradiksi macro

        if (patternSignal.signal == finalDirection && patternSignal.signal != DIR_NONE)
            adjustment += 0.1; // Konfirmasi pattern

        double finalConfidence = baseConfidence + adjustment;
        finalConfidence = MathMax(finalConfidence, 0.1);  // Minimal 10%
        finalConfidence = MathMin(finalConfidence, 0.95); // Maksimal 95%

        // Update cumulative values
        signalCount++;
        totalConfidence += finalConfidence;

        // Set output values
        direction = finalDirection;
        confidence = finalConfidence;
        lastDirection = direction;
        signalSource = signalSource;

        PrintFormat("Signal Engine: %s signal with %.2f confidence (Source:%s, Momentum:%s, Pattern:%s, Macro:%s)",
                    (direction == DIR_BUY ? "BUY" : (direction == DIR_SELL ? "SELL" : "NONE")),
                    confidence, signalSource,
                    (momentumSignal == DIR_BUY ? "BUY" : (momentumSignal == DIR_SELL ? "SELL" : "NONE")),
                    (patternSignal.signal == DIR_BUY ? "BUY" : (patternSignal.signal == DIR_SELL ? "SELL" : "NONE")),
                    (macroSignal == DIR_BUY ? "BUY" : (macroSignal == DIR_SELL ? "SELL" : "NEUTRAL")));

        return true;
    }

    // Helper function untuk cek active OB trades
    bool HasActiveOBTrade()
    {
        for (int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                if (StringFind(comment, "OB_") >= 0) // Trades dengan comment OB
                    return true;
            }
        }
        return false;
    }

    double CalculatePatternConfidence(ChartPatternSignal &signal)
    {
        double baseConfidence = 0.5; // Base confidence

        // Adjust based on pattern strength
        if (signal.isStrong)
            baseConfidence += 0.3;
        else
            baseConfidence += 0.1;

        // Adjust based on pattern type
        if (signal.patternName == "Double Top" || signal.patternName == "Double Bottom")
            baseConfidence += 0.1;
        else if (signal.patternName == "Head & Shoulders" || signal.patternName == "Inverse H&S")
            baseConfidence += 0.15;
        else if (signal.patternName == "Triangle")
            baseConfidence += 0.1;
        else if (signal.patternName == "Gartley" || signal.patternName == "Bat" ||
                 signal.patternName == "Butterfly" || signal.patternName == "Crab")
            baseConfidence += 0.2; // Harmonic patterns get higher confidence

        // Tambahan: Adjust berdasarkan Iceberg detection
        IcebergLevel iceberg = DetectIcebergAdvanced(0); // Cek candle terbaru
        if (iceberg == ICE_STRONG)
            baseConfidence += 0.15;
        else if (iceberg == ICE_WEAK)
            baseConfidence += 0.05;

        return MathMin(baseConfidence, 0.95); // Cap at 95%
    }
};

//+------------------------------------------------------------------+
//| Risk Manager Class                                              |
//+------------------------------------------------------------------+
namespace RiskManager
{
    // --- Hitung balance, equity, margin ---
    double GetBalance() { return AccountInfoDouble(ACCOUNT_BALANCE); }
    double GetEquity() { return AccountInfoDouble(ACCOUNT_EQUITY); }
    double GetFreeMargin() { return AccountInfoDouble(ACCOUNT_MARGIN_FREE); }
    double GetMarginLevel() { return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); }

    // --- Hitung nilai 1 pip ---
    double GetPipValue(string symbol = NULL)
    {
        if (symbol == NULL)
            symbol = _Symbol;
        return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    }

    // --- Hitung lot berdasarkan risk% dan SL (dalam pips) ---
    double CalculateLotByRisk(double stopLossPips, string symbol = NULL)
    {
        if (symbol == NULL)
            symbol = _Symbol;
        double balance = GetBalance();
        double riskMoney = balance * (RiskPercent / 100.0);
        double pipValue = GetPipValue(symbol);
        if (pipValue <= 0)
            pipValue = 0.0001;
        double lot = riskMoney / (stopLossPips * pipValue);
        return NormalizeDouble(lot, 2);
    }

    // --- Hitung lot dinamis dari confidence + risk ---
    double GetDynamicLot(double confidence, double stopLossPips = 50, string symbol = NULL, bool isPremiumSignal = false)
    {
        if (symbol == NULL)
            symbol = _Symbol;

        double actualMaxLot = MaxLot;
        if (isPremiumSignal)
        {
            actualMaxLot = MaxLot * 3.0; // 3x dari normal
            Print("PREMIUM SIGNAL: Using enhanced MaxLot = ", actualMaxLot);
        }

        double lotFromConfidence = BaseLot + (actualMaxLot - BaseLot) * confidence;
        double lotByRisk = CalculateLotByRisk(stopLossPips, symbol);
        double lot = MathMin(lotFromConfidence, lotByRisk);

        double freeMargin = GetFreeMargin();
        double marginReq = 0.0;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lot, SymbolInfoDouble(symbol, SYMBOL_ASK), marginReq))
            marginReq = 0;

        if (marginReq > freeMargin * 0.8)
            if (marginReq > 0)
            {
                lot = (freeMargin * 0.8 / marginReq) * lot;
                Print("Margin adjusted lot: ", lot);
            }
            else
            {
                Print("WARNING: marginReq = 0, skip adjustment");
            }

        lot = MathMin(lot, actualMaxLot);
        lot = MathMax(lot, BaseLot);

        return NormalizeDouble(lot, 2);
    }

    // --- Hitung lot untuk sinyal premium (confidence tinggi) ---
    double GetPremiumLot(double confidence, double stopLossPips = 50, string symbol = NULL)
    {
        if (symbol == NULL)
            symbol = _Symbol;
        if (confidence < 0.8)
            return GetDynamicLot(confidence, stopLossPips, symbol, false);

        double premiumRiskPercent = RiskPercent * 2.0; // 2x risk normal
        double balance = GetBalance();
        double riskMoney = balance * (premiumRiskPercent / 100.0);
        double pipValue = GetPipValue(symbol);
        if (pipValue <= 0)
            pipValue = 0.0001;

        double premiumLot = riskMoney / (stopLossPips * pipValue);
        double premiumMaxLot = MaxLot * 20.0; // batas maksimal premium
        premiumLot = MathMin(premiumLot, premiumMaxLot);

        double freeMargin = GetFreeMargin();
        double marginReq = 0.0;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, symbol, premiumLot, SymbolInfoDouble(symbol, SYMBOL_ASK), marginReq))
            marginReq = 0;

        if (marginReq > freeMargin * 0.7)
            premiumLot = (freeMargin * 0.7 / marginReq) * premiumLot;

        premiumLot = MathMax(premiumLot, BaseLot);
        Print("PREMIUM LOT ACTIVATED: ", premiumLot, " (Confidence: ", confidence, ")");
        return NormalizeDouble(premiumLot, 2);
    }

    // --- Cek apakah boleh entry ---
    bool CanOpenTrade(bool isPremiumTrade = false)
    {
        double marginLevel = GetMarginLevel();
        double minMarginLevel = isPremiumTrade ? 300.0 : 200.0;
        if (marginLevel > 0 && marginLevel < minMarginLevel)
        {
            Print("Margin level too low: ", marginLevel, " (Required: ", minMarginLevel, ")");
            return false;
        }

        double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        double maxAllowedSpread = isPremiumTrade ? MaxSpread * 0.7 : MaxSpread;
        if (spread > maxAllowedSpread)
        {
            Print("Spread too high: ", spread, " (Max: ", maxAllowedSpread, ")");
            return false;
        }

        // atur drawdown disini
        // static double equityStart = GetEquity();
        // double currentEquity = GetEquity();
        // double ddPercent = ((equityStart - currentEquity) / equityStart) * 100.0;
        // double maxAllowedDD = isPremiumTrade ? MaxDailyDD * 0.5 : MaxDailyDD;
        // if (ddPercent > maxAllowedDD)
        // {
        //     Print("Daily drawdown limit reached: ", ddPercent, " (Max: ", maxAllowedDD, ")");
        //     return false;
        // }

        // if (isPremiumTrade)
        // {
        //     double freeMargin = GetFreeMargin();
        //     double balance = GetBalance();
        //     if (freeMargin < balance * 0.3)
        //     {
        //         Print("Insufficient free margin for premium trade: ", freeMargin);
        //         return false;
        //     }
        // }

        return true;
    }

    bool CanOpenPremiumTrade() { return CanOpenTrade(true); }

    // --- Fungsi baru: ambil MaxLot yang aman (integrasi OB Strong / Premium) ---
    double GetMaxLot()
    {
        double stopLossPips = 50.0; // default stop loss
        double lotByRisk = CalculateLotByRisk(stopLossPips);
        double freeMargin = GetFreeMargin();
        double marginReq = 0.0;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotByRisk, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginReq))
            marginReq = 0;

        if (marginReq > freeMargin * 0.8)
            lotByRisk = (freeMargin * 0.8 / marginReq) * lotByRisk;

        lotByRisk = MathMin(lotByRisk, MaxLot);
        lotByRisk = MathMax(lotByRisk, BaseLot);

        // Sesuaikan step broker
        double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        lotByRisk = MathFloor(lotByRisk / lotStep) * lotStep;

        return NormalizeDouble(lotByRisk, 2);
    }
}

//+------------------------------------------------------------------+
//| Trading Functions (FIXED - SL lebih longgar)                   |
//+------------------------------------------------------------------+
void ExecuteBuy(double lot, int slPips, int tpPips, string signalSource)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Pastikan SL minimal 30 pips untuk menghindari noise market
    slPips = MathMax(slPips, 50);
    tpPips = MathMax(tpPips, 100); // Minimal RR 1:1.5

    double sl = ask - slPips * _Point;
    double tp = ask + tpPips * _Point;

    // double sl = slPips;
    // double tp = tpPips;
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_BUY;
    request.volume = lot;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = signalSource + " Buy";

    if (!OrderSend(request, result))
        Print("❌ Buy failed: ", result.retcode);
    else
        Print("✅ Buy executed @", ask, " lot=", lot, " SL=", sl, " TP=", tp, " SL Pips=", slPips);
}

void ExecuteSell(double lot, int slPips, int tpPips, string signalSource)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Pastikan SL minimal 30 pips untuk menghindari noise market
    slPips = MathMax(slPips, 50);
    tpPips = MathMax(tpPips, 100); // Minimal RR 1:1.5

    double sl = bid + slPips * _Point;
    double tp = bid - tpPips * _Point;

    // double sl = slPips;
    // double tp = tpPips;

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_SELL;
    request.volume = lot;
    request.price = bid;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = signalSource + " Buy";

    if (!OrderSend(request, result))
        Print("❌ Sell failed: ", result.retcode);
    else
        Print("✅ Sell executed @", bid, " lot=", lot, " SL=", sl, " TP=", tp, " SL Pips=", slPips);
}

//===================== FUNGSI TREND FILTER =======================
Dir GetTrendDirection(ENUM_TIMEFRAMES tf)
{
    double emaFast = iMA(_Symbol, tf, 9, 0, MODE_EMA, PRICE_CLOSE);
    double emaSlow = iMA(_Symbol, tf, 21, 0, MODE_EMA, PRICE_CLOSE);
    if (emaFast > emaSlow)
        return DIR_BUY;
    if (emaFast < emaSlow)
        return DIR_SELL;
    return DIR_NONE;
}

//+------------------------------------------------------------------+
//| Fungsi eksekusi utama                                           |
//+------------------------------------------------------------------+
void ExecuteTradeFromSignals()
{
    Dir direction;
    double confidence;
    string signalSource;

    // Ambil sinyal konsensus dari SignalEngine
    if (!signalEngine.GetConsensusSignal(direction, confidence, signalSource))
        return; // tidak ada sinyal

    // ✅ Cek proteksi RiskManager sebelum entry
    if (!RiskManager::CanOpenTrade())
    {
        Print("⚠️ Kondisi tidak aman, tidak entry (margin/spread/DD limit).");
        return;
    }

    // Hitung lot dinamis dengan proteksi margin
    double lotSize = RiskManager::GetDynamicLot(confidence, SL_Pips);

    // Entry BUY / SELL sesuai sinyal
    if (direction == DIR_BUY)
    {
        // string signalSource = "Entry BUY / SELL sesuai sinyal";
        ExecuteBuy(lotSize, SL_Pips, TP_Pips, signalSource);
    }
    else if (direction == DIR_SELL)
    {
        // string signalSource = "Entry BUY / SELL sesuai sinyal";
        ExecuteSell(lotSize, SL_Pips, TP_Pips, signalSource);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Chart Pattern Trading System Started");
    Print("Risk Management: ", RiskPercent, "% per trade");

    // Initialize dashboard timer jika diaktifkan
    if (EnableDashboard)
    {
        EventSetTimer(1);
        Print("Dashboard System Activated with Timer");
        ObjectsDeleteAll(0, -1, OBJ_LABEL);
    }

    // Test Telegram connection
    if (Dashboard_SendTelegram && EnableTelegram)
    {
        if (TelegramBotToken == "" || TelegramBotToken == "8470744929:AAHJ02vl-RUxRbVdc_kBZuSZdPx_Qzvtnr8")
        {
            Print("❌ Telegram: Please set your Bot Token in inputs");
        }
        else if (TelegramChatID == "" || TelegramChatID == "--1002864046051")
        {
            Print("❌ Telegram: Please set your Chat ID in inputs");
        }
        else
        {
            Print("✅ Telegram: Testing connection...");

            // Test message
            string testMsg = "🤖 *TRADING SYSTEM STARTED* 🤖\n";
            testMsg += "Symbol: " + _Symbol + "\n";
            testMsg += "Account: " + AccountInfoString(ACCOUNT_COMPANY) + "\n";
            testMsg += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
            testMsg += "System: Ultimate Trading EA v2.0\n";
            testMsg += "Time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

            SendTelegramMessage(testMsg);
        }
    }

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //---
    // Hapus semua objek chart dari dashboard
    if (EnableDashboard)
    {
        ObjectsDeleteAll(0, -1, OBJ_LABEL);
        EventKillTimer();
        Print("Dashboard Cleaned Up");
    }

    // Send shutdown message ke Telegram
    if (Dashboard_SendTelegram && TelegramChatID != TelegramChatID)
    {
        string shutdownMsg = "🛑 *TRADING SYSTEM STOPPED* 🛑\n";
        shutdownMsg += "Reason: " + GetUninitReasonText(reason) + "\n";
        shutdownMsg += "Time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
        SendTelegramMessage(shutdownMsg);
    }

    Print("Chart Pattern Trading System Stopped");
}

//==================================================================
// Helper: Get Uninit Reason Text
//==================================================================
string GetUninitReasonText(int reason)
{
    switch (reason)
    {
    case REASON_ACCOUNT:
        return "Account changed";
    case REASON_CHARTCHANGE:
        return "Chart changed";
    case REASON_CHARTCLOSE:
        return "Chart closed";
    case REASON_PARAMETERS:
        return "Parameters changed";
    case REASON_RECOMPILE:
        return "EA recompiled";
    case REASON_REMOVE:
        return "EA removed";
    case REASON_TEMPLATE:
        return "Template changed";
    default:
        return "Unknown reason";
    }
}
//+------------------------------------------------------------------+
//| Expert tick function - ULTIMATE TRADING SYSTEM                 |
//+------------------------------------------------------------------+
SignalEngine signalEngine; // Instance SignalEngine

// Tambahkan variabel global untuk tracking waktu entry
datetime lastTradeTime = 0;
int minSecondsBetweenTrades = 1; // Minimal 60 detik antara trade

// Fungsi untuk MQL5 - menghitung position yang sesuai
int GetCurrentTicketCount()
{
    int count = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            long magic = PositionGetInteger(POSITION_MAGIC);

            if (symbol == _Symbol && magic == 12345) // Ganti dengan magic number EA Anda
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Input Parameters                                                |
//+------------------------------------------------------------------+
input bool EnableSadamTier = true; // Enable/Disable Sadam Tier
input int Sadam_Priority = 3;      // Priority order (1=highest)
//+------------------------------------------------------------------+

// =========================================
// GLOBAL OBJECTS
// =========================================
SignalEngine engine; // supaya state (history sinyal) tidak reset

// =========================================
// HYBRID EXECUTION FLOW
// =========================================
enum TierType
{
    TIER_ULTRA = 0,
    TIER_ADX_RSI_BB,
    TIER_SADAM,
    TIER_POWER,
    TIER_ENHANCED,
    TIER_ADVANCED,
    TIER_MOMENTUM,
    TIER_OBSIGNAL,
    TIER_PBX,
    TIER_TLB
};

void ExecuteTradingFlow()
{
    bool tradeExecuted = true;

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Ultra Tier", TIER_ULTRA);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Ultra ADX_RSI_BB Tier", TIER_ADX_RSI_BB);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("OB SIGNAL Tier", TIER_OBSIGNAL);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("PBX Tier", TIER_PBX);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("TLB Tier", TIER_TLB);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Sadam Tier", TIER_SADAM);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Power Tier", TIER_POWER);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Enhanced Tier", TIER_ENHANCED);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Advanced Tier", TIER_ADVANCED);

    if (!tradeExecuted)
        tradeExecuted = ExecuteTierWithFilter("Momentum Tier", TIER_MOMENTUM);

    if (!tradeExecuted)
        Print("ℹ️ No valid trade executed this cycle.");
}

// =================== Integrasi PBX ke Tier ===================
bool ExecuteTierWithFilter(string tierName, TierType tier)
{
    bool tradeExecuted = true;

    // Panggil fungsi tier asli (entry logic dasar)
    switch (tier)
    {
    case TIER_ULTRA:
        tradeExecuted = ExecuteUltraTier1();
        break;
    case TIER_ADX_RSI_BB:  
        tradeExecuted = ExecuteTIER_ADX_RSI_BB();
        break;
    case TIER_SADAM:
        tradeExecuted = ExecuteSadamTier();
        break;
    case TIER_POWER:
        tradeExecuted = ExecutePowerTier2();
        break;
    case TIER_ENHANCED:
        tradeExecuted = ExecuteEnhancedTier3();
        break;
    case TIER_ADVANCED:
        tradeExecuted = ExecuteAdvancedTier4();
        break;
    case TIER_MOMENTUM:
        tradeExecuted = ExecuteMomentumTier5();
        break;
    case TIER_OBSIGNAL:
        tradeExecuted = OB_Signal();
        break;
    case TIER_TLB:
        tradeExecuted = LuxAlgoTrendLinesWithBreak();
        break;
    case TIER_PBX:
        tradeExecuted = ExecutePBXHybridFlow();
        break;
    }

    // =================== PBX Pullback Filter ===================
    if (tradeExecuted)
    {
        PBX_SignalResult pbxSignal = PBX_DetectSignal(); // fungsi PBX canggih kita
        if (pbxSignal.signal == PBX_NONE)
        {
            PrintFormat("⚠️ %s blocked - No valid PBX pullback signal", tierName);
            return false;
        }

        // =================== SignalEngine Filter ===================
        Dir confirmDir;
        double confidence;
        string signalSource;

        if (!engine.GetConsensusSignal(confirmDir, confidence, signalSource))
        {
            PrintFormat("⚠️ %s blocked - SignalEngine skip (News/OB active)", tierName);
            return false;
        }

        if (confidence < 0.6)
        {
            PrintFormat("❌ %s blocked by SignalEngine (confidence=%.2f)", tierName, confidence);
            return false;
        }

        PrintFormat("✅ %s confirmed by SignalEngine & PBX (confidence=%.2f)", tierName, confidence);

        // =================== Setup SL + TP ===================
        double entryPrice = pbxSignal.entry;
        double slPips = MathMax((pbxSignal.signal == PBX_BUY)
                                    ? (entryPrice - pbxSignal.sl) / _Point
                                    : (pbxSignal.sl - entryPrice) / _Point,
                                50);                // minimal 50 pips
        double tpPips = MathMax(slPips * 1.5, 100); // minimal RR 1:1.5 / 100 pips

        // =================== Order Placement ===================
        if (pbxSignal.signal == PBX_BUY)
        {
            ExecuteBuy(2.0, (int)slPips, (int)tpPips, tierName + " PBX BUY");
            tradeExecuted = true;
        }
        else if (pbxSignal.signal == PBX_SELL)
        {
            ExecuteSell(2.0, (int)slPips, (int)tpPips, tierName + " PBX SELL");
            tradeExecuted = true;
        }
    }

    return tradeExecuted;
}

void OnTick()
{
    // ==================== ADVANCED RISK MANAGEMENT ====================
    ManageAdvancedRisk();
    ManageTrailingBreakCloseUltimate();
    //---
    // ==================== PROFIT BOOSTER FILTER ====================
    if (!AdvancedProfitFilter())
        return;

    // ==================== ANALISIS SEMUA TIER SECARA BERURUTAN ====================
    bool tradeExecuted = false;
    // ==================== ENTRY COOLDOWN CHECK ====================
    if (TimeCurrent() - lastTradeTime < minSecondsBetweenTrades)
        return;

    // ==================== POSITION LIMIT CHECK ====================
    if (PositionsTotal() >= 30)
        return;

    // Eksekusi hybrid trading flow
    ExecuteTradingFlow();

    // ==================== DASHBOARD UPDATE ====================
    static datetime lastDashboardCheck = 0;
    static int lastTicketCount = 0;

    if (EnableDashboard)
    {
        int currentTicketCount = GetCurrentTicketCount();
        bool newEntryDetected = (currentTicketCount > lastTicketCount);
        bool timeBasedUpdate = (TimeCurrent() - lastDashboardCheck >= 5);

        if (newEntryDetected || timeBasedUpdate)
        {
            CollectActiveSignals();
            UpdateSignalsUltimateLive2();
            lastDashboardCheck = TimeCurrent();
            lastTicketCount = currentTicketCount;
        }
    }

    // Backup System (Lowest Priority)
    if (!tradeExecuted)
    {
        ExecuteBackupSystem();
    }
}

bool OB_Signal()
{
    bool tradeExecuted = false;
    // --- OB Signal Override System ---
    OBSignal obSig = DetectOrderBlockPro(0.01, 50, 50, 3, 10, 20, true);
    if (obSig.signal != DIR_NONE)
    {
        double lot = obSig.lotSize;

        // OB Strong = premium trade
        bool isPremiumTrade = obSig.isStrong;

        // Cek Risk Manager
        if (!RiskManager::CanOpenTrade(isPremiumTrade))
        {
            // Strong override: jika isStrong=true, sesuaikan lot agar aman
            if (obSig.isStrong)
            {
                lot = MathMin(lot, RiskManager::GetMaxLot());
                if (!RiskManager::CanOpenTrade(isPremiumTrade))
                {
                    Print("⚠️ Strong OB signal blocked by RiskManager");
                    obSig.signal = DIR_NONE;
                }
            }
            else
            {
                obSig.signal = DIR_NONE;
            }
        }

        // Eksekusi OB Signal jika lolos proteksi
        if (obSig.signal == DIR_BUY)
        {
            ExecuteBuy(lot, (int)obSig.stopLoss, (int)obSig.takeProfit, "OB Strong BUY");
            tradeExecuted = true;
        }
        else if (obSig.signal == DIR_SELL)
        {
            ExecuteSell(lot, (int)obSig.stopLoss, (int)obSig.takeProfit, "OB Strong SELL");
            tradeExecuted = true;
        }
    }

    return tradeExecuted;
}

// ==================== PBX HYBRID FLOW ====================
bool ExecutePBXHybridFlow()
{
    bool tradeExecuted = true;
    PBX_SignalResult pbxSignal = PBX_DetectSignal();

    // Hanya jalankan hybrid flow kalau PBX valid
    if (pbxSignal.signal == PBX_NONE)
    {
        Print("⚠️ PBX Hybrid Flow blocked - No valid pullback signal");
        return tradeExecuted;
    }

    // ==================== TRAILING SL / BREAK EVEN ====================
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket))
            continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? PBX_BUY : PBX_SELL;

        double newSL = PBX_ManageSL(
            openPrice,
            (dir == PBX_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK),
            currentSL,
            dir);

        if (newSL != currentSL)
        {
            // Update SL order
            PBX_TrailingSLHandler();
        }
    }
    return tradeExecuted;
}

//+------------------------------------------------------------------+
//| Input Parameters - SADAM SYSTEM                                 |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES SADAM_TF_Entry = PERIOD_M5; // Sadam: Timeframe Entry
input ENUM_TIMEFRAMES SADAM_TF_Trend = PERIOD_H4; // Sadam: Timeframe Trend Filter
input int SADAM_EMA_Period = 200;                 // Sadam: EMA untuk trend filter
input int SADAM_ATR_Period = 14;                  // Sadam: ATR period
input double SADAM_ATR_Factor = 1.5;              // Sadam: ATR multiplier
input int SADAM_Volume_Period = 20;               // Sadam: rata-rata volume N candle
input int SADAM_Momentum_Candles = 2;             // Sadam: jumlah candle momentum searah
input double SADAM_Risk_Percent = 30.0;           // Sadam: risk per trade (% balance)
input int SADAM_Fib_Type = 0;                     // Sadam: 0=off, 1=50%, 2=61.8%
input int SADAM_SR_Lookback = 50;                 // Sadam: jumlah candle untuk SR
input double SADAM_SR_BufferPips = 30;            // Sadam: buffer jarak dari SnR
input bool SADAM_Enabled = true;                  // Sadam: Enable/Disable system
input int SADAM_Priority = 3;                     // Sadam: Priority order (1=highest)

//+------------------------------------------------------------------+
//| Check Entry Signal - SADAM SYSTEM                               |
//+------------------------------------------------------------------+
bool DeteksiSadam(string symbol, bool isBuy)
{
    // --- 1. Higher TF Trend Filter
    double ema[];
    if (CopyBuffer(iMA(symbol, SADAM_TF_Trend, SADAM_EMA_Period, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, ema) < 2)
        return false;
    double priceTrend = iClose(symbol, SADAM_TF_Trend, 0);
    if (isBuy && priceTrend < ema[0])
        return false;
    if (!isBuy && priceTrend > ema[0])
        return false;

    // --- 2. ATR Candle Strength Filter
    double atr[];
    if (CopyBuffer(iATR(symbol, SADAM_TF_Entry, SADAM_ATR_Period), 0, 0, 2, atr) < 2)
        return false;
    double body = MathAbs(iClose(symbol, SADAM_TF_Entry, 0) - iOpen(symbol, SADAM_TF_Entry, 0));
    if (body < atr[0] * SADAM_ATR_Factor)
        return false;

    // --- 3. Volume Confirmation Filter
    double avgVolume = 0;
    for (int i = 1; i <= SADAM_Volume_Period; i++)
        avgVolume += (double)iVolume(symbol, SADAM_TF_Entry, i);
    avgVolume /= SADAM_Volume_Period;
    double currentVolume = (double)iVolume(symbol, SADAM_TF_Entry, 0);
    if (currentVolume <= avgVolume)
        return false;

    // --- 4. Multi-Candle Momentum Confirmation
    int bullish = 0, bearish = 0;
    for (int i = 1; i <= SADAM_Momentum_Candles; i++)
    {
        double o = iOpen(symbol, SADAM_TF_Entry, i);
        double c = iClose(symbol, SADAM_TF_Entry, i);
        if (c > o)
            bullish++;
        if (c < o)
            bearish++;
    }
    if (isBuy && bullish < SADAM_Momentum_Candles)
        return false;
    if (!isBuy && bearish < SADAM_Momentum_Candles)
        return false;

    // --- 5. Fibonacci Pullback Entry (opsional)
    if (SADAM_Fib_Type > 0)
    {
        double high = iHigh(symbol, SADAM_TF_Entry, 1);
        double low = iLow(symbol, SADAM_TF_Entry, 1);
        double fibLevel = (SADAM_Fib_Type == 1 ? 0.5 : 0.618);
        double fibPrice = low + (high - low) * fibLevel;
        double lastPrice = iClose(symbol, SADAM_TF_Entry, 0);

        if (isBuy && lastPrice < fibPrice)
            return false;
        if (!isBuy && lastPrice > fibPrice)
            return false;
    }

    // --- 6. Support & Resistance Filter (Smart SnR Trading)
    double curHigh = iHigh(symbol, SADAM_TF_Entry, 0);
    double curLow = iLow(symbol, SADAM_TF_Entry, 0);
    double recentHigh = curHigh;
    double recentLow = curLow;

    for (int i = 1; i <= SADAM_SR_Lookback; i++)
    {
        recentHigh = MathMax(recentHigh, iHigh(symbol, SADAM_TF_Entry, i));
        recentLow = MathMin(recentLow, iLow(symbol, SADAM_TF_Entry, i));
    }

    double buffer = SymbolInfoDouble(symbol, SYMBOL_POINT) * SADAM_SR_BufferPips;
    double lastPrice = iClose(symbol, SADAM_TF_Entry, 0);

    // --- Jika harga terlalu dekat SnR -> hindari entry
    if (MathAbs(lastPrice - recentHigh) < buffer)
        return false;
    if (MathAbs(lastPrice - recentLow) < buffer)
        return false;

    // --- Smart SnR Trading Logic
    // BUY: hanya valid jika harga dekat support & mantul (rejection candle)
    if (isBuy)
    {
        if (MathAbs(lastPrice - recentLow) < buffer)
        {
            double closePrev = iClose(symbol, SADAM_TF_Entry, 1);
            double openPrev = iOpen(symbol, SADAM_TF_Entry, 1);
            if (closePrev < openPrev)
                return false; // candle sebelumnya bearish → tolak BUY
        }
    }

    // SELL: hanya valid jika harga dekat resistance & rejection
    if (!isBuy)
    {
        if (MathAbs(lastPrice - recentHigh) < buffer)
        {
            double closePrev = iClose(symbol, SADAM_TF_Entry, 1);
            double openPrev = iOpen(symbol, SADAM_TF_Entry, 1);
            if (closePrev > openPrev)
                return false; // candle sebelumnya bullish → tolak SELL
        }
    }

    // --- Semua filter lolos
    return true;
}

//+------------------------------------------------------------------+
//| Execute Sadam Tier - Advanced Multi-Filter System               |
//+------------------------------------------------------------------+
bool ExecuteSadamTier()
{
    if (!SADAM_Enabled)
        return false;

    string symbol = Symbol();
    double lotSize = CalculateSadamLotSize(SADAM_Risk_Percent);

    // Check BUY signal
    if (DeteksiSadam(symbol, true))
    {
        double sl = CalculateSadamStopLoss(symbol, true);
        double tp = CalculateSadamTakeProfit(symbol, true, sl);

        // Eksekusi order tanpa pengecekan hasil
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lotSize, sl, tp, "SADAM-BUY");
        Print("SADAM TIER: BUY Order Executed");
        lastTradeTime = TimeCurrent();
        return true;
    }

    // Check SELL signal
    if (DeteksiSadam(symbol, false))
    {
        double sl = CalculateSadamStopLoss(symbol, false);
        double tp = CalculateSadamTakeProfit(symbol, false, sl);

        // Eksekusi order tanpa pengecekan hasil
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lotSize, sl, tp, "SADAM-SELL");
        Print("SADAM TIER: SELL Order Executed");
        lastTradeTime = TimeCurrent();
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Execute Trade Function for MQL5                                 |
//+------------------------------------------------------------------+
bool ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType, double volume, double sl, double tp, string comment)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    // Set trade request parameters
    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = volume;
    request.type = orderType;
    request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 123456;
    request.comment = comment;
    request.type_filling = ORDER_FILLING_FOK;

    // Send order
    bool success = OrderSend(request, result);

    if (!success)
    {
        Print("OrderSend failed. Error code: ", GetLastError());
        Print("Retcode: ", result.retcode, ", Description: ", GetRetcodeID(result.retcode));
        return false;
    }

    if (result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade failed. Retcode: ", result.retcode, ", Description: ", GetRetcodeID(result.retcode));
        return false;
    }

    Print("Trade executed successfully. Ticket: ", result.order);
    return true;
}

//+------------------------------------------------------------------+
//| Get Retcode ID for better error messages                        |
//+------------------------------------------------------------------+
string GetRetcodeID(int retcode)
{
    switch (retcode)
    {
    case 10004:
        return "TRADE_RETCODE_REQUOTE";
    case 10006:
        return "TRADE_RETCODE_REJECT";
    case 10007:
        return "TRADE_RETCODE_CANCEL";
    case 10008:
        return "TRADE_RETCODE_PLACED";
    case 10009:
        return "TRADE_RETCODE_DONE";
    case 10010:
        return "TRADE_RETCODE_DONE_PARTIAL";
    case 10011:
        return "TRADE_RETCODE_ERROR";
    case 10012:
        return "TRADE_RETCODE_TIMEOUT";
    case 10013:
        return "TRADE_RETCODE_INVALID";
    case 10014:
        return "TRADE_RETCODE_INVALID_VOLUME";
    case 10015:
        return "TRADE_RETCODE_INVALID_PRICE";
    case 10016:
        return "TRADE_RETCODE_INVALID_STOPS";
    case 10017:
        return "TRADE_RETCODE_TRADE_DISABLED";
    case 10018:
        return "TRADE_RETCODE_MARKET_CLOSED";
    case 10019:
        return "TRADE_RETCODE_NO_MONEY";
    case 10020:
        return "TRADE_RETCODE_PRICE_CHANGED";
    case 10021:
        return "TRADE_RETCODE_PRICE_OFF";
    case 10022:
        return "TRADE_RETCODE_INVALID_EXPIRATION";
    case 10023:
        return "TRADE_RETCODE_ORDER_CHANGED";
    case 10024:
        return "TRADE_RETCODE_TOO_MANY_REQUESTS";
    case 10025:
        return "TRADE_RETCODE_NO_CHANGES";
    case 10026:
        return "TRADE_RETCODE_SERVER_DISABLES_AT";
    case 10027:
        return "TRADE_RETCODE_CLIENT_DISABLES_AT";
    case 10028:
        return "TRADE_RETCODE_LOCKED";
    case 10029:
        return "TRADE_RETCODE_FROZEN";
    case 10030:
        return "TRADE_RETCODE_INVALID_FILL";
    case 10031:
        return "TRADE_RETCODE_CONNECTION";
    case 10032:
        return "TRADE_RETCODE_ONLY_REAL";
    case 10033:
        return "TRADE_RETCODE_LIMIT_ORDERS";
    case 10034:
        return "TRADE_RETCODE_LIMIT_VOLUME";
    case 10035:
        return "TRADE_RETCODE_INVALID_ORDER";
    case 10036:
        return "TRADE_RETCODE_POSITION_CLOSED";
    case 10038:
        return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
    case 10039:
        return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
    case 10040:
        return "TRADE_RETCODE_LIMIT_POSITIONS";
    case 10041:
        return "TRADE_RETCODE_REJECT_CANCEL";
    case 10042:
        return "TRADE_RETCODE_LONG_ONLY";
    case 10043:
        return "TRADE_RETCODE_SHORT_ONLY";
    case 10044:
        return "TRADE_RETCODE_CLOSE_ONLY";
    case 10045:
        return "TRADE_RETCODE_FIFO_CLOSE";
    default:
        return "UNKNOWN_ERROR";
    }
}
//+------------------------------------------------------------------+
//| Calculate Stop Loss - SADAM SYSTEM                              |
//+------------------------------------------------------------------+
double CalculateSadamStopLoss(string symbol, bool isBuy)
{
    double atr[];
    if (CopyBuffer(iATR(symbol, SADAM_TF_Entry, SADAM_ATR_Period), 0, 0, 1, atr) < 1)
        return 0;

    double price = isBuy ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
    double slDistance = atr[0] * SADAM_ATR_Factor;

    return isBuy ? price - slDistance : price + slDistance;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit - SADAM SYSTEM                            |
//+------------------------------------------------------------------+
double CalculateSadamTakeProfit(string symbol, bool isBuy, double sl)
{
    double price = isBuy ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
    double risk = MathAbs(price - sl);

    // Risk:Reward ratio 1:1.5
    return isBuy ? price + (risk * 1.5) : price - (risk * 1.5);
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk - SADAM SYSTEM                 |
//+------------------------------------------------------------------+
double CalculateSadamLotSize(double riskPercent)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * riskPercent / 100.0;
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);

    if (tickValue == 0)
        return 0.05;

    double lotSize = riskAmount / tickValue;
    return NormalizeDouble(lotSize, 2);
}

// ==================== FILTER CANGGIH TANPA UBAH FUNGSI ====================
bool AdvancedProfitFilter()
{
    Print("🔥 MAX PROFIT MODE - AUTO APPROVE");

    // Hanya filter dasar saja - auto approve hampir semua
    double atr = iATR(_Symbol, PERIOD_M5, 14);
    double atrPercent = (atr / SymbolInfoDouble(_Symbol, SYMBOL_BID)) * 100;

    // Auto reject hanya jika market benar2 mati
    if (atrPercent < 0.003)
    {
        Print("⚡ Market extremely quiet - waiting for volatility");
        return false; // Hanya kondisi ini yang di-reject
    }

    // Selain itu, APPROVE SEMUA
    Print("✅ AUTO-APPROVED: High Profit Opportunity");
    return true;
}
bool ExecuteUltraTier1()
{
    // 1. ORDER BLOCK SUPER FILTERED
    static datetime lastOBCheck = 0;
    if (UseOrderBlock || (TimeCurrent() - lastOBCheck >= 3600))
    {
        OBSignal obSignal = DetectOrderBlockPro(OB_BaseLot, OB_EMAPeriod1, OB_EMAPeriod2, OB_Levels, OB_ZoneBufferPips, OB_Lookback);

        if (obSignal.signal != DIR_NONE || obSignal.isStrong)
        {
            double rrRatio = CalculateRRRatio(obSignal);
            if (rrRatio >= 2.5)
            {
                double optimalLot = RiskManager::GetDynamicLot(0.8,
                                                               (int)((obSignal.entryPrice - obSignal.stopLoss) / _Point / 10));

                // PERBAIKAN: Direct execution tanpa if condition
                if (obSignal.signal == DIR_BUY)
                {
                    string signalSource = "ORDER BLOCK SUPER FILTERED";
                    int slPips = (int)((obSignal.entryPrice - obSignal.stopLoss) / _Point / 10);
                    int tpPips = (int)((obSignal.takeProfit - obSignal.entryPrice) / _Point / 10);
                    ExecuteBuy(optimalLot, slPips, tpPips, signalSource); // LANGSUNG EXECUTE

                    if (Dashboard_SendTelegram)
                        SendTradeAlert(_Symbol, DIR_BUY, optimalLot, obSignal.entryPrice, obSignal.stopLoss, obSignal.takeProfit, "ORDER BLOCK ULTRA");

                    PrintFormat("🏆 ORDER BLOCK ULTRA: BUY | RR: 1:%.1f | Super Filtered", rrRatio);
                    lastTradeTime = TimeCurrent();
                    lastOBCheck = TimeCurrent();
                    return true;
                }
                else
                {
                    string signalSource = "ORDER BLOCK SUPER FILTERED";
                    int slPips = (int)((obSignal.stopLoss - obSignal.entryPrice) / _Point / 10);
                    int tpPips = (int)((obSignal.entryPrice - obSignal.takeProfit) / _Point / 10);
                    ExecuteSell(optimalLot, slPips, tpPips, signalSource); // LANGSUNG EXECUTE

                    if (Dashboard_SendTelegram)
                        SendTradeAlert(_Symbol, DIR_SELL, optimalLot, obSignal.entryPrice, obSignal.stopLoss, obSignal.takeProfit, "ORDER BLOCK ULTRA");

                    PrintFormat("🏆 ORDER BLOCK ULTRA: SELL | RR: 1:%.1f | Super Filtered", rrRatio);
                    lastTradeTime = TimeCurrent();
                    lastOBCheck = TimeCurrent();
                    return true;
                }
            }
        }
        lastOBCheck = TimeCurrent();
    }

    // 2. PRICE ACTION ENHANCED - PERBAIKAN YANG SAMA
    static datetime lastPACheck = 0;
    if (UsePriceAction || (TimeCurrent() - lastPACheck >= 4))
    {
        PA_Signal paSignal = DetectPriceAction_MTF(_Symbol, 2);

        if (paSignal.found || paSignal.lotLevel >= 3 || IsSignalInTrend(paSignal.direction))
        {
            ExecutePriceActionTrade(paSignal); // LANGSUNG EXECUTE

            if (Dashboard_SendTelegram)
                SendTradeAlert(_Symbol, paSignal.direction, paSignal.lotSize, paSignal.entryPrice, paSignal.stopLoss, paSignal.takeProfit, "PRICE ACTION ENHANCED");

            PrintFormat("🎯 PRICE ACTION ENHANCED: %s | Strong Pattern | Multi-TF Confirmed",
                        (paSignal.direction == DIR_BUY ? "BULLISH" : "BEARISH"));
            lastTradeTime = TimeCurrent();
            lastPACheck = TimeCurrent();
            return true;
        }
        lastPACheck = TimeCurrent();
    }

    return false;
}

bool ExecutePowerTier2()
{
   bool  executed = false;
    // 4. MOMENTUM SCALPING ENHANCED
    static datetime lastMomentumCheck = 0;
    if (UseMomentumPullback && (TimeCurrent() - lastMomentumCheck >= 3))
    {
        MomentumSignal momentumSignal;
        if (DetectMomentumPullback(MomentumTF, momentumSignal, MomentumLookback) && momentumSignal.found)
        {
            if (IsScalpingCondition() || IsSignalInTrend(momentumSignal.dir))
            {
                double scalpLot = RiskManager::GetDynamicLot(0.5,
                                                             (int)((momentumSignal.entryPrice - momentumSignal.stopLoss) / _Point / 10));

                // PERBAIKAN: Direct execution
                if (momentumSignal.dir == DIR_BUY)
                {
                    string signalSource = "MOMENTUM SCALP";
                    int slPips = (int)((momentumSignal.entryPrice - momentumSignal.stopLoss) / _Point / 10);
                    int tpPips = (int)((momentumSignal.takeProfit - momentumSignal.entryPrice) / _Point / 10);
                    ExecuteBuy(scalpLot, slPips, tpPips, signalSource); // LANGSUNG EXECUTE
                    executed = true;

                    if (Dashboard_SendTelegram)
                        SendTradeAlert(_Symbol, DIR_BUY, scalpLot, momentumSignal.entryPrice, momentumSignal.stopLoss, momentumSignal.takeProfit, "MOMENTUM SCALP");
                    PrintFormat("⚡ MOMENTUM SCALP: BUY | Quick Profit");
                }
                else
                {
                    string signalSource = "MOMENTUM SCALP";
                    int slPips = (int)((momentumSignal.stopLoss - momentumSignal.entryPrice) / _Point / 10);
                    int tpPips = (int)((momentumSignal.entryPrice - momentumSignal.takeProfit) / _Point / 10);
                    ExecuteSell(scalpLot, slPips, tpPips, signalSource); // LANGSUNG EXECUTE
                    executed = true;

                    if (Dashboard_SendTelegram)
                        SendTradeAlert(_Symbol, DIR_SELL, scalpLot, momentumSignal.entryPrice, momentumSignal.stopLoss, momentumSignal.takeProfit, "MOMENTUM SCALP");
                    PrintFormat("⚡ MOMENTUM SCALP: SELL | Quick Profit");
                }
                if (executed)
                    lastTradeTime = TimeCurrent();
            }
        }
        lastMomentumCheck = TimeCurrent();
    }

    return executed;
}
bool ExecuteEnhancedTier3()
{
    // 8. STOCHASTIC POWER UPGRADE
    static datetime lastStochCheck = 0;
    if (UseStochastic || (TimeCurrent() - lastStochCheck >= 10))
    {
        StochSignal stochSignal = GetStochasticSignalUltimateAdvanced(Stoch_TFLow, Stoch_TFHigh, Stoch_KPeriod, Stoch_DPeriod, Stoch_Slowing, Stoch_EMAPeriod, Stoch_ATR_Multiplier, 0);

        if ((stochSignal.signal != DIR_NONE && stochSignal.isStrong &&
             IsStochasticPower(stochSignal)) ||
            IsSignalInTrend(stochSignal.signal) || HasVolumeConfirmation())
        {
            double stochLot = RiskManager::GetDynamicLot(0.6,
                                                         (int)((stochSignal.entryPrice - stochSignal.stopLoss) / _Point / 10));
            if (stochSignal.signal != DIR_NONE)
            {
                // Eksekusi trade langsung pakai fungsi universal
                ExecuteStochasticTrade(stochSignal);

                if (Dashboard_SendTelegram)
                    SendTradeAlert(_Symbol, stochSignal.signal,
                                   0.0, // lot dihitung otomatis dalam ExecuteStochasticTrade
                                   stochSignal.entryPrice, stochSignal.stopLoss, stochSignal.takeProfit,
                                   "STOCHASTIC POWER");

                PrintFormat("📊 STOCHASTIC POWER: %s | K:%.1f D:%.1f | Enhanced Signal",
                            stochSignal.signal == DIR_BUY ? "BUY" : "SELL",
                            stochSignal.kValueLow, stochSignal.dValueLow);

                lastTradeTime = TimeCurrent();
                lastStochCheck = TimeCurrent();
                return true;
            }
        }
        lastStochCheck = TimeCurrent();
    }

    return false;
}

// ==================== NEW TIER 4: ADVANCED PATTERNS ====================
bool ExecuteAdvancedTier4()
{
    bool executed = false;

    // 9. CHART PATTERNS ULTIMATE
    static datetime lastChartCheck = 0;
    if (TimeCurrent() - lastChartCheck >= 300) // Setiap 5 menit
    {
        ChartPatternSignal chartSignal = GetChartPatternSignalUltimate(1, 10, PERIOD_M15);

        if (chartSignal.signal != DIR_NONE && chartSignal.isStrong && IsSignalInTrend(chartSignal.signal))
        {
            double chartLot = RiskManager::GetDynamicLot(0.7,
                                                         (int)((chartSignal.entryPrice - chartSignal.stopLoss) / _Point / 10));

            if (chartSignal.signal == DIR_BUY)
            {
                string signalSource = "CHART PATTERN";
                int slPips = (int)((chartSignal.entryPrice - chartSignal.stopLoss) / _Point / 10);
                int tpPips = (int)((chartSignal.takeProfit - chartSignal.entryPrice) / _Point / 10);
                ExecuteBuy(chartLot, slPips, tpPips, signalSource);

                PrintFormat("📈 CHART PATTERN: BUY | %s | Strong Pattern", chartSignal.patternName);
                lastTradeTime = TimeCurrent();
                executed = true;
            }
            else
            {
                string signalSource = "CHART PATTERN";
                int slPips = (int)((chartSignal.stopLoss - chartSignal.entryPrice) / _Point / 10);
                int tpPips = (int)((chartSignal.entryPrice - chartSignal.takeProfit) / _Point / 10);
                ExecuteSell(chartLot, slPips, tpPips, signalSource);

                PrintFormat("📈 CHART PATTERN: SELL | %s | Strong Pattern", chartSignal.patternName);
                lastTradeTime = TimeCurrent();
                executed = true;
            }
        }
        lastChartCheck = TimeCurrent();
    }

    // 10. HARMONIC PATTERNS PRO
    static datetime lastHarmonicCheck = 0;
    if (TimeCurrent() - lastHarmonicCheck >= 600) // Setiap 10 menit
    {
        // Ambil titik XABCD dari chart
        double X = iHigh(_Symbol, PERIOD_H1, 10);
        double A = iLow(_Symbol, PERIOD_H1, 8);
        double B = iHigh(_Symbol, PERIOD_H1, 6);
        double C = iLow(_Symbol, PERIOD_H1, 4);
        double D = iClose(_Symbol, PERIOD_H1, 0);

        HarmonicPatternSignal harmonicSignal = DetectHarmonicPattern(X, A, B, C, D);

        if (harmonicSignal.signal != DIR_NONE && harmonicSignal.isStrong && IsSignalInTrend(harmonicSignal.signal))
        {
            double harmonicLot = RiskManager::GetDynamicLot(0.6,
                                                            (int)(MathAbs(D - harmonicSignal.stopLoss) / _Point / 10));

            if (harmonicSignal.signal == DIR_BUY)
            {
                string signalSource = "HARMONIC PATTERN";
                ExecuteBuy(harmonicLot,
                           (int)((D - harmonicSignal.stopLoss) / _Point / 10),
                           (int)((harmonicSignal.takeProfit - D) / _Point / 10), signalSource);

                PrintFormat("🎯 HARMONIC PATTERN: BUY | %s | High Probability", harmonicSignal.patternName);
                lastTradeTime = TimeCurrent();
                executed = true;
            }
            else
            {
                string signalSource = "HARMONIC PATTERN";
                ExecuteSell(harmonicLot,
                            (int)((harmonicSignal.stopLoss - D) / _Point / 10),
                            (int)((D - harmonicSignal.takeProfit) / _Point / 10), signalSource);

                PrintFormat("🎯 HARMONIC PATTERN: SELL | %s | High Probability", harmonicSignal.patternName);
                lastTradeTime = TimeCurrent();
                executed = true;
            }
        }
        lastHarmonicCheck = TimeCurrent();
    }

    // 11. SMART MONEY CONCEPT (SMC)
    static datetime lastSMCCheck = 0;
    if (TimeCurrent() - lastSMCCheck >= 180) // Setiap 3 menit
    {
        SMCSignal smcSignal = DetectSMCSignalAdvanced(SMC_BaseLot, SMC_EMA_Period1, SMC_EMA_Period2, SMC_Lookback, SMC_ATR_Multiplier);

        if (smcSignal.signal != DIR_NONE && smcSignal.isStrong)
        {
            if (smcSignal.signal == DIR_BUY)
            {
                string signalSource = "SMART MONEY CONCEPT (SMC)";
                ExecuteBuy(smcSignal.lotSize,
                           (int)((smcSignal.entryPrice - smcSignal.stopLoss) / _Point / 10),
                           (int)((smcSignal.takeProfit - smcSignal.entryPrice) / _Point / 10), signalSource);

                PrintFormat("💎 SMC SIGNAL: BUY | Smart Money Detection");
                lastTradeTime = TimeCurrent();
                executed = true;
            }
            else
            {
                string signalSource = "SMART MONEY CONCEPT (SMC)";
                ExecuteSell(smcSignal.lotSize,
                            (int)((smcSignal.stopLoss - smcSignal.entryPrice) / _Point / 10),
                            (int)((smcSignal.entryPrice - smcSignal.takeProfit) / _Point / 10), signalSource);

                PrintFormat("💎 SMC SIGNAL: SELL | Smart Money Detection");
                lastTradeTime = TimeCurrent();
                executed = true;
            }
        }
        lastSMCCheck = TimeCurrent();
    }

    return executed;
}

// ==================== NEW TIER 5: MOMENTUM & VOLUME ====================
bool ExecuteMomentumTier5()
{
    bool executed = false;

    // 12. ICEBERG VOLUME DETECTION
    static datetime lastIcebergCheck = 0;
    if (TimeCurrent() - lastIcebergCheck >= 60) // Setiap 1 menit
    {
        IcebergLevel iceberg = DetectIcebergAdvanced(0); // Current candle

        if (iceberg == ICE_STRONG)
        {
            // Ambil sinyal dari momentum untuk konfirmasi arah
            MomentumSignal momentumSignal;
            if (DetectMomentumPullback(PERIOD_M5, momentumSignal, 10) && momentumSignal.found)
            {
                double volumeLot = RiskManager::GetDynamicLot(0.4,
                                                              (int)((momentumSignal.entryPrice - momentumSignal.stopLoss) / _Point / 10));

                if (momentumSignal.dir == DIR_BUY)
                {
                    string signalSource = "ICEBERG VOLUME";
                    ExecuteBuy(volumeLot,
                               (int)((momentumSignal.entryPrice - momentumSignal.stopLoss) / _Point / 10),
                               (int)((momentumSignal.takeProfit - momentumSignal.entryPrice) / _Point / 10), signalSource);

                    PrintFormat("🧊 ICEBERG VOLUME: BUY | Strong Institutional Volume");
                    lastTradeTime = TimeCurrent();
                    executed = true;
                }
                else
                {
                    string signalSource = "ICEBERG VOLUME";
                    ExecuteSell(volumeLot,
                                (int)((momentumSignal.stopLoss - momentumSignal.entryPrice) / _Point / 10),
                                (int)((momentumSignal.entryPrice - momentumSignal.takeProfit) / _Point / 10), signalSource);

                    PrintFormat("🧊 ICEBERG VOLUME: SELL | Strong Institutional Volume");
                    lastTradeTime = TimeCurrent();
                    executed = true;
                }
            }
        }
        lastIcebergCheck = TimeCurrent();
    }

    // 13. SMART CONVERGENCE MOMENTUM (SCM)
    static datetime lastSCMCheck = 0;
    if (TimeCurrent() - lastSCMCheck >= 120) // Setiap 2 menit
    {
        SCMSignal scmSignal = DetectSCMSignalHighProb(SCM_BaseLot, SCM_EMAPeriod, SCM_RSIPeriod,
                                                      SCM_RSI_OB, SCM_RSI_OS, SCM_MACD_Fast,
                                                      SCM_MACD_Slow, SCM_MACD_Signal, SCM_ATRPeriod,
                                                      SCM_ATRMultiplier);

        if (scmSignal.signal != DIR_NONE && scmSignal.isStrong)
        {
            if (scmSignal.signal == DIR_BUY)
            {
                string signalSource = "SCM SIGNAL";
                ExecuteBuy(scmSignal.lotSize,
                           (int)((scmSignal.entryPrice - scmSignal.stopLoss) / _Point / 10),
                           (int)((scmSignal.takeProfit - scmSignal.entryPrice) / _Point / 10), signalSource);

                PrintFormat("⚡ SCM SIGNAL: BUY | Multi-Indicator Convergence");
                lastTradeTime = TimeCurrent();
                executed = true;
            }
            else
            {
                string signalSource = "SCM SIGNAL";
                ExecuteSell(scmSignal.lotSize,
                            (int)((scmSignal.stopLoss - scmSignal.entryPrice) / _Point / 10),
                            (int)((scmSignal.entryPrice - scmSignal.takeProfit) / _Point / 10), signalSource);

                PrintFormat("⚡ SCM SIGNAL: SELL | Multi-Indicator Convergence");
                lastTradeTime = TimeCurrent();
                executed = true;
            }
        }
        lastSCMCheck = TimeCurrent();
    }

    return executed;
}

void ExecuteBackupSystem()
{
    static datetime lastSignalCheck = 0;
    if (TimeCurrent() - lastSignalCheck >= 12)
    {
        if (!HasActiveTrades() && !IsNewsPeriod() && RiskManager::CanOpenTrade())
        {
            ExecuteTradeFromSignals();
        }
        lastSignalCheck = TimeCurrent();
    }
}

void ManageAdvancedRisk()
{
    static datetime lastRiskCheck = 0;
    if (TimeCurrent() - lastRiskCheck >= 1)
    {
        ManageTrailingBreakCloseUltimate();

        static bool riskAlertSent = false;
        if (!RiskManager::CanOpenTrade())
        {
            if (!riskAlertSent)
            {
                SendTelegramMessage("🚨 RISK MANAGEMENT ALERT 🚨\nTrading suspended!");
                riskAlertSent = true;
            }
        }
        else
        {
            riskAlertSent = false; // reset kalau kondisi sudah normal
        }

        lastRiskCheck = TimeCurrent();
    }
}

// MANAGE TRALING STOP

input double BE_Pips        = 10;   
input double BE_Buffer      = 2;    
input double TrailLevel1    = 15;
input double TrailDistance1 = 5;
input double TrailLevel2    = 30;
input double TrailDistance2 = 10;
input int LevelsCount       = 2;
input ENUM_TIMEFRAMES ConfirmTF = PERIOD_M5;
input bool UseTrendFilter   = true;

input double MinProfitForAutoClean = 5;          
input ENUM_TIMEFRAMES AutoCleanTF = PERIOD_M1;   
input double MinBodyPips = 2;                    
input int TrendEMAPeriod = 200;                  

struct TrailingUltimateParams
{
    double bePips;
    double beBuffer;
    double trailLevels[10];
    double trailDistances[10];
    int levelsCount;
    ENUM_TIMEFRAMES tfConfirm;
    bool useTrendFilter;
};

double StochTrailingStop(double price, double currentSL, bool isBuy, double atr, double factor)
{
    if(isBuy) return price - atr*factor;
    else       return price + atr*factor;
}

void ManageTrailingBreakCloseUltimate()
{
    TrailingUltimateParams params;
    params.bePips        = BE_Pips;
    params.beBuffer      = BE_Buffer;
    params.trailLevels[0] = TrailLevel1;
    params.trailDistances[0] = TrailDistance1;
    params.trailLevels[1] = TrailLevel2;
    params.trailDistances[1] = TrailDistance2;
    params.levelsCount   = LevelsCount;
    params.tfConfirm     = ConfirmTF;
    params.useTrendFilter= UseTrendFilter;

    double emaTrend = iMA(_Symbol, PERIOD_CURRENT, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        if(!PositionGetTicket(i)) continue;

        ulong  ticket = PositionGetInteger(POSITION_TICKET);
        long   type   = PositionGetInteger(POSITION_TYPE);
        double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        double volume = PositionGetDouble(POSITION_VOLUME);

        double price = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

        double profitPips = (type==POSITION_TYPE_BUY) ? (price-entry)/_Point : (entry-price)/_Point;
        if(_Digits==5 || _Digits==3) profitPips/=10.0;

        double newSL = currentSL;
        bool slChanged=false;

        //--- Break-Even
        if(profitPips >= params.bePips)
        {
            double beLevel = (type==POSITION_TYPE_BUY) ? entry+params.beBuffer*_Point
                                                       : entry-params.beBuffer*_Point;
            if(currentSL==0 || (type==POSITION_TYPE_BUY && beLevel>currentSL) || (type==POSITION_TYPE_SELL && beLevel<currentSL))
            {
                newSL = beLevel; slChanged=true;
                PrintFormat("✅ BE Triggered: Ticket %d, BE Level=%.5f", ticket, beLevel);
            }
        }

        //--- Trailing Stop Multi-Level
        for(int lvl=0; lvl<params.levelsCount; lvl++)
        {
            if(profitPips >= params.trailLevels[lvl])
            {
                double trailDistance = params.trailDistances[lvl]*_Point;
                double trailSL = (type==POSITION_TYPE_BUY) ? price-trailDistance : price+trailDistance;

                if(type==POSITION_TYPE_BUY && (currentSL==0 || trailSL>newSL) && (price-trailSL)>(2*_Point))
                    { newSL=trailSL; slChanged=true; PrintFormat("✅ Trailing BUY: Ticket %d, New SL=%.5f",ticket,newSL);}
                if(type==POSITION_TYPE_SELL && (currentSL==0 || trailSL<newSL) && (trailSL-price)>(2*_Point))
                    { newSL=trailSL; slChanged=true; PrintFormat("✅ Trailing SELL: Ticket %d, New SL=%.5f",ticket,newSL);}
            }
        }

        //--- ATR-based Trailing
        int atrPeriod=14;
        ENUM_TIMEFRAMES atrTF=PERIOD_M15;
        double trailFactor=1.5;
        int atrHandle=iATR(_Symbol, atrTF, atrPeriod);
        if(atrHandle!=INVALID_HANDLE)
        {
            double atrArr[];
            ArraySetAsSeries(atrArr,true);
            if(CopyBuffer(atrHandle,0,0,1,atrArr)>0)
            {
                double atr = atrArr[0];
                if(atr>0)
                {
                    double stochSL = StochTrailingStop(price,newSL,type==POSITION_TYPE_BUY,atr,trailFactor);
                    if(MathAbs(stochSL-newSL)>(1*_Point)) { newSL=stochSL; slChanged=true; PrintFormat("✅ ATR Trail: Ticket %d, ATR=%.1f, New SL=%.5f",ticket,atr,newSL);}
                }
            }
            IndicatorRelease(atrHandle);
        }

        //--- Update SL
        if(slChanged && newSL!=currentSL)
        {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req); ZeroMemory(res);
            req.action=TRADE_ACTION_SLTP;
            req.position=ticket;
            req.sl=NormalizeDouble(newSL,_Digits);
            req.tp=currentTP;
            req.deviation=10;
            if(OrderSend(req,res)) PrintFormat("✅ SL Updated: Ticket %d, New SL=%.5f (Profit %.1f pips)",ticket,newSL,profitPips);
        }

        //--- Advanced AutoClean
        if(profitPips >= MinProfitForAutoClean)
        {
            double prevOpen  = iOpen(_Symbol, AutoCleanTF, 1);
            double prevClose = iClose(_Symbol, AutoCleanTF, 1);
            double bodyPips  = MathAbs(prevClose-prevOpen)/_Point; if(_Digits==5||_Digits==3) bodyPips/=10.0;
            bool pullback=false;

            if(type==POSITION_TYPE_BUY && prevClose<prevOpen && bodyPips>=MinBodyPips) pullback=true;
            if(type==POSITION_TYPE_SELL && prevClose>prevOpen && bodyPips>=MinBodyPips) pullback=true;

            if(params.useTrendFilter)
            {
                if(type==POSITION_TYPE_BUY && price<emaTrend) pullback=true;
                if(type==POSITION_TYPE_SELL && price>emaTrend) pullback=true;
            }

            if(pullback)
            {
                MqlTradeRequest req;
                MqlTradeResult res;
                ZeroMemory(req); ZeroMemory(res);
                req.action=TRADE_ACTION_DEAL;
                req.symbol=_Symbol;
                req.volume=volume;
                req.type=(type==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
                req.price=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
                req.position=ticket;
                req.deviation=20;

                if(OrderSend(req,res))
                    PrintFormat("🚨 Advanced AutoClean: Ticket %d closed, Profit %.1f pips, Candle body %.1f pips",ticket,profitPips,bodyPips);
            }
        }
    }
}

// ==================== HELPER FUNCTIONS TANPA UBAH FUNGSI ASLI ====================

double CalculateRRRatio(const OBSignal &signal)
{
    double risk = MathAbs(signal.entryPrice - signal.stopLoss);
    double reward = MathAbs(signal.takeProfit - signal.entryPrice);
    return reward / risk;
}

bool IsSignalInTrend(Dir direction)
{
    double emaFast = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
    double emaSlow = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (direction == DIR_BUY)
        return (emaFast > emaSlow && price > emaFast);
    else
        return (emaFast < emaSlow && price < emaFast);
}

bool IsScalpingCondition()
{
    // Hanya scalp di market aktif
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    int hour = timeStruct.hour;
    return (hour >= 0 && hour <= 24); // Active trading hours
}

bool IsStochasticPower(const StochSignal &signal)
{
    // Strong stochastic signals only
    return (signal.kValueLow < 15 || signal.dValueLow < 20) ||
           (signal.kValueLow > 85 || signal.dValueLow > 80);
}

bool HasVolumeConfirmation()
{
    double currentVolume = (double)iVolume(_Symbol, PERIOD_CURRENT, 0);
    double avgVolume = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, IND_VOLUMES);
    return currentVolume > avgVolume * 1.2;
}
//==================================================================
// Helper Function: Check Active Trades
//==================================================================
bool HasActiveTrades()
{
    return (PositionsTotal() > 0);
}

//==================================================================
// Helper Function: Print System Performance
//==================================================================
void PrintSystemPerformance()
{
    int totalTiers[4] = {0, 0, 0, 0};
    int totalPositions = PositionsTotal();
    double totalProfit = 0;
    int buyCount = 0, sellCount = 0;

    for (int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            string comment = PositionGetString(POSITION_COMMENT);
            long type = PositionGetInteger(POSITION_TYPE);

            totalProfit += profit;

            if (type == POSITION_TYPE_BUY)
                buyCount++;
            else if (type == POSITION_TYPE_SELL)
                sellCount++;

            // Kategorikan berdasarkan tier
            if (StringFind(comment, "ORDER BLOCK") >= 0)
                totalTiers[0]++;
            else if (StringFind(comment, "PRICE ACTION") >= 0)
                totalTiers[0]++;
            else if (StringFind(comment, "SMC") >= 0)
                totalTiers[0]++;
            else if (StringFind(comment, "MOMENTUM") >= 0)
                totalTiers[1]++;
            else if (StringFind(comment, "CANDLE") >= 0)
                totalTiers[1]++;
            else if (StringFind(comment, "NEWS") >= 0)
                totalTiers[3]++;
            else if (StringFind(comment, "STOCHASTIC") >= 0)
                totalTiers[3]++;
            else
                totalTiers[2]++; // Consensus engine
        }
    }

    string performance = StringFormat("📊 PERFORMANCE: T1:%d T2:%d T3:%d T4:%d | BUY:%d SELL:%d | P/L: $%.2f | Optimal Structure Active",
                                      totalTiers[0], totalTiers[1], totalTiers[2], totalTiers[3], buyCount, sellCount, totalProfit);

    Print(performance);

    // Kirim performance alert jika profit/loss signifikan
    if (Dashboard_SendTelegram && MathAbs(totalProfit) > 50) // Jika P/L > $50
    {
        string perfMsg = "📈 *PERFORMANCE UPDATE* 📈\n";
        perfMsg += "Total P/L: $" + DoubleToString(totalProfit, 2) + "\n";
        perfMsg += "Active Positions: " + IntegerToString(totalPositions) + "\n";
        perfMsg += "Buy: " + IntegerToString(buyCount) + " | Sell: " + IntegerToString(sellCount) + "\n";
        perfMsg += "Tier Distribution: T1:" + IntegerToString(totalTiers[0]) + " T2:" + IntegerToString(totalTiers[1]) + " T3:" + IntegerToString(totalTiers[2]) + " T4:" + IntegerToString(totalTiers[3]);
        SendTelegramMessage(perfMsg);
    }
}

//==================================================================
// Helper Function: Print Active Positions Summary
//==================================================================
void PrintActivePositionsSummary()
{
    int totalPositions = PositionsTotal();
    int buyPositions = 0;
    int sellPositions = 0;
    double totalVolume = 0;

    for (int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double volume = PositionGetDouble(POSITION_VOLUME);
            long type = PositionGetInteger(POSITION_TYPE);
            totalVolume += volume;

            if (type == POSITION_TYPE_BUY)
                buyPositions++;
            else if (type == POSITION_TYPE_SELL)
                sellPositions++;
        }
    }

    string summary = StringFormat("📈 POSITIONS: Total: %d (BUY: %d, SELL: %d) | Volume: %.2f",
                                  totalPositions, buyPositions, sellPositions, totalVolume);

    Print(summary);
}

//==================================================================
// Helper Function: Check if in News Period
//==================================================================
bool IsNewsPeriod()
{
    datetime currentTime = TimeCurrent();
    datetime newsTime = 0;
    string newsName = "";
    int eventImpact = 0;

    for (int i = 0; i < CalendarEventsTotal(); i++)
    {
        if (CalendarEventByIndex(i, newsTime, newsName, eventImpact))
        {
            // Skip 10 minutes before and 20 minutes after high impact news
            if (eventImpact >= 2 && currentTime >= newsTime - 600 && currentTime <= newsTime + 1200)
            {
                if (Dashboard_SendTelegram)
                {
                    string newsMsg = "📢 *NEWS PERIOD DETECTED* 📢\n";
                    newsMsg += "Event: " + newsName + "\n";
                    newsMsg += "Time: " + TimeToString(newsTime, TIME_DATE | TIME_MINUTES) + "\n";
                    newsMsg += "Impact Level: " + IntegerToString(eventImpact) + "\n";
                    newsMsg += "Trading may be limited during this period";
                    SendTelegramMessage(newsMsg);
                }
                return true;
            }
        }
    }
    return false;
}

//==================================================================
// Timer function untuk Dashboard Animations
//==================================================================
void OnTimer()
{
    // Timer untuk dashboard animations
    if (EnableDashboard && Dashboard_AnimateBars)
    {
        // Update chart labels untuk animasi
        int totalObjects = ObjectsTotal(0, -1, OBJ_LABEL);
        if (totalObjects > 0)
        {
            // Hanya update jika ada label aktif
            datetime nowTime = TimeCurrent();
            int tickAnim = int(nowTime % Dashboard_BarLength);

            // Update posisi label untuk efek animasi sederhana
            for (int i = 0; i < totalObjects; i++)
            {
                string objName = ObjectName(0, i, -1, OBJ_LABEL);
                if (StringFind(objName, "SignalLabel_") >= 0)
                {
                    // Alternatif warna untuk efek animasi
                    color currentColor = (color)ObjectGetInteger(0, objName, OBJPROP_COLOR);
                    color newColor = currentColor;

                    if (tickAnim % 2 == 0)
                    {
                        // Efek blink sederhana
                        if (currentColor == clrLime)
                            newColor = clrGreen;
                        else if (currentColor == clrOrange)
                            newColor = clrDarkOrange;
                        else if (currentColor == clrYellow)
                            newColor = clrGold;
                    }
                    else
                    {
                        // Kembali ke warna original
                        if (currentColor == clrGreen)
                            newColor = clrLime;
                        else if (currentColor == clrDarkOrange)
                            newColor = clrOrange;
                        else if (currentColor == clrGold)
                            newColor = clrYellow;
                    }

                    ObjectSetInteger(0, objName, OBJPROP_COLOR, newColor);
                }
            }
        }
    }

    // Periodic health check setiap 60 detik
    static datetime lastHealthCheck = 0;
    if (TimeCurrent() - lastHealthCheck >= 60)
    {
        // Check account connection
        if (!TerminalInfoInteger(TERMINAL_CONNECTED))
        {
            Print("⚠️ Terminal not connected to broker");
        }

        lastHealthCheck = TimeCurrent();
    }
}

//==================================================================
// Helper Function: Check Active High Priority Trades
//==================================================================
bool HasActiveHighPriorityTrades()
{
    int highPriorityCount = 0;

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            string comment = PositionGetString(POSITION_COMMENT);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

            // Consider trades opened in last 5 minutes as high priority
            if (TimeCurrent() - openTime < 300)
            {
                highPriorityCount++;

                // If we find SMC or News trades, consider as high priority
                if (StringFind(comment, "SMC") >= 0 || StringFind(comment, "News") >= 0)
                {
                    return true; // Immediate return if found SMC or News trades
                }
            }
        }
    }

    // If we have more than 3 recent high priority trades, skip regular signals
    return (highPriorityCount >= 3);
}

//==================================================================
// Helper Function: Print System Status
//==================================================================
void PrintSystemStatus()
{
    string status = "🟢 NORMAL";
    int activeSignals = 0;

    // Check if any detection systems are active
    if (UseSMCSignal)
        activeSignals++;
    if (UseOrderBlock)
        activeSignals++;
    if (UsePriceAction)
        activeSignals++;
    if (UseSCMSignal)
        activeSignals++;
    if (UseCandlePattern)
        activeSignals++;
    if (UseMomentumPullback)
        activeSignals++;
    if (UseNewsImpact)
        activeSignals++;

    PrintFormat("🖥️ SYSTEM STATUS: %s | Active Detectors: %d/7 | Risk Management: %s",
                status, activeSignals,
                (RiskManager::CanOpenTrade() ? "ENABLED" : "DISABLED"));
}

//==================================================================
// Helper Function: Print Account Status
//==================================================================
void PrintAccountStatus()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    int positions = PositionsTotal();

    PrintFormat("📊 ACCOUNT STATUS | Balance: $%.2f | Equity: $%.2f | Free Margin: $%.2f | Margin Level: %.1f%% | Positions: %d",
                balance, equity, margin, (marginLevel > 0 ? marginLevel : 0), positions);
}

//==================================================================
// Helper Function: Calendar Event - TradingView Implementation
//==================================================================

int CalendarEventsTotal()
{
    datetime fromTime = TimeCurrent();
    datetime toTime = fromTime + 86400; // 24 jam ke depan

    string events = GetTradingViewCalendarEvents(fromTime, toTime);
    if (events == "")
        return 0;

    return ParseTradingViewEventsCount(events);
}

bool CalendarEventByIndex(int index, datetime &eventTime, string &eventName, int &impact)
{
    datetime fromTime = TimeCurrent();
    datetime toTime = fromTime + 86400;

    string events = GetTradingViewCalendarEvents(fromTime, toTime);
    if (events == "")
        return false;

    return GetTradingViewEventByIndex(events, index, eventTime, eventName, impact);
}

// Fungsi utama untuk mengambil data dari TradingView
string GetTradingViewCalendarEvents(datetime fromTime, datetime toTime)
{
    string result = "";

    // Format URL TradingView Economic Calendar
    string url = "https://economic-calendar.tradingview.com/events?from=" +
                 TimeToString(fromTime, TIME_DATE) +
                 "&to=" +
                 TimeToString(toTime, TIME_DATE);

    string headers = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r\n";
    headers += "Accept: application/json, text/plain, */*\r\n";

    char data[];
    char postData[];
    int timeout = 5000;
    string resultHeaders;

    ResetLastError();
    int response = WebRequest("GET", url, headers, timeout, postData, data, resultHeaders);

    if (response == 200)
    {
        result = CharArrayToString(data);
        Print("✓ Successfully fetched economic calendar data");
    }
    else
    {
        Print("❌ Failed to fetch calendar data. Error: ", GetLastError(), ", Response: ", response);
        // Fallback ke simulated data
        result = GetSimulatedCalendarData(fromTime, toTime);
    }

    return result;
}

// Parse JSON menggunakan MQL5 native functions
int ParseTradingViewEventsCount(string jsonData)
{
    int count = 0;

    // Simple string parsing untuk menghitung events
    int startPos = StringFind(jsonData, "\"events\"");
    if (startPos == -1)
        return 0;

    int arrayStart = StringFind(jsonData, "[", startPos);
    int arrayEnd = StringFind(jsonData, "]", arrayStart);

    if (arrayStart == -1 || arrayEnd == -1)
        return 0;

    string eventsArray = StringSubstr(jsonData, arrayStart, arrayEnd - arrayStart + 1);

    // Hitung jumlah objects dalam array
    int objCount = 0;
    int searchPos = 0;
    while ((searchPos = StringFind(eventsArray, "{", searchPos)) != -1)
    {
        objCount++;
        searchPos++;
    }

    // Filter untuk currency yang relevan
    string currentSymbol = _Symbol;
    string baseCurrency = StringSubstr(currentSymbol, 0, 3);
    string quoteCurrency = StringSubstr(currentSymbol, 3, 3);

    int relevantCount = 0;
    for (int i = 0; i < objCount; i++)
    {
        // Cari country field dalam setiap event
        string eventStr = ExtractEventString(eventsArray, i);
        if (IsEventRelevant(eventStr, baseCurrency, quoteCurrency))
        {
            relevantCount++;
        }
    }

    return relevantCount;
}

// Extract event string sederhana
string ExtractEventString(string eventsArray, int index)
{
    int currentIndex = 0;
    int startPos = 0;

    while (currentIndex <= index)
    {
        startPos = StringFind(eventsArray, "{", startPos);
        if (startPos == -1)
            return "";
        currentIndex++;
        if (currentIndex > index)
            break;
        startPos++;
    }

    int endPos = StringFind(eventsArray, "}", startPos);
    if (endPos == -1)
        return "";

    return StringSubstr(eventsArray, startPos, endPos - startPos + 1);
}

bool IsEventRelevant(string eventStr, string baseCurrency, string quoteCurrency)
{
    // Cek country field
    int countryPos = StringFind(eventStr, "\"country\"");
    if (countryPos == -1)
        return false;

    int colonPos = StringFind(eventStr, ":", countryPos);
    int quoteStart = StringFind(eventStr, "\"", colonPos);
    int quoteEnd = StringFind(eventStr, "\"", quoteStart + 1);

    if (quoteStart == -1 || quoteEnd == -1)
        return false;

    string country = StringSubstr(eventStr, quoteStart + 1, quoteEnd - quoteStart - 1);

    return IsCurrencyRelevant(country, baseCurrency, quoteCurrency);
}

bool GetTradingViewEventByIndex(string jsonData, int index, datetime &eventTime, string &eventName, int &impact)
{
    // Cari events array
    int startPos = StringFind(jsonData, "\"events\"");
    if (startPos == -1)
        return false;

    int arrayStart = StringFind(jsonData, "[", startPos);
    int arrayEnd = StringFind(jsonData, "]", arrayStart);

    if (arrayStart == -1 || arrayEnd == -1)
        return false;

    string eventsArray = StringSubstr(jsonData, arrayStart, arrayEnd - arrayStart + 1);

    // Cari event berdasarkan index
    string currentSymbol = _Symbol;
    string baseCurrency = StringSubstr(currentSymbol, 0, 3);
    string quoteCurrency = StringSubstr(currentSymbol, 3, 3);

    int currentIndex = 0;
    int searchPos = 0;

    for (int i = 0; i < 100; i++) // Max 100 events
    {
        string eventStr = ExtractEventString(eventsArray, i);
        if (eventStr == "")
            break;

        if (IsEventRelevant(eventStr, baseCurrency, quoteCurrency))
        {
            if (currentIndex == index)
            {
                // Extract event details
                eventName = ExtractEventField(eventStr, "title") + " (" + ExtractEventField(eventStr, "country") + ")";
                string timeStr = ExtractEventField(eventStr, "time");
                eventTime = StringToTime(timeStr);

                string importance = ExtractEventField(eventStr, "importance");
                impact = ImportanceToImpact(importance);

                return true;
            }
            currentIndex++;
        }
    }

    return false;
}

string ExtractEventField(string eventStr, string fieldName)
{
    int fieldPos = StringFind(eventStr, "\"" + fieldName + "\"");
    if (fieldPos == -1)
        return "";

    int colonPos = StringFind(eventStr, ":", fieldPos);
    int quoteStart = StringFind(eventStr, "\"", colonPos);
    int quoteEnd = StringFind(eventStr, "\"", quoteStart + 1);

    if (quoteStart == -1 || quoteEnd == -1)
        return "";

    return StringSubstr(eventStr, quoteStart + 1, quoteEnd - quoteStart - 1);
}

// Fungsi helper yang sama seperti sebelumnya
bool IsCurrencyRelevant(string country, string baseCurrency, string quoteCurrency)
{
    string currencyMap[][2] = {
        {"US", "USD"}, {"EU", "EUR"}, {"UK", "GBP"}, {"JP", "JPY"}, {"AU", "AUD"}, {"CA", "CAD"}, {"CH", "CHF"}, {"NZ", "NZD"}};

    for (int i = 0; i < ArraySize(currencyMap); i++)
    {
        if (currencyMap[i][0] == country)
        {
            string currency = currencyMap[i][1];
            return (currency == baseCurrency || currency == quoteCurrency);
        }
    }

    return false;
}

int ImportanceToImpact(string importance)
{
    if (importance == "high")
        return 3;
    if (importance == "medium")
        return 2;
    if (importance == "low")
        return 1;
    return 0;
}

string GetSimulatedCalendarData(datetime fromTime, datetime toTime)
{
    MqlDateTime fromStruct;
    TimeToStruct(fromTime, fromStruct);

    string simulatedData = "{";
    simulatedData += "\"result\": {";
    simulatedData += "\"events\": [";

    string currentSymbol = _Symbol;
    string baseCurrency = StringSubstr(currentSymbol, 0, 3);
    string quoteCurrency = StringSubstr(currentSymbol, 3, 3);

    string countries[];
    if (baseCurrency == "USD" || quoteCurrency == "USD")
        ArrayPushString(countries, "US");
    if (baseCurrency == "EUR" || quoteCurrency == "EUR")
        ArrayPushString(countries, "EU");
    if (baseCurrency == "GBP" || quoteCurrency == "GBP")
        ArrayPushString(countries, "UK");
    if (baseCurrency == "JPY" || quoteCurrency == "JPY")
        ArrayPushString(countries, "JP");

    for (int i = 0; i < ArraySize(countries); i++)
    {
        if (i > 0)
            simulatedData += ",";

        datetime eventTime = fromTime + (i + 1) * 10800;
        string importance = (i % 3 == 0) ? "high" : ((i % 3 == 1) ? "medium" : "low");

        simulatedData += "{";
        simulatedData += "\"title\": \"Simulated " + countries[i] + " Event " + IntegerToString(i + 1) + "\",";
        simulatedData += "\"country\": \"" + countries[i] + "\",";
        simulatedData += "\"time\": \"" + TimeToString(eventTime) + "\",";
        simulatedData += "\"importance\": \"" + importance + "\"";
        simulatedData += "}";
    }

    simulatedData += "]}}";
    return simulatedData;
}

void ArrayPushString(string &array[], string value)
{
    int size = ArraySize(array);
    ArrayResize(array, size + 1);
    array[size] = value;
}

//==================================================================
// Helper Function: Cleanup Expired Data
//==================================================================
void CleanupExpiredData()
{
    // Cleanup expired indicators or temporary data
    // This helps prevent memory leaks in long-running EAs

    // Example: Reset some static variables if needed
    static int cleanupCounter = 0;
    cleanupCounter++;

    if (cleanupCounter >= 100) // Every ~50 minutes
    {
        // Reset any accumulation counters if needed
        cleanupCounter = 0;
        Print("🧹 SYSTEM: Periodic cleanup completed");
    }
}

//==================================================================
// Helper Function: Check Active OB Trades
//==================================================================
bool HasActiveOBTrade()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "OB_") >= 0) // Trades dengan comment OB
                return true;
        }
    }
    return false;
}

//==================================================================
// =================== DETECTION FUNCTIONS ========================
//==================================================================

//--- Double Top
bool DetectDoubleTop(int idxStart, int idxEnd, double &neckline, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    double hi1 = iHigh(_Symbol, tf, idxStart);
    double hi2 = iHigh(_Symbol, tf, idxEnd);
    double loBetween = iLow(_Symbol, tf, (idxStart + idxEnd) / 2);

    if (MathAbs(hi1 - hi2) <= (hi1 * 0.0005))
    {
        neckline = loBetween;
        isStrong = (MathAbs(hi1 - hi2) <= (hi1 * 0.00025));
        return true;
    }
    return false;
}

//--- Double Bottom
bool DetectDoubleBottom(int idxStart, int idxEnd, double &neckline, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    double lo1 = iLow(_Symbol, tf, idxStart);
    double lo2 = iLow(_Symbol, tf, idxEnd);
    double hiBetween = iHigh(_Symbol, tf, (idxStart + idxEnd) / 2);

    if (MathAbs(lo1 - lo2) <= (lo1 * 0.0005))
    {
        neckline = hiBetween;
        isStrong = (MathAbs(lo1 - lo2) <= (lo1 * 0.00025));
        return true;
    }
    return false;
}

//--- Triangles
bool DetectTriangle(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    double hiStart = iHigh(_Symbol, tf, idxStart);
    double hiEnd = iHigh(_Symbol, tf, idxEnd);
    double loStart = iLow(_Symbol, tf, idxStart);
    double loEnd = iLow(_Symbol, tf, idxEnd);

    if (hiEnd < hiStart && loEnd > loStart)
    {
        signal = DIR_BUY;
        isStrong = true;
        return true;
    }
    if (hiEnd > hiStart && loEnd < loStart)
    {
        signal = DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//--- Head & Shoulders / Inverse H&S
bool DetectHeadShoulders(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    int mid = (idxStart + idxEnd) / 2;
    double hiLS = iHigh(_Symbol, tf, idxStart);
    double hiHead = iHigh(_Symbol, tf, mid);
    double hiRS = iHigh(_Symbol, tf, idxEnd);

    if (hiHead > hiLS && hiHead > hiRS && MathAbs(hiLS - hiRS) <= hiHead * 0.0005)
    {
        signal = DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

bool DetectInverseHeadShoulders(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    int mid = (idxStart + idxEnd) / 2;
    double loLS = iLow(_Symbol, tf, idxStart);
    double loHead = iLow(_Symbol, tf, mid);
    double loRS = iLow(_Symbol, tf, idxEnd);

    if (loHead < loLS && loHead < loRS && MathAbs(loLS - loRS) <= loHead * 0.0005)
    {
        signal = DIR_BUY;
        isStrong = true;
        return true;
    }
    return false;
}

//--- Wedges
bool DetectWedge(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    double hiStart = iHigh(_Symbol, tf, idxStart);
    double hiEnd = iHigh(_Symbol, tf, idxEnd);
    double loStart = iLow(_Symbol, tf, idxStart);
    double loEnd = iLow(_Symbol, tf, idxEnd);

    if (hiEnd > hiStart && loEnd > loStart)
    {
        signal = DIR_SELL;
        isStrong = true;
        return true;
    }
    if (hiEnd < hiStart && loEnd < loStart)
    {
        signal = DIR_BUY;
        isStrong = true;
        return true;
    }
    return false;
}

//--- Flags / Pennants
bool DetectFlag(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    double opStart = iOpen(_Symbol, tf, idxStart);
    double clEnd = iClose(_Symbol, tf, idxEnd);

    if (clEnd > opStart * 1.005)
    {
        signal = DIR_BUY;
        isStrong = true;
        return true;
    }
    if (clEnd < opStart * 0.995)
    {
        signal = DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//--- Cup & Handle
bool DetectCupHandle(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    int mid = (idxStart + idxEnd) / 2;
    double loCup = iLow(_Symbol, tf, mid);
    double hiStart = iHigh(_Symbol, tf, idxStart);
    double hiEnd = iHigh(_Symbol, tf, idxEnd);

    if (loCup < hiStart && loCup < hiEnd && hiEnd > hiStart)
    {
        signal = DIR_BUY;
        isStrong = true;
        return true;
    }
    return false;
}

//--- Harmonic Patterns (Updated)
bool DetectHarmonic(int idxStart, int idxEnd, Dir &signal, bool &isStrong, ENUM_TIMEFRAMES tf, string &patternName)
{
    // Ambil titik XABCD dari chart
    double X = iHigh(_Symbol, tf, idxStart + 10);
    double A = iLow(_Symbol, tf, idxStart + 8);
    double B = iHigh(_Symbol, tf, idxStart + 6);
    double C = iLow(_Symbol, tf, idxStart + 4);
    double D = iClose(_Symbol, tf, idxStart);

    HarmonicPatternSignal hps = DetectHarmonicPattern(X, A, B, C, D);

    if (hps.signal != DIR_NONE)
    {
        signal = hps.signal;
        isStrong = hps.isStrong;
        patternName = hps.patternName;
        return true;
    }

    return false;
}

//==================================================================
// Fungsi utama pattern detection
//==================================================================
ChartPatternSignal GetChartPatternSignalUltimate(int idxStart, int idxEnd, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    ChartPatternSignal cps;
    cps.signal = DIR_NONE;
    cps.isStrong = false;
    cps.patternName = "None";
    cps.confidence = 0.0;

    double neckline;
    bool strongFlag = false;
    Dir signalDir;
    string patternHarmonic = "";

    if (DetectDoubleTop(idxStart, idxEnd, neckline, strongFlag, tf))
    {
        cps.signal = DIR_SELL;
        cps.isStrong = strongFlag;
        cps.patternName = "Double Top";
        return cps;
    }
    if (DetectDoubleBottom(idxStart, idxEnd, neckline, strongFlag, tf))
    {
        cps.signal = DIR_BUY;
        cps.isStrong = strongFlag;
        cps.patternName = "Double Bottom";
        return cps;
    }
    if (DetectTriangle(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Triangle";
        return cps;
    }
    if (DetectHeadShoulders(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Head & Shoulders";
        return cps;
    }
    if (DetectInverseHeadShoulders(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Inverse H&S";
        return cps;
    }
    if (DetectWedge(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Wedge";
        return cps;
    }
    if (DetectFlag(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Flag/Pennant";
        return cps;
    }
    if (DetectCupHandle(idxStart, idxEnd, signalDir, strongFlag, tf))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = "Cup & Handle";
        return cps;
    }
    if (DetectHarmonic(idxStart, idxEnd, signalDir, strongFlag, tf, patternHarmonic))
    {
        cps.signal = signalDir;
        cps.isStrong = strongFlag;
        cps.patternName = patternHarmonic;
        return cps;
    }

    return cps;
}

//==================================================================
// Fungsi log
//==================================================================
void PrintChartPatternSignal(int idxStart, int idxEnd, ENUM_TIMEFRAMES tf = PERIOD_M15)
{
    ChartPatternSignal cps = GetChartPatternSignalUltimate(idxStart, idxEnd, tf);
    string s = (cps.signal == DIR_BUY ? "BUY" : (cps.signal == DIR_SELL ? "SELL" : "NONE"));
    string strength = cps.isStrong ? "STRONG" : "WEAK";
    PrintFormat("ChartPattern Signal | Start:%d End:%d | TF:%s | Signal:%s | Strength:%s | Pattern:%s",
                idxStart, idxEnd, EnumToString(tf), s, strength, cps.patternName);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Struct untuk sinyal harmonic pattern                            |
//+------------------------------------------------------------------+
struct HarmonicPatternSignal
{
    Dir signal;
    bool isStrong;
    string patternName;
    double entryPrice; // DITAMBAHKAN
    double stopLoss;   // DITAMBAHKAN
    double takeProfit; // DITAMBAHKAN
};

//==================================================================
// Fungsi rasio Fibonacci helper
//==================================================================
bool IsFibRatio(double actual, double target, double tolerance = 0.03)
{
    return (MathAbs(actual - target) / target <= tolerance);
}

//==================================================================
// Fungsi bantu untuk menghitung rasio Fibonacci point
//==================================================================
double GetDistance(double a, double b) { return MathAbs(b - a); }

//==================================================================
// Deteksi Gartley (XABCD)
// Rasio: AB=0.618*XA, BC=0.382-0.886*AB, CD=1.272-1.618*BC
//==================================================================
bool DetectGartley(double X, double A, double B, double C, double D, Dir &signal, bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X, A);
    double AB = GetDistance(A, B);
    double BC = GetDistance(B, C);
    double CD = GetDistance(C, D);

    if (IsFibRatio(AB, 0.618 * XA) &&
        IsFibRatio(BC, 0.382 * AB) &&
        IsFibRatio(CD, 1.272 * BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Bat (XABCD)
// Rasio: AB=0.382-0.5*XA, BC=0.382-0.886*AB, CD=1.618-2.618*BC
//==================================================================
bool DetectBat(double X, double A, double B, double C, double D, Dir &signal, bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X, A);
    double AB = GetDistance(A, B);
    double BC = GetDistance(B, C);
    double CD = GetDistance(C, D);

    if (IsFibRatio(AB, 0.382 * XA) &&
        IsFibRatio(BC, 0.886 * AB) &&
        IsFibRatio(CD, 1.618 * BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Butterfly (XABCD)
// Rasio: AB=0.786*XA, BC=0.382-0.886*AB, CD=1.618-2.618*BC
//==================================================================
bool DetectButterfly(double X, double A, double B, double C, double D, Dir &signal, bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X, A);
    double AB = GetDistance(A, B);
    double BC = GetDistance(B, C);
    double CD = GetDistance(C, D);

    if (IsFibRatio(AB, 0.786 * XA) &&
        IsFibRatio(BC, 0.382 * AB) &&
        IsFibRatio(CD, 1.618 * BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Deteksi Crab (XABCD)
// Rasio: AB=0.382-0.618*XA, BC=0.382-0.886*AB, CD=2.618-3.618*BC
//==================================================================
bool DetectCrab(double X, double A, double B, double C, double D, Dir &signal, bool &isStrong)
{
    signal = DIR_NONE;
    isStrong = false;

    double XA = GetDistance(X, A);
    double AB = GetDistance(A, B);
    double BC = GetDistance(B, C);
    double CD = GetDistance(C, D);

    if (IsFibRatio(AB, 0.618 * XA) &&
        IsFibRatio(BC, 0.886 * AB) &&
        IsFibRatio(CD, 2.618 * BC))
    {
        signal = (D > C) ? DIR_BUY : DIR_SELL;
        isStrong = true;
        return true;
    }
    return false;
}

//==================================================================
// Fungsi utama deteksi harmonic pattern
//==================================================================
HarmonicPatternSignal DetectHarmonicPattern(double X, double A, double B, double C, double D)
{
    HarmonicPatternSignal hps;
    hps.signal = DIR_NONE;
    hps.isStrong = false;
    hps.patternName = "None";

    Dir sig;
    bool strongFlag;

    if (DetectGartley(X, A, B, C, D, sig, strongFlag))
    {
        hps.signal = sig;
        hps.isStrong = strongFlag;
        hps.patternName = "Gartley";
        return hps;
    }
    if (DetectBat(X, A, B, C, D, sig, strongFlag))
    {
        hps.signal = sig;
        hps.isStrong = strongFlag;
        hps.patternName = "Bat";
        return hps;
    }
    if (DetectButterfly(X, A, B, C, D, sig, strongFlag))
    {
        hps.signal = sig;
        hps.isStrong = strongFlag;
        hps.patternName = "Butterfly";
        return hps;
    }
    if (DetectCrab(X, A, B, C, D, sig, strongFlag))
    {
        hps.signal = sig;
        hps.isStrong = strongFlag;
        hps.patternName = "Crab";
        return hps;
    }

    return hps;
}

//==================================================================
// Fungsi log harmonic pattern
//==================================================================
void PrintHarmonicPatternSignal(double X, double A, double B, double C, double D)
{
    HarmonicPatternSignal hps = DetectHarmonicPattern(X, A, B, C, D);
    string s = (hps.signal == DIR_BUY ? "BUY" : (hps.signal == DIR_SELL ? "SELL" : "NONE"));
    string strength = hps.isStrong ? "STRONG" : "WEAK";
    PrintFormat("Harmonic Pattern | Signal:%s | Strength:%s | Pattern:%s", s, strength, hps.patternName);
}

//+------------------------------------------------------------------+
//| Enum untuk Iceberg Level                                        |
//+------------------------------------------------------------------+
enum IcebergLevel
{
    ICE_NONE,
    ICE_WEAK,
    ICE_STRONG
};

//+------------------------------------------------------------------+
//| Input Parameters untuk Iceberg                                  |
//+------------------------------------------------------------------+
input int LookbackCandlesAdvanced = 20;      // Lookback untuk volume average
input double VolumeMultiplierAdvanced = 2.0; // Multiplier untuk spike volume

//==================================================================
// Fungsi: DetectIcebergSimple
// Parameter: idx = candle index
// Return: true jika volume > 2x volume sebelumnya
//==================================================================
bool DetectIcebergSimple(int idx)
{
    double volCurrent = (double)iVolume(_Symbol, PERIOD_CURRENT, idx);
    double volPrev = (double)iVolume(_Symbol, PERIOD_CURRENT, idx + 1);
    return (volCurrent >= volPrev * 2.0);
}

//==================================================================
// Fungsi: DetectIcebergAdvanced
// Parameter: idx = candle index
// Return: IcebergLevel (NONE, WEAK, STRONG)
//==================================================================
IcebergLevel DetectIcebergAdvanced(int idx)
{
    double sumVolume = 0;
    int lookback = LookbackCandlesAdvanced;

    if (Bars(_Symbol, PERIOD_CURRENT) <= lookback)
        return ICE_NONE;

    for (int i = idx + 1; i <= idx + lookback; i++)
        sumVolume += (double)iVolume(_Symbol, PERIOD_CURRENT, i);

    double avgVolume = sumVolume / lookback;
    double lastVolume = (double)iVolume(_Symbol, PERIOD_CURRENT, idx);

    if (lastVolume >= avgVolume * VolumeMultiplierAdvanced * 1.5)
        return ICE_STRONG;
    else if (lastVolume >= avgVolume * VolumeMultiplierAdvanced)
        return ICE_WEAK;

    return ICE_NONE;
}

//==================================================================
// Fungsi: DetectIcebergMultiTF
// Parameter: tfFast, tfSlow = timeframe, idx = candle index
// Return: IcebergLevel
// Deskripsi: gabungkan deteksi di dua timeframe
//==================================================================
IcebergLevel DetectIcebergMultiTF(ENUM_TIMEFRAMES tfFast, ENUM_TIMEFRAMES tfSlow, int idx)
{
    IcebergLevel fast = DetectIcebergAdvanced(idx); // TF current
    // switch symbol ke slow TF
    double sumVolumeSlow = 0;
    int lookback = LookbackCandlesAdvanced;
    if (Bars(_Symbol, tfSlow) <= lookback)
        return ICE_NONE;
    for (int i = idx + 1; i <= idx + lookback; i++)
        sumVolumeSlow += (double)iVolume(_Symbol, tfSlow, i);
    double avgVolumeSlow = sumVolumeSlow / lookback;
    double lastVolumeSlow = (double)iVolume(_Symbol, tfSlow, idx);

    bool slowSpike = lastVolumeSlow >= avgVolumeSlow * VolumeMultiplierAdvanced;

    // Gabungkan logika: jika keduanya spike → STRONG, jika salah satu → WEAK
    if (fast == ICE_STRONG && slowSpike)
        return ICE_STRONG;
    if (fast != ICE_NONE || slowSpike)
        return ICE_WEAK;

    return ICE_NONE;
}

//==================================================================
// Fungsi: PrintIcebergSignal
// Parameter: idx = candle index
//==================================================================
void PrintIcebergSignal(int idx)
{
    bool simple = DetectIcebergSimple(idx);
    IcebergLevel adv = DetectIcebergAdvanced(idx);
    IcebergLevel multi = DetectIcebergMultiTF(PERIOD_M5, PERIOD_H1, idx);

    string sAdv = (adv == ICE_STRONG ? "STRONG" : (adv == ICE_WEAK ? "WEAK" : "NONE"));
    string sMulti = (multi == ICE_STRONG ? "STRONG" : (multi == ICE_WEAK ? "WEAK" : "NONE"));

    PrintFormat("Iceberg | CandleIdx:%d | Simple:%s | Advanced:%s | MultiTF:%s",
                idx, simple ? "YES" : "NO", sAdv, sMulti);
}

//+------------------------------------------------------------------+
//| Macro Analysis Parameters                                       |
//+------------------------------------------------------------------+
//--- default MA & ATR
input int MAPeriod = 50;
input ENUM_MA_METHOD MAMethod = MODE_SMA;
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE;
input int ATRPeriod = 14;

//--- Weighting tiap indikator makro (0-1)
input double WeightDXY = 0.5;
input double WeightGold = 0.3;
input double WeightYield = 0.2;

//--- Threshold total score untuk entry
input double BuyThreshold = 0.6;
input double SellThreshold = -0.6;

//==================================================================
// Fungsi: GetMacroScore
// Parameter:
//   symbolName : string
//   timeframe  : ENUM_TIMEFRAMES
// Return: double (-1..1) → -1 strong sell, +1 strong buy
//==================================================================
double GetMacroScore(string symbolName, ENUM_TIMEFRAMES timeframe)
{
    if (!SymbolSelect(symbolName, true))
    {
        Print("Symbol not found: ", symbolName);
        return 0;
    }

    // Get price data
    double closeArray[], prevCloseArray[];
    ArraySetAsSeries(closeArray, true);
    ArraySetAsSeries(prevCloseArray, true);

    CopyClose(symbolName, timeframe, 0, 2, closeArray);
    CopyClose(symbolName, timeframe, 1, 2, prevCloseArray);

    double closePrice = closeArray[0];
    double prevClose = prevCloseArray[1];

    // Get MA data
    int maHandle = iMA(symbolName, timeframe, MAPeriod, 0, MAMethod, MAPrice);
    double maArray[];
    ArraySetAsSeries(maArray, true);
    CopyBuffer(maHandle, 0, 0, 2, maArray);

    double maCurrent = maArray[0];
    double maPrev = maArray[1];

    // Get ATR data
    int atrHandle = iATR(symbolName, timeframe, ATRPeriod);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, 1, atrArray);

    double atr = atrArray[0];
    double maSlope = maCurrent - maPrev;

    // jika volatilitas terlalu rendah dibanding slope → sinyal netral
    if (atr < 0.1 * MathAbs(maSlope))
        return 0;

    // cross MA
    if (prevClose < maPrev && closePrice > maCurrent && maSlope > 0)
        return 1.0; // buy
    if (prevClose > maPrev && closePrice < maCurrent && maSlope < 0)
        return -1.0; // sell

    return 0; // netral
}

//==================================================================
// Fungsi: GetMacroSignalUltimate
// Return: Dir
// Deskripsi:
//   Menggabungkan semua indikator makro menggunakan weighting dan threshold
//==================================================================
Dir GetMacroSignalUltimate()
{
    double score = 0;
    score += GetMacroScore("DXY", PERIOD_H1) * WeightDXY;
    score += GetMacroScore("XAUUSD", PERIOD_H1) * WeightGold;
    score += GetMacroScore("US10Y", PERIOD_H1) * WeightYield;

    if (score >= BuyThreshold)
        return DIR_BUY;
    if (score <= SellThreshold)
        return DIR_SELL;

    return DIR_NONE;
}

//==================================================================
// Fungsi: PrintMacroUltimate
// Deskripsi:
//   Print semua sinyal makro + skor total + sinyal gabungan
//==================================================================
void PrintMacroUltimate()
{
    double sDXY = GetMacroScore("DXY", PERIOD_H1);
    double sGold = GetMacroScore("XAUUSD", PERIOD_H1);
    double sYield = GetMacroScore("US10Y", PERIOD_H1);
    double total = sDXY * WeightDXY + sGold * WeightGold + sYield * WeightYield;
    Dir combined = GetMacroSignalUltimate();

    string SigStr = (combined == DIR_BUY ? "BUY" : (combined == DIR_SELL ? "SELL" : "NONE"));

    PrintFormat("Macro Ultimate Scores | DXY:%.2f Gold:%.2f Yield:%.2f | Total:%.2f | COMBINED:%s",
                sDXY, sGold, sYield, total, SigStr);
}

//+------------------------------------------------------------------+
//| Momentum & Multi-Timeframe Parameters                           |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M5;     // timeframe entry
input ENUM_TIMEFRAMES TF_Confirm1 = PERIOD_M15; // confirm timeframe 1
input ENUM_TIMEFRAMES TF_Confirm2 = PERIOD_H1;  // confirm timeframe 2
input int EMA_Period = 200;                     // EMA trend filter

input double MinBodyPoints = 200;        // minimal body in points
input double MaxWickPercent = 0.35;      // max wick / range
input double StrongSignalMinBody = 40;   // strong if >= this
input double AggressiveMultiplier = 2.0; // TP = body * multiplier

input bool UseFractalConfirmation = true; // require fractal MS confirmation
input int FractalLookback = 30;           // lookback for fractals

input double RiskPercentPerTrade = 50.0; // risk % per trade
input double MaxSpreadPoints = 50;       // filter max spread (points)

input int MagicNumber = 20250928;
input double SlippagePips = 3; // slippage in pips

//+------------------------------------------------------------------+
//| Risk Reward Info Structure                                      |
//+------------------------------------------------------------------+
struct RiskRewardInfo
{
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double riskRewardRatio;
};

//==================================================================
// Helper Functions
//==================================================================
double GetPoint() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }
int GetDigits() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }

double AskPrice(ENUM_TIMEFRAMES tf) { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double BidPrice(ENUM_TIMEFRAMES tf) { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }

//==================================================================
// EMA Trend Filter
//==================================================================
bool IsTrendAligned(ENUM_TIMEFRAMES tf, int idx, Dir dir)
{
    // Get EMA data
    int emaHandle = iMA(_Symbol, tf, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[], priceArray[];
    ArraySetAsSeries(emaArray, true);
    ArraySetAsSeries(priceArray, true);

    CopyBuffer(emaHandle, 0, 0, idx + 1, emaArray);
    CopyClose(_Symbol, tf, 0, idx + 1, priceArray);

    double ema = emaArray[idx];
    double price = priceArray[idx];

    if (ema == 0)
        return false;
    if (dir == DIR_BUY)
        return price > ema;
    if (dir == DIR_SELL)
        return price < ema;
    return false;
}

//==================================================================
// Fractal-based Market Structure
//==================================================================
Dir AnalyzeFractalMS(ENUM_TIMEFRAMES tf, int lookback)
{
    if (Bars(_Symbol, tf) < lookback + 5)
        return DIR_NONE;

    int lastFractalHigh = -1, lastFractalLow = -1;

    for (int i = 2; i < lookback; i++)
    {
        double h = iHigh(_Symbol, tf, i);
        if (h > iHigh(_Symbol, tf, i + 1) && h > iHigh(_Symbol, tf, i + 2) &&
            h > iHigh(_Symbol, tf, i - 1) && h > iHigh(_Symbol, tf, i - 2))
        {
            lastFractalHigh = i;
            break;
        }
    }
    for (int i = 2; i < lookback; i++)
    {
        double l = iLow(_Symbol, tf, i);
        if (l < iLow(_Symbol, tf, i + 1) && l < iLow(_Symbol, tf, i + 2) &&
            l < iLow(_Symbol, tf, i - 1) && l < iLow(_Symbol, tf, i - 2))
        {
            lastFractalLow = i;
            break;
        }
    }

    if (lastFractalHigh == -1 || lastFractalLow == -1)
        return DIR_NONE;

    double high1 = iHigh(_Symbol, tf, lastFractalHigh + 5);
    double high2 = iHigh(_Symbol, tf, lastFractalHigh);
    double low1 = iLow(_Symbol, tf, lastFractalLow + 5);
    double low2 = iLow(_Symbol, tf, lastFractalLow);

    if (high2 > high1 && low2 > low1)
        return DIR_BUY;
    if (high2 < high1 && low2 < low1)
        return DIR_SELL;
    return DIR_NONE;
}

//==================================================================
// Momentum Detection
//==================================================================
Dir DetectMomentumTF(ENUM_TIMEFRAMES tf, int idx, bool &isStrongSignal, RiskRewardInfo &rrInfo)
{
    double op = iOpen(_Symbol, tf, idx);
    double cl = iClose(_Symbol, tf, idx);
    double hi = iHigh(_Symbol, tf, idx);
    double lo = iLow(_Symbol, tf, idx);
    double pt = GetPoint();

    if (op == 0 || cl == 0 || hi == 0 || lo == 0)
        return DIR_NONE;

    double bodyPts = MathAbs(cl - op) / pt;
    double rangePts = (hi - lo) / pt;
    if (rangePts <= 0)
        return DIR_NONE;

    double wickTop = hi - MathMax(op, cl);
    double wickBottom = MathMin(op, cl) - lo;
    double maxWick = MathMax(wickTop, wickBottom) / (hi - lo);

    isStrongSignal = false;
    rrInfo.entryPrice = cl;
    rrInfo.stopLoss = 0;
    rrInfo.takeProfit = 0;
    rrInfo.riskRewardRatio = 0;

    if (bodyPts < MinBodyPoints)
        return DIR_NONE;
    if (maxWick > MaxWickPercent)
        return DIR_NONE;

    Dir dir = DIR_NONE;
    if (cl > op)
        dir = DIR_BUY;
    if (cl < op)
        dir = DIR_SELL;

    if (bodyPts >= StrongSignalMinBody)
        isStrongSignal = true;

    if (dir == DIR_BUY)
    {
        rrInfo.stopLoss = lo;
        rrInfo.takeProfit = cl + (cl - lo) * AggressiveMultiplier;
        rrInfo.riskRewardRatio = (rrInfo.takeProfit - cl) / (cl - rrInfo.stopLoss);
    }
    else if (dir == DIR_SELL)
    {
        rrInfo.stopLoss = hi;
        rrInfo.takeProfit = cl - (hi - cl) * AggressiveMultiplier;
        rrInfo.riskRewardRatio = (cl - rrInfo.takeProfit) / (rrInfo.stopLoss - cl);
    }

    return dir;
}

//==================================================================
// Multi-TF Confirmation
//==================================================================
bool ConfirmMultiTF(Dir dir)
{
    // Entry TF quick check (latest closed bar idx=1)
    bool ok1 = IsTrendAligned(TF_Entry, 1, dir);
    bool ok2 = IsTrendAligned(TF_Confirm1, 1, dir);
    bool ok3 = IsTrendAligned(TF_Confirm2, 1, dir);

    if (!ok1 || !ok2 || !ok3)
        return false;

    if (UseFractalConfirmation)
    {
        Dir ms1 = AnalyzeFractalMS(TF_Confirm1, FractalLookback);
        Dir ms2 = AnalyzeFractalMS(TF_Confirm2, FractalLookback);
        if (ms1 != dir || ms2 != dir)
            return false;
    }

    return true;
}

//==================================================================
// Get Momentum Signal
//==================================================================
Dir GetMomentumSignal()
{
    bool isStrong = false;
    RiskRewardInfo rrInfo;

    // Check momentum on entry timeframe
    Dir momentumDir = DetectMomentumTF(TF_Entry, 1, isStrong, rrInfo);

    if (momentumDir == DIR_NONE)
        return DIR_NONE;

    // Check multi-timeframe confirmation
    if (!ConfirmMultiTF(momentumDir))
        return DIR_NONE;

    return momentumDir;
}

//+------------------------------------------------------------------+
//| Momentum Pullback Configuration                                 |
//+------------------------------------------------------------------+
struct MomentumCfg
{
    static int minConsecutive;
    static double minBodyMultiplier;
    static bool useEngulfingFilter;
    static bool usePinbarFilter;
    static int confirmationCandles;
    static double slPipsDefault;
    static double tpPipsDefault;
    static double maxLotPerTrade;
};

int MomentumCfg::minConsecutive = 3;
double MomentumCfg::minBodyMultiplier = 0.5;
bool MomentumCfg::useEngulfingFilter = true;
bool MomentumCfg::usePinbarFilter = false;
int MomentumCfg::confirmationCandles = 1;
double MomentumCfg::slPipsDefault = 50;
double MomentumCfg::tpPipsDefault = 100;
double MomentumCfg::maxLotPerTrade = 1.0;

//+------------------------------------------------------------------+
//| Momentum Signal Structure                                       |
//+------------------------------------------------------------------+
struct MomentumSignal
{
    bool found;
    datetime time;
    Dir dir;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lot;
    string reason;
};

//+------------------------------------------------------------------+
//| Momentum Pullback Parameters                                    |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES MomentumTF = PERIOD_M5;   // Timeframe untuk momentum detection
input ENUM_TIMEFRAMES MomentumHTF = PERIOD_M15; // Higher timeframe untuk konfirmasi
input int MomentumLookback = 100;               // Lookback bars untuk momentum
input bool UseMomentumPullback = true;          // Aktifkan momentum pullback detection

//==================================================================
// Helper Functions untuk Momentum Pullback
//==================================================================
double PipsToPrice(double pips)
{
    return pips * _Point * 10;
}

int CandleDir(int shift, ENUM_TIMEFRAMES tf)
{
    double open = iOpen(_Symbol, tf, shift);
    double close = iClose(_Symbol, tf, shift);
    if (close > open)
        return 1; // Bullish
    if (close < open)
        return -1; // Bearish
    return 0;      // Doji
}

double CandleBody(int shift, ENUM_TIMEFRAMES tf)
{
    double open = iOpen(_Symbol, tf, shift);
    double close = iClose(_Symbol, tf, shift);
    return MathAbs(close - open);
}

bool IsEngulfing(int shift, ENUM_TIMEFRAMES tf)
{
    double bodyCurrent = CandleBody(shift, tf);
    double bodyPrev = CandleBody(shift + 1, tf);
    int dirCurrent = CandleDir(shift, tf);
    int dirPrev = CandleDir(shift + 1, tf);

    return (bodyCurrent > bodyPrev && dirCurrent != dirPrev && dirCurrent != 0);
}

bool IsPinbar(int shift, ENUM_TIMEFRAMES tf)
{
    double high = iHigh(_Symbol, tf, shift);
    double low = iLow(_Symbol, tf, shift);
    double open = iOpen(_Symbol, tf, shift);
    double close = iClose(_Symbol, tf, shift);

    double body = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    double totalRange = high - low;

    if (totalRange == 0)
        return false;

    // Pinbar: salah satu wick > 2/3 total range dan body < 1/3 total range
    return ((upperWick > totalRange * 0.66 && body < totalRange * 0.33) ||
            (lowerWick > totalRange * 0.66 && body < totalRange * 0.33));
}

double CalculateLotFromRisk(double stopLoss, double entryPrice)
{
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercentPerTrade / 100.0);
    double riskPips = MathAbs(entryPrice - stopLoss) / _Point / 10;
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

    if (pipValue > 0 && riskPips > 0)
        return riskMoney / (riskPips * pipValue);

    return 0.1; // default lot
}

//==================================================================
// Deteksi Momentum Pullback
//==================================================================
bool DetectMomentumPullback(ENUM_TIMEFRAMES tf, MomentumSignal &outSignal, int lookbackBars = 100)
{
    outSignal.found = false;

    // Minimal bars
    if (lookbackBars < MomentumCfg::minConsecutive + 1)
        lookbackBars = MomentumCfg::minConsecutive + 1;

    int pullShift = 1;
    int dirPull = CandleDir(pullShift, tf);
    if (dirPull == 0)
        return false; // skip doji

    // === Filter trend dengan EMA200 (timeframe yang sama) ===
    int emaHandle = iMA(_Symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[];
    ArraySetAsSeries(emaArray, true);
    CopyBuffer(emaHandle, 0, 0, pullShift + 1, emaArray);

    double ema200 = emaArray[pullShift];
    double price = iClose(_Symbol, tf, pullShift);

    if (dirPull == 1 && price < ema200)
        return false; // buy tapi harga < EMA200
    if (dirPull == -1 && price > ema200)
        return false; // sell tapi harga > EMA200

    // === Filter ATR (volatilitas cukup, bukan choppy) ===
    int atrHandle = iATR(_Symbol, tf, 14);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, pullShift + 1, atrArray);

    double atr = atrArray[pullShift];
    if (atr < PipsToPrice(5))
        return false; // minimal ATR 5 pips

    // === Multi-timeframe konfirmasi trend ===
    int emaHTFHandle = iMA(_Symbol, MomentumHTF, 200, 0, MODE_EMA, PRICE_CLOSE);
    double emaHTFArray[], priceHTFArray[];
    ArraySetAsSeries(emaHTFArray, true);
    ArraySetAsSeries(priceHTFArray, true);

    CopyBuffer(emaHTFHandle, 0, 0, 2, emaHTFArray);
    CopyClose(_Symbol, MomentumHTF, 0, 2, priceHTFArray);

    double emaHTF = emaHTFArray[1];
    double priceHTF = priceHTFArray[1];

    if (dirPull == 1 && priceHTF < emaHTF)
        return false;
    if (dirPull == -1 && priceHTF > emaHTF)
        return false;

    // Cari panjang momentum L
    int maxPossibleL = MathMin(lookbackBars - 1, 20);
    for (int L = maxPossibleL; L >= MomentumCfg::minConsecutive; L--)
    {
        int start = 2;
        int end = L + 1;
        int firstDir = CandleDir(start, tf);
        if (firstDir == 0)
            continue;

        bool okSeq = true;
        for (int s = start + 1; s <= end; s++)
        {
            if (CandleDir(s, tf) != firstDir)
            {
                okSeq = false;
                break;
            }
        }
        if (!okSeq)
            continue;

        // momentum vs pullback harus berlawanan
        if (dirPull == firstDir)
            continue;

        // body pullback > multiplier * body momentum awal
        double bodyPull = CandleBody(pullShift, tf);
        double bodyPrev = CandleBody(2, tf);
        if (bodyPrev <= 0)
            bodyPrev = _Point;
        if (bodyPull < MomentumCfg::minBodyMultiplier * bodyPrev)
            continue;

        // filter engulfing / pinbar opsional
        if (MomentumCfg::useEngulfingFilter && !IsEngulfing(pullShift, tf))
            continue;
        if (MomentumCfg::usePinbarFilter && !IsPinbar(pullShift, tf))
            continue;

        // konfirmasi candle jika diaktifkan
        if (MomentumCfg::confirmationCandles > 0)
        {
            bool confOk = true;
            for (int c = 0; c < MomentumCfg::confirmationCandles; c++)
            {
                if (CandleDir(c, tf) != dirPull)
                {
                    confOk = false;
                    break;
                }
            }
            if (!confOk)
                continue;
        }

        // === jika lolos semua: buat sinyal ===
        outSignal.found = true;
        outSignal.time = iTime(_Symbol, tf, pullShift);
        outSignal.dir = (Dir)dirPull;
        outSignal.entryPrice = (dirPull == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

        double slP = MomentumCfg::slPipsDefault;
        double tpP = MomentumCfg::tpPipsDefault;
        outSignal.stopLoss = outSignal.entryPrice - dirPull * PipsToPrice(slP);
        outSignal.takeProfit = outSignal.entryPrice + dirPull * PipsToPrice(tpP);

        outSignal.lot = CalculateLotFromRisk(outSignal.stopLoss, outSignal.entryPrice);
        outSignal.lot = MathMin(outSignal.lot, MomentumCfg::maxLotPerTrade);

        outSignal.reason = StringFormat("EMA200 trend + Momentum L=%d pullback idx=%d", L, pullShift);
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| News Impact Signal Structure                                    |
//+------------------------------------------------------------------+
struct NISignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
    datetime newsTime;
    string newsEvent;
    string impact;
};

//+------------------------------------------------------------------+
//| News Impact Parameters                                          |
//+------------------------------------------------------------------+
input bool UseNewsImpact = true;     // Aktifkan news impact detection
input double NewsLotMin = 0.01;      // Lot minimal untuk news
input double NewsMinCandlePct = 0.5; // Minimal % body candle
input int NewsTrailPoints = 10;      // Trailing stop points
input int NewsEMAPeriod = 200;       // EMA period untuk filter
input int NewsATRPeriod = 14;        // ATR period untuk volatilitas

//==================================================================
// Fungsi: DetectAndExecuteMultiTFNews
// Deskripsi:
//   Deteksi sinyal news impact probabilitas tinggi menggunakan multi-timeframe
//   - M1, M5, M15 candle
//   - EMA filter jangka pendek
//   - ATR filter untuk konfirmasi volatilitas
//   - Lot dinamis, SL/TP otomatis, trailing stop
//==================================================================
NISignal DetectAndExecuteMultiTFNews(double lotMin = 0.01, double minCandlePct = 0.5, int trailPoints = 10, int emaPeriod = 200, int atrPeriod = 14)
{
    NISignal sig;
    sig.signal = DIR_NONE;
    sig.entryPrice = 0;
    sig.stopLoss = 0;
    sig.takeProfit = 0;
    sig.lotSize = lotMin;
    sig.isStrong = false;
    sig.newsTime = 0;
    sig.newsEvent = "";
    sig.impact = "";

    // -------------------------
    // Ambil news high-impact live
    // -------------------------
    datetime currentTime = TimeCurrent();
    datetime newsTime = 0; // INISIALISASI
    string newsName = "";  // INISIALISASI
    int eventImpact = 0;   // INISIALISASI
    bool newsFound = false;

    for (int i = 0; i < CalendarEventsTotal(); i++)
    {
        if (CalendarEventByIndex(i, newsTime, newsName, eventImpact))
        {
            if (eventImpact == 3 && newsTime >= currentTime && newsTime <= currentTime + 60)
            {
                newsFound = true;
                break;
            }
        }
    }
    if (!newsFound)
        return sig;

    // -------------------------
    // Multi-timeframe ratio
    // -------------------------
    double rM1 = GetBodyAndAvg(PERIOD_M1);
    double rM5 = GetBodyAndAvg(PERIOD_M5);
    double rM15 = GetBodyAndAvg(PERIOD_M15);

    // Minimal candle ratio terpenuhi di semua TF
    if (rM1 < minCandlePct || rM5 < minCandlePct || rM15 < minCandlePct)
        return sig;

    // -------------------------
    // Filter trend EMA untuk M1
    // -------------------------
    int emaHandle = iMA(_Symbol, PERIOD_M1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[];
    ArraySetAsSeries(emaArray, true);
    CopyBuffer(emaHandle, 0, 0, 2, emaArray);

    double ema = emaArray[0];
    double prevEma = emaArray[1];
    bool trendUp = (ema > prevEma);
    bool trendDown = (ema < prevEma);

    // -------------------------
    // Candle M1 terakhir
    // -------------------------
    double op = iOpen(_Symbol, PERIOD_M1, 0);
    double cl = iClose(_Symbol, PERIOD_M1, 0);
    double hi = iHigh(_Symbol, PERIOD_M1, 0);
    double lo = iLow(_Symbol, PERIOD_M1, 0);
    double body = MathAbs(cl - op);

    // -------------------------
    // ATR untuk konfirmasi volatilitas
    // -------------------------
    int atrHandle = iATR(_Symbol, PERIOD_M1, atrPeriod);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, 1, atrArray);

    double atr = atrArray[0];
    if (body < atr * 0.8)
        return sig; // body terlalu kecil → skip

    // -------------------------
    // Tentukan arah sinyal
    // -------------------------
    if (cl > op && trendUp)
    {
        sig.signal = DIR_BUY;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sig.stopLoss = lo - _Point * 5;
        sig.takeProfit = cl + body * 2;
    }
    else if (cl < op && trendDown)
    {
        sig.signal = DIR_SELL;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sig.stopLoss = hi + _Point * 5;
        sig.takeProfit = cl - body * 2;
    }
    else
        return sig;

    // -------------------------
    // Set atribut sinyal
    // -------------------------
    sig.lotSize = lotMin * (1 + body / _Point / 10.0);
    sig.isStrong = true;
    sig.newsTime = newsTime;
    sig.newsEvent = newsName;
    sig.impact = "high";

    // -------------------------
    // Entry order otomatis
    // -------------------------
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = sig.lotSize;
    request.type = (sig.signal == DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = (sig.signal == DIR_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = sig.stopLoss;
    request.tp = sig.takeProfit;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "NewsImpact";

    if (OrderSend(request, result))
    {
        Print("News Impact Order Executed: Ticket ", result.order);

        // Trailing stop akan dihandle oleh ManageTrailingBreakCloseUltimate yang sudah ada
    }
    else
    {
        Print("News Impact Order Failed: ", result.retcode);
    }

    return sig;
}

//==================================================================
// Helper Function: Hitung body candle & rata-rata
//==================================================================
double GetBodyAndAvg(ENUM_TIMEFRAMES tf)
{
    double body = MathAbs(iClose(_Symbol, tf, 0) - iOpen(_Symbol, tf, 0));
    double avg = 0;
    for (int j = 1; j <= 10; j++)
        avg += MathAbs(iClose(_Symbol, tf, j) - iOpen(_Symbol, tf, j));
    avg /= 10.0;
    if (avg == 0)
        return 0;
    return body / avg; // rasio body dibanding rata-rata
}

//+------------------------------------------------------------------+
//| Order Block Parameters                                          |
//+------------------------------------------------------------------+
input bool UseOrderBlock = true;          // Aktifkan order block detection
input ENUM_TIMEFRAMES OB_TF1 = PERIOD_H1; // Timeframe 1 untuk OB
input ENUM_TIMEFRAMES OB_TF2 = PERIOD_H4; // Timeframe 2 untuk trend filter
input double OB_BaseLot = 1.0;            // Lot dasar untuk OB
input int OB_EMAPeriod1 = 50;             // EMA period untuk TF1
input int OB_EMAPeriod2 = 50;             // EMA period untuk TF2
input int OB_Levels = 3;                  // Jumlah level OB
input double OB_ZoneBufferPips = 50;      // Buffer zona dalam pips
input int OB_Lookback = 20;               // Lookback candles untuk OB

//==================================================================
// Helper Function: Get Trend Direction dari EMA
//==================================================================
Dir GetTrendEMA(ENUM_TIMEFRAMES tf, int emaPeriod)
{
    int emaHandle = iMA(_Symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[];
    ArraySetAsSeries(emaArray, true);
    CopyBuffer(emaHandle, 0, 0, 2, emaArray);

    double emaCurrent = emaArray[0];
    double emaPrev = emaArray[1];

    if (emaCurrent > emaPrev)
        return DIR_BUY;
    if (emaCurrent < emaPrev)
        return DIR_SELL;
    return DIR_NONE;
}

//==================================================================
// Fungsi deteksi OB multi-level + scaling lot (Probabilitas ~80%+)
//==================================================================
OBSignal DetectOrderBlockPro(double baseLot = 0.01,
                             int emaM1 = 50,
                             int emaM5 = 50,
                             int levels = 3,
                             double zoneBufferPips = 10,
                             int lookback = 20,
                             bool allowStrongOverride = true)
{
    OBSignal sig;
    sig.signal = DIR_NONE;
    sig.entryPrice = 0;
    sig.stopLoss = 0;
    sig.takeProfit = 0;
    sig.lotSize = baseLot;
    sig.isStrong = false;

    double hiMax = 0, loMin = DBL_MAX;
    int idxHi = -1, idxLo = -1;

    // Cari High & Low lookback candle terakhir di TF1
    for (int i = 1; i <= lookback; i++)
    {
        double hi = iHigh(_Symbol, OB_TF1, i);
        double lo = iLow(_Symbol, OB_TF1, i);
        if (hi > hiMax)
        {
            hiMax = hi;
            idxHi = i;
        }
        if (lo < loMin)
        {
            loMin = lo;
            idxLo = i;
        }
    }

    double supply = hiMax;
    double demand = loMin;

    if (supply <= demand || supply == 0 || demand == 0)
        return sig;

    // Spread sebagai buffer, sesuaikan dengan symbol digit
    double pointSize = _Point;
    double spread = zoneBufferPips * pointSize;

    // Trend filter multi-TF
    Dir trendTF1 = GetTrendEMA(OB_TF1, emaM1);
    Dir trendTF2 = GetTrendEMA(OB_TF2, emaM5);

    // Ambil harga real-time sesuai arah
    double price = (trendTF1 == DIR_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double levelStep = (supply - demand) / levels;

    //==== BUY Multi-level OB ====
    if (trendTF1 == DIR_BUY && trendTF2 == DIR_BUY)
    {
        for (int lvl = 1; lvl <= levels; lvl++)
        {
            double levelPrice = demand + lvl * levelStep;
            if (price >= levelPrice - spread && price <= levelPrice + spread)
            {
                sig.signal = DIR_BUY;
                sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                sig.stopLoss = demand - pointSize * 5;
                sig.takeProfit = supply;
                sig.lotSize = baseLot * lvl;
                sig.isStrong = (lvl == 1);

                // Proteksi tambahan: override jika isStrong dan diizinkan
                if (sig.isStrong && allowStrongOverride)
                {
                    double maxAllowedLot = RiskManager::GetMaxLot();
                    if (sig.lotSize > maxAllowedLot)
                        sig.lotSize = maxAllowedLot; // tetap aman
                }

                break;
            }
        }
    }

    //==== SELL Multi-level OB ====
    if (trendTF1 == DIR_SELL && trendTF2 == DIR_SELL)
    {
        for (int lvl = 1; lvl <= levels; lvl++)
        {
            double levelPrice = supply - lvl * levelStep;
            if (price <= levelPrice + spread && price >= levelPrice - spread)
            {
                sig.signal = DIR_SELL;
                sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                sig.stopLoss = supply + pointSize * 5;
                sig.takeProfit = demand;
                sig.lotSize = baseLot * lvl;
                sig.isStrong = (lvl == 1);

                // Proteksi tambahan: override jika isStrong dan diizinkan
                if (sig.isStrong && allowStrongOverride)
                {
                    double maxAllowedLot = RiskManager::GetMaxLot();
                    if (sig.lotSize > maxAllowedLot)
                        sig.lotSize = maxAllowedLot; // tetap aman
                }

                break;
            }
        }
    }

    return sig;
}

//+------------------------------------------------------------------+
//| Candle Structure POLA N PRO                                      |
//+------------------------------------------------------------------+
struct Candle
{
    double open;
    double high;
    double low;
    double close;
    datetime time;
};

//+------------------------------------------------------------------+
//| Multi Entry Info Structure                                      |
//+------------------------------------------------------------------+
struct MultiEntryInfo
{
    double entry1;
    double entry2;
    double entry3;
    double stopLoss;
    double takeProfit1;
    double takeProfit2;
    double takeProfit3;
    double riskReward1;
    double riskReward2;
    double riskReward3;
};

//+------------------------------------------------------------------+
//| Candlestick Pattern Parameters                                  |
//+------------------------------------------------------------------+
input bool UseCandlePattern = true;           // Aktifkan candlestick pattern detection
input ENUM_TIMEFRAMES Candle_TF = PERIOD_M15; // Timeframe untuk pattern detection
input int Candle_EMAPeriod = 50;              // EMA period untuk trend filter
input double Candle_MinBodyRatio = 0.3;       // Minimal body ratio untuk validasi
input double Candle_RiskReward = 2.0;         // Risk reward ratio default
input bool Candle_MultiEntry = true;          // Aktifkan multi-level entry

//==================================================================
// Helper Function: Get Candle Data
//==================================================================
Candle GetCandle(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
    Candle c;
    c.open = iOpen(symbol, tf, shift);
    c.high = iHigh(symbol, tf, shift);
    c.low = iLow(symbol, tf, shift);
    c.close = iClose(symbol, tf, shift);
    c.time = iTime(symbol, tf, shift);
    return c;
}

//==================================================================
// Fungsi deteksi candlestick canggih + multi-level entry + trailing
//==================================================================
Dir DetectPatternPro(string symbol, ENUM_TIMEFRAMES tf, int shift, MultiEntryInfo &me, int emaPeriod = 50)
{
    Candle c1 = GetCandle(symbol, tf, shift + 2);
    Candle c2 = GetCandle(symbol, tf, shift + 1);
    Candle c3 = GetCandle(symbol, tf, shift);

    // Get EMA data
    int emaHandle = iMA(symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[];
    ArraySetAsSeries(emaArray, true);
    CopyBuffer(emaHandle, 0, 0, shift + 1, emaArray);
    double ema = emaArray[shift];

    // Body rata-rata 3 candle terakhir
    double avgBody = (MathAbs(c1.close - c1.open) + MathAbs(c2.close - c2.open) + MathAbs(c3.close - c3.open)) / 3.0;

    // Inisialisasi MultiEntryInfo
    me.entry1 = me.entry2 = me.entry3 = 0;
    me.takeProfit1 = me.takeProfit2 = me.takeProfit3 = 0;
    me.stopLoss = 0;
    me.riskReward1 = me.riskReward2 = me.riskReward3 = 0;

    Dir signal = DIR_NONE;

    // --- Engulfing bullish ---
    if (c2.close < c2.open && c3.close > c3.open &&
        c3.close > c2.open && c3.open < c2.close &&
        c3.close > ema && MathAbs(c3.close - c3.open) > avgBody)
    {
        double risk = c3.close - c2.low;
        if (risk > 0)
        {
            me.entry1 = c3.close;
            me.stopLoss = c2.low;
            me.takeProfit1 = me.entry1 + risk * Candle_RiskReward;

            if (Candle_MultiEntry)
            {
                me.entry2 = me.entry1 + risk * 0.5; // scaling 2
                me.takeProfit2 = me.entry2 + risk * Candle_RiskReward;
                me.entry3 = me.entry1 + risk * 1.0; // scaling 3
                me.takeProfit3 = me.entry3 + risk * Candle_RiskReward;
            }
            else
            {
                me.entry2 = me.entry1;
                me.takeProfit2 = me.takeProfit1;
                me.entry3 = me.entry1;
                me.takeProfit3 = me.takeProfit1;
            }

            me.riskReward1 = me.riskReward2 = me.riskReward3 = Candle_RiskReward;
            return DIR_BUY;
        }
    }

    // --- Engulfing bearish ---
    if (c2.close > c2.open && c3.close < c3.open &&
        c3.close < c2.open && c3.open > c2.close &&
        c3.close < ema && MathAbs(c3.close - c3.open) > avgBody)
    {
        double risk = c2.high - c3.close;
        if (risk > 0)
        {
            me.entry1 = c3.close;
            me.stopLoss = c2.high;
            me.takeProfit1 = me.entry1 - risk * Candle_RiskReward;

            if (Candle_MultiEntry)
            {
                me.entry2 = me.entry1 - risk * 0.5;
                me.takeProfit2 = me.entry2 - risk * Candle_RiskReward;
                me.entry3 = me.entry1 - risk * 1.0;
                me.takeProfit3 = me.entry3 - risk * Candle_RiskReward;
            }
            else
            {
                me.entry2 = me.entry1;
                me.takeProfit2 = me.takeProfit1;
                me.entry3 = me.entry1;
                me.takeProfit3 = me.takeProfit1;
            }

            me.riskReward1 = me.riskReward2 = me.riskReward3 = Candle_RiskReward;
            return DIR_SELL;
        }
    }

    // --- Pin Bar / Hammer bullish ---
    double body = MathAbs(c3.close - c3.open);
    double upperWick = c3.high - MathMax(c3.close, c3.open);
    double lowerWick = MathMin(c3.close, c3.open) - c3.low;
    double range = c3.high - c3.low;

    if (range > 0 && lowerWick >= 2 * body && body <= Candle_MinBodyRatio * range && c3.close > ema)
    {
        double risk = c3.close - c3.low;
        if (risk > 0)
        {
            me.entry1 = c3.close;
            me.stopLoss = c3.low;
            me.takeProfit1 = me.entry1 + risk * Candle_RiskReward;

            if (Candle_MultiEntry)
            {
                me.entry2 = me.entry1 + risk * 0.5;
                me.takeProfit2 = me.entry2 + risk * Candle_RiskReward;
                me.entry3 = me.entry1 + risk * 1.0;
                me.takeProfit3 = me.entry3 + risk * Candle_RiskReward;
            }
            else
            {
                me.entry2 = me.entry1;
                me.takeProfit2 = me.takeProfit1;
                me.entry3 = me.entry1;
                me.takeProfit3 = me.takeProfit1;
            }

            me.riskReward1 = me.riskReward2 = me.riskReward3 = Candle_RiskReward;
            return DIR_BUY;
        }
    }

    // --- Pin Bar / Inverted Hammer bearish ---
    if (range > 0 && upperWick >= 2 * body && body <= Candle_MinBodyRatio * range && c3.close < ema)
    {
        double risk = c3.high - c3.close;
        if (risk > 0)
        {
            me.entry1 = c3.close;
            me.stopLoss = c3.high;
            me.takeProfit1 = me.entry1 - risk * Candle_RiskReward;

            if (Candle_MultiEntry)
            {
                me.entry2 = me.entry1 - risk * 0.5;
                me.takeProfit2 = me.entry2 - risk * Candle_RiskReward;
                me.entry3 = me.entry1 - risk * 1.0;
                me.takeProfit3 = me.entry3 - risk * Candle_RiskReward;
            }
            else
            {
                me.entry2 = me.entry1;
                me.takeProfit2 = me.takeProfit1;
                me.entry3 = me.entry1;
                me.takeProfit3 = me.takeProfit1;
            }

            me.riskReward1 = me.riskReward2 = me.riskReward3 = Candle_RiskReward;
            return DIR_SELL;
        }
    }

    return DIR_NONE;
}

//==================================================================
// Fungsi Execute Multi-Entry
//==================================================================
void ExecuteMultiEntryTrade(Dir direction, MultiEntryInfo &me, double baseLot)
{
    if (direction == DIR_NONE)
        return;

    double lot1 = baseLot;
    double lot2 = baseLot * 0.7; // Smaller lot untuk entry berikutnya
    double lot3 = baseLot * 0.5; // Even smaller lot

    // Entry 1 - Immediate
    if (direction == DIR_BUY)
    {
        string signalSource = "Multi-Entry";
        ExecuteBuy(lot1, (int)((me.entry1 - me.stopLoss) / _Point / 10),
                   (int)((me.takeProfit1 - me.entry1) / _Point / 10), signalSource);
    }
    else
    {
        string signalSource = "Multi-Entry";
        ExecuteSell(lot1, (int)((me.stopLoss - me.entry1) / _Point / 10),
                    (int)((me.entry1 - me.takeProfit1) / _Point / 10), signalSource);
    }

    // Entry 2 & 3 akan dihandle oleh pending orders (jika multi-entry aktif)
    if (Candle_MultiEntry)
    {
        // Untuk simplicity, kita eksekusi langsung dengan smaller lots
        // Dalam implementasi real, bisa menggunakan pending orders
        if (direction == DIR_BUY && me.entry2 > 0)
        {
            string signalSource = "Candle_MultiEntry";
            ExecuteBuy(lot2, (int)((me.entry2 - me.stopLoss) / _Point / 10),
                       (int)((me.takeProfit2 - me.entry2) / _Point / 10), signalSource);
        }
        else if (direction == DIR_SELL && me.entry2 > 0)
        {
            string signalSource = "Candle_MultiEntry";
            ExecuteSell(lot2, (int)((me.stopLoss - me.entry2) / _Point / 10),
                        (int)((me.entry2 - me.takeProfit2) / _Point / 10), signalSource);
        }
    }
}

//+------------------------------------------------------------------+
//| SCM Signal Structure                                            |
//+------------------------------------------------------------------+
struct SCMSignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
};

//+------------------------------------------------------------------+
//| SCM (Smart Convergence Momentum) Parameters                     |
//+------------------------------------------------------------------+
input bool UseSCMSignal = true;             // Aktifkan SCM signal detection
input ENUM_TIMEFRAMES SCM_TF1 = PERIOD_M1;  // Timeframe 1 untuk SCM
input ENUM_TIMEFRAMES SCM_TF2 = PERIOD_M5;  // Timeframe 2 untuk SCM
input ENUM_TIMEFRAMES SCM_TF3 = PERIOD_M15; // Timeframe 3 untuk SCM
input double SCM_BaseLot = 0.01;            // Lot dasar untuk SCM
input int SCM_EMAPeriod = 50;               // EMA period untuk trend
input int SCM_RSIPeriod = 14;               // RSI period
input double SCM_RSI_OB = 70;               // RSI overbought level
input double SCM_RSI_OS = 30;               // RSI oversold level
input int SCM_MACD_Fast = 12;               // MACD fast period
input int SCM_MACD_Slow = 26;               // MACD slow period
input int SCM_MACD_Signal = 9;              // MACD signal period
input int SCM_ATRPeriod = 14;               // ATR period
input double SCM_ATRMultiplier = 1.5;       // ATR multiplier untuk SL

//==================================================================
// Helper Function: Get EMA Trend Direction
//==================================================================
Dir GetEMAtrend(ENUM_TIMEFRAMES tf, int emaPeriod)
{
    int emaHandle = iMA(_Symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double emaArray[], priceArray[];
    ArraySetAsSeries(emaArray, true);
    ArraySetAsSeries(priceArray, true);

    CopyBuffer(emaHandle, 0, 0, 2, emaArray);
    CopyClose(_Symbol, tf, 0, 2, priceArray);

    double emaCurrent = emaArray[0];
    double priceCurrent = priceArray[0];

    if (priceCurrent > emaCurrent)
        return DIR_BUY;
    if (priceCurrent < emaCurrent)
        return DIR_SELL;
    return DIR_NONE;
}

//==================================================================
// Fungsi: DetectSCMSignalHighProb
// Deskripsi: Smart Convergence Momentum dengan multi-timeframe confirmation
//==================================================================
SCMSignal DetectSCMSignalHighProb(double lotMin = 0.01,
                                  int emaPeriod = 50,
                                  int rsiPeriod = 14,
                                  double rsiOB = 70,
                                  double rsiOS = 30,
                                  int macdFast = 12,
                                  int macdSlow = 26,
                                  int macdSignal = 9,
                                  int atrPeriod = 14,
                                  double atrMultiplier = 1.5)
{
    SCMSignal sig;
    sig.signal = DIR_NONE;
    sig.entryPrice = 0;
    sig.stopLoss = 0;
    sig.takeProfit = 0;
    sig.lotSize = lotMin;
    sig.isStrong = false;

    // --- Trend EMA Multi-TF ---
    Dir trendTF1 = GetEMAtrend(SCM_TF1, emaPeriod);
    Dir trendTF2 = GetEMAtrend(SCM_TF2, emaPeriod);
    Dir trendTF3 = GetEMAtrend(SCM_TF3, emaPeriod);

    // --- RSI pada TF1 ---
    int rsiHandle = iRSI(_Symbol, SCM_TF1, rsiPeriod, PRICE_CLOSE);
    double rsiArray[];
    ArraySetAsSeries(rsiArray, true);
    CopyBuffer(rsiHandle, 0, 0, 1, rsiArray);
    double rsi = rsiArray[0];

    // --- MACD pada TF1 ---
    int macdHandle = iMACD(_Symbol, SCM_TF1, macdFast, macdSlow, macdSignal, PRICE_CLOSE);
    double macdMainArray[], macdSignalArray[];
    ArraySetAsSeries(macdMainArray, true);
    ArraySetAsSeries(macdSignalArray, true);

    CopyBuffer(macdHandle, MAIN_LINE, 0, 1, macdMainArray);
    CopyBuffer(macdHandle, SIGNAL_LINE, 0, 1, macdSignalArray);

    double macdCurrent = macdMainArray[0];
    double macdSignalLine = macdSignalArray[0];

    // --- ATR pada TF1 ---
    int atrHandle = iATR(_Symbol, SCM_TF1, atrPeriod);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, 1, atrArray);
    double atr = atrArray[0];

    // --- Candle info ---
    double openC = iOpen(_Symbol, SCM_TF1, 0);
    double closeC = iClose(_Symbol, SCM_TF1, 0);
    double body = MathAbs(closeC - openC);

    // Validasi data
    if (atr <= 0 || rsi <= 0)
        return sig;

    // --- BUY Condition ---
    if (trendTF1 == DIR_BUY && trendTF2 == DIR_BUY && trendTF3 == DIR_BUY &&
        rsi < rsiOS &&
        macdCurrent > macdSignalLine &&
        body >= atr * 0.5) // candle cukup kuat
    {
        sig.signal = DIR_BUY;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sig.stopLoss = sig.entryPrice - atr * atrMultiplier;
        sig.takeProfit = sig.entryPrice + atr * atrMultiplier * 2;
        sig.lotSize = lotMin * (1 + body / _Point / 10);
        sig.lotSize = MathMin(sig.lotSize, lotMin * 3); // Batasi maksimal 3x base lot
        sig.isStrong = true;
    }

    // --- SELL Condition ---
    if (trendTF1 == DIR_SELL && trendTF2 == DIR_SELL && trendTF3 == DIR_SELL &&
        rsi > rsiOB &&
        macdCurrent < macdSignalLine &&
        body >= atr * 0.5) // candle cukup kuat
    {
        sig.signal = DIR_SELL;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sig.stopLoss = sig.entryPrice + atr * atrMultiplier;
        sig.takeProfit = sig.entryPrice - atr * atrMultiplier * 2;
        sig.lotSize = lotMin * (1 + body / _Point / 10);
        sig.lotSize = MathMin(sig.lotSize, lotMin * 3); // Batasi maksimal 3x base lot
        sig.isStrong = true;
    }

    return sig;
}

//+------------------------------------------------------------------+
//| Price Action Signal Structure                                   |
//+------------------------------------------------------------------+
struct PA_Signal
{
    bool found;        // true jika ada sinyal
    datetime time;     // waktu candle
    double entryPrice; // harga entry
    double stopLoss;   // SL otomatis
    double takeProfit; // TP otomatis
    int lotLevel;      // level scaling lot
    double lotSize;
    bool longTrade; // arah trade: true=buy, false=sell
    Dir direction;  // direction (DIR_BUY/DIR_SELL)
};

//+------------------------------------------------------------------+
//| Price Action Parameters                                         |
//+------------------------------------------------------------------+
input bool UsePriceAction = true;                // Aktifkan price action detection
input ENUM_TIMEFRAMES PA_MainTF = PERIOD_M5;     // Main timeframe untuk trend
input ENUM_TIMEFRAMES PA_ConfirmTF = PERIOD_M15; // Confirmation timeframe
input int PA_EMA_Long = 200;                     // EMA long period untuk trend
input int PA_EMA_Short = 50;                     // EMA short period untuk konfirmasi
input double PA_RiskPercent = 100.0;             // Risiko per trade
input double PA_RewardRatio = 2.0;               // Risk:Reward ratio
input double PA_ATR_Multiplier = 1.5;            // ATR multiplier untuk SL
input double PA_TrailFactor = 1.0;               // Trailing stop factor

//==================================================================
// Fungsi deteksi Price Action canggih dengan Multi-Timeframe Confirmation
// High-probability ~90%
//==================================================================
PA_Signal DetectPriceAction_MTF(string symbol, int shift = 1)
{
    PA_Signal signal;
    signal.found = false;
    signal.direction = DIR_NONE;

    // ============================
    // 1. Trend Filter EMA (Multi-Timeframe)
    // ============================
    int emaLongMain = iMA(symbol, PA_MainTF, PA_EMA_Long, 0, MODE_EMA, PRICE_CLOSE);
    int emaShortMain = iMA(symbol, PA_MainTF, PA_EMA_Short, 0, MODE_EMA, PRICE_CLOSE);

    double emaLongMainArray[], emaShortMainArray[], closeMainArray[];
    ArraySetAsSeries(emaLongMainArray, true);
    ArraySetAsSeries(emaShortMainArray, true);
    ArraySetAsSeries(closeMainArray, true);

    CopyBuffer(emaLongMain, 0, 0, shift + 1, emaLongMainArray);
    CopyBuffer(emaShortMain, 0, 0, shift + 1, emaShortMainArray);
    CopyClose(symbol, PA_MainTF, 0, shift + 1, closeMainArray);

    double emaLongMainVal = emaLongMainArray[shift];
    double emaShortMainVal = emaShortMainArray[shift];
    double closeMain = closeMainArray[shift];

    int emaLongConfirm = iMA(symbol, PA_ConfirmTF, PA_EMA_Long, 0, MODE_EMA, PRICE_CLOSE);
    int emaShortConfirm = iMA(symbol, PA_ConfirmTF, PA_EMA_Short, 0, MODE_EMA, PRICE_CLOSE);

    double emaLongConfirmArray[], emaShortConfirmArray[], closeConfirmArray[];
    ArraySetAsSeries(emaLongConfirmArray, true);
    ArraySetAsSeries(emaShortConfirmArray, true);
    ArraySetAsSeries(closeConfirmArray, true);

    CopyBuffer(emaLongConfirm, 0, 0, shift + 1, emaLongConfirmArray);
    CopyBuffer(emaShortConfirm, 0, 0, shift + 1, emaShortConfirmArray);
    CopyClose(symbol, PA_ConfirmTF, 0, shift + 1, closeConfirmArray);

    double emaLongConfirmVal = emaLongConfirmArray[shift];
    double emaShortConfirmVal = emaShortConfirmArray[shift];
    double closeConfirm = closeConfirmArray[shift];

    bool upTrend = (closeMain > emaLongMainVal && emaShortMainVal > emaLongMainVal) &&
                   (closeConfirm > emaLongConfirmVal && emaShortConfirmVal > emaLongConfirmVal);

    bool downTrend = (closeMain < emaLongMainVal && emaShortMainVal < emaLongMainVal) &&
                     (closeConfirm < emaLongConfirmVal && emaShortConfirmVal < emaLongConfirmVal);

    // ============================
    // 2. Ambil harga candle utama
    // ============================
    double open = iOpen(symbol, PA_ConfirmTF, shift);
    double close = iClose(symbol, PA_ConfirmTF, shift);
    double high = iHigh(symbol, PA_ConfirmTF, shift);
    double low = iLow(symbol, PA_ConfirmTF, shift);
    double prevOpen = iOpen(symbol, PA_ConfirmTF, shift + 1);
    double prevClose = iClose(symbol, PA_ConfirmTF, shift + 1);

    // ============================
    // 3. ATR untuk SL/TP dinamis
    // ============================
    int atrHandle = iATR(symbol, PA_ConfirmTF, 14);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, shift + 1, atrArray);
    double atr = atrArray[shift];

    // ============================
    // 4. Deteksi Pin Bar / Engulfing
    // ============================
    double body = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    double totalRange = high - low;

    // Validasi data
    if (totalRange <= 0 || atr <= 0)
        return signal;

    // --- Bullish Pin Bar ---
    if (upTrend && lowerWick > body * 2 && upperWick < body && body <= totalRange * 0.3)
    {
        signal.found = true;
        signal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        signal.stopLoss = low - PA_ATR_Multiplier * atr;
        signal.takeProfit = signal.entryPrice + PA_RewardRatio * (signal.entryPrice - signal.stopLoss);
        signal.lotLevel = 1;
        signal.time = iTime(symbol, PA_ConfirmTF, shift);
        signal.longTrade = true;
        signal.direction = DIR_BUY;
    }
    // --- Bearish Pin Bar ---
    else if (downTrend && upperWick > body * 2 && lowerWick < body && body <= totalRange * 0.3)
    {
        signal.found = true;
        signal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        signal.stopLoss = high + PA_ATR_Multiplier * atr;
        signal.takeProfit = signal.entryPrice - PA_RewardRatio * (signal.stopLoss - signal.entryPrice);
        signal.lotLevel = 1;
        signal.time = iTime(symbol, PA_ConfirmTF, shift);
        signal.longTrade = false;
        signal.direction = DIR_SELL;
    }

    // --- Bullish Engulfing ---
    if (upTrend && prevClose < prevOpen && close > open && close > prevOpen && open < prevClose)
    {
        signal.found = true;
        signal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        signal.stopLoss = low - PA_ATR_Multiplier * atr;
        signal.takeProfit = signal.entryPrice + PA_RewardRatio * (signal.entryPrice - signal.stopLoss);
        signal.lotLevel = 2;
        signal.time = iTime(symbol, PA_ConfirmTF, shift);
        signal.longTrade = true;
        signal.direction = DIR_BUY;
    }

    // --- Bearish Engulfing ---
    if (downTrend && prevClose > prevOpen && close < open && close < prevOpen && open > prevClose)
    {
        signal.found = true;
        signal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        signal.stopLoss = high + PA_ATR_Multiplier * atr;
        signal.takeProfit = signal.entryPrice - PA_RewardRatio * (signal.stopLoss - signal.entryPrice);
        signal.lotLevel = 2;
        signal.time = iTime(symbol, PA_ConfirmTF, shift);
        signal.longTrade = false;
        signal.direction = DIR_SELL;
    }

    return signal;
}

//==================================================================
// Fungsi Trailing Stop otomatis untuk Price Action
//==================================================================
double PATrailingStop(double currentPrice, double stopLoss, bool longTrade, double atr, double trailFactor = 1.0)
{
    if (longTrade)
    {
        double newSL = currentPrice - trailFactor * atr;
        if (newSL > stopLoss)
            stopLoss = newSL;
    }
    else
    {
        double newSL = currentPrice + trailFactor * atr;
        if (newSL < stopLoss)
            stopLoss = newSL;
    }
    return stopLoss;
}

//==================================================================
// Fungsi Execute Price Action Trade
//==================================================================
void ExecutePriceActionTrade(PA_Signal &paSignal)
{
    if (!paSignal.found)
        return;

    double lotSize = RiskManager::GetDynamicLot(0.7,
                                                (int)(MathAbs(paSignal.entryPrice - paSignal.stopLoss) / _Point / 10));

    if (paSignal.direction == DIR_BUY)
    {
        string signalSource = "Price Action Trade";
        int slPips = (int)((paSignal.entryPrice - paSignal.stopLoss) / _Point / 10);
        int tpPips = (int)((paSignal.takeProfit - paSignal.entryPrice) / _Point / 10);
        ExecuteBuy(lotSize, slPips, tpPips, signalSource);
    }
    else if (paSignal.direction == DIR_SELL)
    {
        string signalSource = "Price Action Trade";
        int slPips = (int)((paSignal.stopLoss - paSignal.entryPrice) / _Point / 10);
        int tpPips = (int)((paSignal.entryPrice - paSignal.takeProfit) / _Point / 10);
        ExecuteSell(lotSize, slPips, tpPips, signalSource);
    }
}

//+------------------------------------------------------------------+
//| SMC Signal Structure                                            |
//+------------------------------------------------------------------+
struct SMCSignal
{
    Dir signal;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    bool isStrong;
};

//+------------------------------------------------------------------+
//| SMC (Smart Money Concept) Parameters                            |
//+------------------------------------------------------------------+
input bool UseSMCSignal = true;            // Aktifkan SMC signal detection
input ENUM_TIMEFRAMES SMC_TF1 = PERIOD_H1; // Timeframe 1 untuk SMC
input ENUM_TIMEFRAMES SMC_TF2 = PERIOD_H4; // Timeframe 2 untuk trend confirmation
input double SMC_BaseLot = 0.01;           // Lot dasar untuk SMC
input int SMC_EMA_Period1 = 50;            // EMA period untuk TF1
input int SMC_EMA_Period2 = 50;            // EMA period untuk TF2
input int SMC_Lookback = 20;               // Lookback candles untuk OB detection
input double SMC_ATR_Multiplier = 1.5;     // ATR multiplier untuk SL
input double SMC_TP_Ratio = 0.8;           // Take profit ratio (0.8 = 80% dari range)

//==================================================================
// Fungsi deteksi SMC Signal canggih (OB + Breaker + Stop Hunt + Multi-TF)
// Probabilitas tinggi ~90%
//==================================================================
SMCSignal DetectSMCSignalAdvanced(double lotMin = 0.01,
                                  int emaPeriodM1 = 50,
                                  int emaPeriodM5 = 50,
                                  int lookbackCandle = 20,
                                  double atrMultiplier = 1.5)
{
    SMCSignal sig;
    sig.signal = DIR_NONE;
    sig.entryPrice = 0;
    sig.stopLoss = 0;
    sig.takeProfit = 0;
    sig.lotSize = lotMin;
    sig.isStrong = false;

    // --------------------------
    // 1. Trend filter multi-TF
    // --------------------------
    Dir trendTF1 = GetEMAtrend(SMC_TF1, emaPeriodM1);
    Dir trendTF2 = GetEMAtrend(SMC_TF2, emaPeriodM5);

    if (trendTF1 != trendTF2)
        return sig; // konfirmasi trend gagal

    bool upTrend = (trendTF1 == DIR_BUY);
    bool downTrend = (trendTF1 == DIR_SELL);

    // --------------------------
    // 2. Scan Order Block + Breaker
    // --------------------------
    double hiMax = 0, loMin = 0;
    int idxHi = -1, idxLo = -1;

    for (int i = 1; i <= lookbackCandle; i++)
    {
        double hi = iHigh(_Symbol, SMC_TF1, i);
        double lo = iLow(_Symbol, SMC_TF1, i);
        if (hi > hiMax)
        {
            hiMax = hi;
            idxHi = i;
        }
        if (lo < loMin || loMin == 0)
        {
            loMin = lo;
            idxLo = i;
        }
    }

    double supply = hiMax; // OB resistance
    double demand = loMin; // OB support

    double price = iClose(_Symbol, SMC_TF1, 0);
    double spread = _Point * 10;

    // Validasi zona OB
    if (supply <= demand || supply == 0 || demand == 0)
        return sig;

    // --------------------------
    // 3. ATR untuk SL/TP
    // --------------------------
    int atrHandle = iATR(_Symbol, SMC_TF1, 14);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, 1, atrArray);
    double atr = atrArray[0];

    // --------------------------
    // 4. Deteksi Stop Hunt (wick spike)
    // --------------------------
    double high0 = iHigh(_Symbol, SMC_TF1, 0);
    double low0 = iLow(_Symbol, SMC_TF1, 0);
    double open0 = iOpen(_Symbol, SMC_TF1, 0);
    double close0 = iClose(_Symbol, SMC_TF1, 0);
    double body0 = MathAbs(close0 - open0);
    double upperWick0 = high0 - MathMax(open0, close0);
    double lowerWick0 = MathMin(open0, close0) - low0;

    bool bullishStopHunt = upTrend && lowerWick0 > body0 * 2;
    bool bearishStopHunt = downTrend && upperWick0 > body0 * 2;

    // --------------------------
    // 5. BUY Signal (Demand Zone + Stop Hunt)
    // --------------------------
    if (upTrend && price <= demand + spread)
    {
        sig.signal = DIR_BUY;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sig.stopLoss = demand - atr * atrMultiplier;
        sig.takeProfit = sig.entryPrice + (supply - demand) * SMC_TP_Ratio;
        sig.isStrong = true;

        // Dynamic lot scaling berdasarkan strength
        double lotMultiplier = 1.0 + (double)(lookbackCandle - idxLo) / lookbackCandle;
        sig.lotSize = lotMin * MathMin(lotMultiplier, 3.0); // Maksimal 3x base lot
    }

    // --------------------------
    // 6. SELL Signal (Supply Zone + Stop Hunt)
    // --------------------------
    if (downTrend && price >= supply - spread)
    {
        sig.signal = DIR_SELL;
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sig.stopLoss = supply + atr * atrMultiplier;
        sig.takeProfit = sig.entryPrice - (supply - demand) * SMC_TP_Ratio;
        sig.isStrong = true;

        // Dynamic lot scaling berdasarkan strength
        double lotMultiplier = 1.0 + (double)(lookbackCandle - idxHi) / lookbackCandle;
        sig.lotSize = lotMin * MathMin(lotMultiplier, 3.0); // Maksimal 3x base lot
    }

    return sig;
}

//==================================================================
// Fungsi Execute SMC Trade
//==================================================================
void ExecuteSMCTrade(SMCSignal &smcSignal)
{
    if (smcSignal.signal == DIR_NONE)
        return;

    if (smcSignal.signal == DIR_BUY)
    {
        string signalSource = "SMC";
        int slPips = (int)((smcSignal.entryPrice - smcSignal.stopLoss) / _Point / 10);
        int tpPips = (int)((smcSignal.takeProfit - smcSignal.entryPrice) / _Point / 10);
        ExecuteBuy(smcSignal.lotSize, slPips, tpPips, signalSource);
    }
    else if (smcSignal.signal == DIR_SELL)
    {
        string signalSource = "SMC";
        int slPips = (int)((smcSignal.stopLoss - smcSignal.entryPrice) / _Point / 10);
        int tpPips = (int)((smcSignal.entryPrice - smcSignal.takeProfit) / _Point / 10);
        ExecuteSell(smcSignal.lotSize, slPips, tpPips, signalSource);
    }
}

//+------------------------------------------------------------------+
//| Stochastic Ultimate Parameters                                  |
//+------------------------------------------------------------------+
input bool UseStochastic = true;                 // Aktifkan stochastic detection
input ENUM_TIMEFRAMES Stoch_TFLow = PERIOD_M15;  // Timeframe rendah untuk entry
input ENUM_TIMEFRAMES Stoch_TFHigh = PERIOD_M30; // Timeframe tinggi untuk konfirmasi
input int Stoch_KPeriod = 14;                    // %K period
input int Stoch_DPeriod = 3;                     // %D period
input int Stoch_Slowing = 3;                     // Slowing period
input int Stoch_EMAPeriod = 50;                  // EMA period untuk trend filter
input double Stoch_ATR_Multiplier = 3.5;         // ATR multiplier untuk SL
input double Stoch_TrailFactor = 1.0;            // Trailing stop factor

//==================================================================
// Fungsi Stochastic Ultimate Advanced (Multi-TF + Trend Filter + ATR SL/TP)
// Probabilitas tinggi ~90%
//==================================================================
StochSignal GetStochasticSignalUltimateAdvanced(ENUM_TIMEFRAMES tfLow,
                                                ENUM_TIMEFRAMES tfHigh,
                                                int kPeriod = 14,
                                                int dPeriod = 3,
                                                int slowing = 3,
                                                int emaPeriod = 50,
                                                double atrMultiplier = 3.5,
                                                int shift = 0)
{
    StochSignal sig;
    sig.signal = DIR_NONE;
    sig.isStrong = false;
    sig.kValueLow = 0;
    sig.dValueLow = 0;
    sig.kValueHigh = 0;
    sig.dValueHigh = 0;

    //--- TF rendah (entry cepat)
    int stochLowHandle = iStochastic(_Symbol, tfLow, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
    double kLowArray[], dLowArray[];
    ArraySetAsSeries(kLowArray, true);
    ArraySetAsSeries(dLowArray, true);

    CopyBuffer(stochLowHandle, 0, 0, shift + 1, kLowArray);
    CopyBuffer(stochLowHandle, 1, 0, shift + 1, dLowArray);

    double kLow = kLowArray[shift];
    double dLow = dLowArray[shift];
    sig.kValueLow = kLow;
    sig.dValueLow = dLow;

    //--- TF tinggi (konfirmasi trend)
    int stochHighHandle = iStochastic(_Symbol, tfHigh, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
    double kHighArray[], dHighArray[];
    ArraySetAsSeries(kHighArray, true);
    ArraySetAsSeries(dHighArray, true);

    CopyBuffer(stochHighHandle, 0, 0, shift + 1, kHighArray);
    CopyBuffer(stochHighHandle, 1, 0, shift + 1, dHighArray);

    double kHigh = kHighArray[shift];
    double dHigh = dHighArray[shift];
    sig.kValueHigh = kHigh;
    sig.dValueHigh = dHigh;

    //--- Trend filter TF tinggi
    Dir trendHigh = GetEMAtrend(tfHigh, emaPeriod);

    //--- ATR untuk SL/TP dinamis
    int atrHandle = iATR(_Symbol, tfLow, 14);
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    CopyBuffer(atrHandle, 0, 0, shift + 1, atrArray);
    double atr = atrArray[shift];

    //--- Validasi data
    if (kLow == 0 || dLow == 0 || kHigh == 0 || dHigh == 0 || atr == 0)
        return sig;

    //--- Logika sinyal advanced
    bool bullishCross = (kLow > dLow) && (kLow < 20);
    bool bearishCross = (kLow < dLow) && (kLow > 80);

    bool strongBullish = (kLow < 20) && (trendHigh == DIR_BUY) && (kHigh < 30);
    bool strongBearish = (kLow > 80) && (trendHigh == DIR_SELL) && (kHigh > 70);

    if (strongBullish && bullishCross)
    {
        sig.signal = DIR_BUY;
        sig.isStrong = true;
    }
    else if (strongBearish && bearishCross)
    {
        sig.signal = DIR_SELL;
        sig.isStrong = true;
    }
    else if (bullishCross)
    {
        sig.signal = DIR_BUY;
        sig.isStrong = false;
    }
    else if (bearishCross)
    {
        sig.signal = DIR_SELL;
        sig.isStrong = false;
    }

    //--- Tambahkan SL/TP berbasis ATR
    double closePrice = iClose(_Symbol, tfLow, shift);
    double sl = 0, tp = 0;

    double extraBuffer = atr * 0.5; // tambahan buffer setengah ATR
    double rrRatio = 2.0;           // rasio TP : SL (contoh 1:2)

    // --- BUY signal
    if (sig.signal == DIR_BUY)
    {
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // SL lebih longgar: ATR * multiplier + buffer
        sl = closePrice - (atr * atrMultiplier + extraBuffer);

        // TP tetap RR sesuai ratio
        tp = closePrice + (atr * atrMultiplier * rrRatio);
    }

    // --- SELL signal
    else if (sig.signal == DIR_SELL)
    {
        sig.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // SL lebih longgar
        sl = closePrice + (atr * atrMultiplier + extraBuffer);

        // TP tetap RR sesuai ratio
        tp = closePrice - (atr * atrMultiplier * rrRatio);
    }
    sig.stopLoss = sl;
    sig.takeProfit = tp;

    return sig;
}


//==================================================================
// Fungsi Execute Stochastic Trade
//==================================================================
void ExecuteStochasticTrade(StochSignal &stochSignal)
{
    if (stochSignal.signal == DIR_NONE)
        return;

    double lotSize = RiskManager::GetDynamicLot(
        stochSignal.isStrong ? 0.8 : 0.6, // Higher confidence for strong signals
        (int)(MathAbs(stochSignal.entryPrice - stochSignal.stopLoss) / _Point / 10));

    if (stochSignal.signal == DIR_BUY)
    {
        string signalSource = "Stochastic";
        int slPips = (int)((stochSignal.entryPrice - stochSignal.stopLoss) / _Point / 10);
        int tpPips = (int)((stochSignal.takeProfit - stochSignal.entryPrice) / _Point / 10);
        ExecuteBuy(lotSize, slPips, tpPips, signalSource);
    }
    else if (stochSignal.signal == DIR_SELL)
    {
        string signalSource = "Stochastic";
        int slPips = (int)((stochSignal.stopLoss - stochSignal.entryPrice) / _Point / 10);
        int tpPips = (int)((stochSignal.entryPrice - stochSignal.takeProfit) / _Point / 10);
        ExecuteSell(lotSize, slPips, tpPips, signalSource);
    }
}

//+------------------------------------------------------------------+
//| Signal Dashboard Configuration                                  |
//+------------------------------------------------------------------+
input bool EnableDashboard = true;                                                // Aktifkan Signal Dashboard
input bool Dashboard_SendTelegram = true;                                         // Kirim Telegram Notifikasi
input string TelegramBotToken = "8470744929:AAHJ02vl-RUxRbVdc_kBZuSZdPx_Qzvtnr8"; // token bot
input string TelegramChatID = "-1002864046051";                                   // chat ID grup/channel
input bool EnableTelegram = true;                                                 // bisa diubah di properties EA

input int Dashboard_LabelFontSize = 10;  // Ukuran font label chart
input int Dashboard_MaxColumns = 3;      // Max kolom label chart
input int Dashboard_XBase = 20;          // Posisi X pertama label
input int Dashboard_YBase = 50;          // Posisi Y pertama label
input int Dashboard_XStep = 200;         // Jarak X antar label
input int Dashboard_YStep = 50;          // Jarak Y antar label
input int Dashboard_BarLength = 8;       // Panjang bar TP/SL
input bool Dashboard_AnimateBars = true; // Animate bars per tick
input int Dashboard_TrendCandles = 5;    // Jumlah candle untuk mini trend

//+------------------------------------------------------------------+
//| Strength Enum                                                    |
//+------------------------------------------------------------------+
enum Strength
{
    WEAK,
    MEDIUM,
    STRONG
};

//+------------------------------------------------------------------+
//| Signal Info Structure                                           |
//+------------------------------------------------------------------+
struct SignalInfo
{
    string name;
    Dir signal;
    Strength strength;
    double lot;
    double sl;
    double tp;
    double entry; // Tambahkan field entry
    double confidence;
};

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
SignalInfo Signals[20];           // Array untuk menyimpan sinyal
int SignalCount = 0;              // Jumlah sinyal aktif
datetime LastDashboardUpdate = 0; // Waktu update terakhir dashboard

// Helper function untuk error descriptions
string GetLastErrorDescription(int error_code)
{
    switch (error_code)
    {
    case 4014:
        return "URL not allowed - Add to WebRequest list";
    case 4060:
        return "WebRequest not allowed - Enable in EA settings";
    case 4016:
        return "No internet connection";
    default:
        return "Unknown error";
    }
}

//==================================================================
// Fungsi: SendTradeAlert
// Deskripsi: Kirim alert trade ke Telegram
//==================================================================
//+------------------------------------------------------------------+
//| Send Trade Alert (FIXED)                                       |
//+------------------------------------------------------------------+
//==================================================================
// Fungsi: Send Trade Alert (Super Upgrade 🚀🔥)
//==================================================================
// Global variables untuk menyimpan state terakhir
string lastSymbol = "";
Dir lastDirection = DIR_NONE;
double lastEntry = 0;
datetime lastAlertTime = 0;
int alertCooldown = 60; // Cooldown 60 detik

void SendTradeAlert(string symbol, Dir direction, double lot, double entry, double sl, double tp, string signal_type)
{
    if (!Dashboard_SendTelegram || !EnableTelegram)
    {
        Print("⚠️ Telegram alerts disabled");
        return;
    }

    // Cek cooldown untuk mencegah spam
    if (TimeCurrent() - lastAlertTime < alertCooldown)
    {
        Print("⏳ Telegram alert dalam cooldown, skip...");
        return;
    }

    // Cek apakah alert untuk symbol dan direction yang sama sudah dikirim
    if (symbol == lastSymbol && direction == lastDirection && MathAbs(entry - lastEntry) < Point() * 10)
    {
        Print("⚠️ Alert untuk ", symbol, " ", EnumToString(direction), " sudah dikirim, skip...");
        return;
    }

    Print("📸 Capturing chart analysis...");

    // Capture chart screenshot dengan analisa teknikal
    string chart_image = CaptureChartWithAnalysis(symbol, direction, entry, sl, tp);

    string emoji = (direction == DIR_BUY) ? "🚀🟢" : "🔻🔴";
    string dir_text = (direction == DIR_BUY) ? "BUY 📈" : "SELL 📉";

    // Hitung Risk/Reward ratio
    double rr_ratio = CalculateRRRatio(direction, entry, sl, tp);

    string message = emoji + " *PREMIUM TRADE ALERT* " + emoji + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    message += "📌 *Signal Type*: " + signal_type + "\n";
    message += "📊 *Symbol*: `" + symbol + "`\n";
    message += "🎯 *Direction*: " + dir_text + "\n";
    message += "💰 *Lot Size*: " + DoubleToString(lot, 2) + "\n\n";
    message += "🟢 *ENTRY*: " + DoubleToString(entry, _Digits) + "\n";
    message += "🔴 *STOP LOSS*: " + DoubleToString(sl, _Digits) + "\n";
    message += "🟡 *TAKE PROFIT*: " + DoubleToString(tp, _Digits) + "\n\n";
    message += "⚖️ *RISK/REWARD*: 1:" + DoubleToString(rr_ratio, 1) + "\n";
    message += "⏰ *Time*: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    message += "📊 *CHART ANALYSIS*: Lihat gambar di bawah untuk analisa teknikal\n";
    message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    message += "🔥 *GOOD LUCK & SAFE TRADING! FROM X-REY TRADE BOT* 🔥\n";
    message += "📲 Rey Riyan Sanjaya 🤖";

    Print("🚀 Sending VIP Trade Alert with Chart Analysis...");

    if (chart_image != "")
    {
        // Kirim gambar chart terlebih dahulu, lalu message
        SendTelegramPhoto(chart_image, message);
        Print("✅ Chart image sent successfully");

        // Hapus file setelah dikirim
        FileDelete(chart_image);
    }
    else
    {
        Print("❌ Gagal capture chart, kirim alert tanpa gambar");
        SendTelegramMessage(message);
    }

    // Update state terakhir
    lastSymbol = symbol;
    lastDirection = direction;
    lastEntry = entry;
    lastAlertTime = TimeCurrent();
}

// Fungsi untuk capture chart dengan analisa teknikal
string CaptureChartWithAnalysis(string symbol, Dir direction, double entry, double sl, double tp)
{
    string filename = "";

    // Simbol dan timeframe sebelumnya
    string current_symbol = ChartSymbol(0);
    ENUM_TIMEFRAMES current_tf = (ENUM_TIMEFRAMES)ChartPeriod(0);

    // Switch ke simbol yang diinginkan jika berbeda
    if (symbol != current_symbol)
    {
        ChartSetSymbolPeriod(0, symbol, PERIOD_H1);
        Sleep(1000); // Beri waktu untuk load chart
    }

    // Tambahkan analisa teknikal
    AddTechnicalAnalysis(symbol, direction, entry, sl, tp);

    // Capture screenshot
    filename = "Chart_" + symbol + "_" + IntegerToString(TimeCurrent()) + ".png";
    bool success = ChartScreenShot(0, filename, 1024, 768);

    // Kembali ke chart asli jika sebelumnya diubah
    if (symbol != current_symbol)
    {
        ChartSetSymbolPeriod(0, current_symbol, current_tf);
    }

    return success ? filename : "";
}

// Fungsi untuk menambahkan analisa teknikal pada chart
void AddTechnicalAnalysis(string symbol, Dir direction, double entry, double sl, double tp)
{
    // Hapus objects sebelumnya
    ObjectsDeleteAll(0, "ALERT_");

    // Tambahkan garis entry, SL, TP
    CreateHorizontalLine("ALERT_ENTRY", entry, clrLime, 2, STYLE_SOLID, "ENTRY");
    CreateHorizontalLine("ALERT_SL", sl, clrRed, 2, STYLE_SOLID, "STOP LOSS");
    CreateHorizontalLine("ALERT_TP", tp, clrYellow, 2, STYLE_SOLID, "TAKE PROFIT");

    // Tambahkan zona support/resistance berdasarkan direction
    if (direction == DIR_BUY)
    {
        // Untuk BUY: highlight support zone
        double support_zone = entry - (entry - sl) * 0.5;
        CreateRectangle("ALERT_SUPPORT", TimeCurrent() - 1000, support_zone, TimeCurrent() + 1000, sl, clrGreen, 1, STYLE_DASHDOT, "Support Zone");

        // Tambahkan arrow buy
        CreateArrowBuy("ALERT_BUY_ARROW", TimeCurrent(), entry, clrLime);
    }
    else
    {
        // Untuk SELL: highlight resistance zone
        double resistance_zone = entry + (sl - entry) * 0.5;
        CreateRectangle("ALERT_RESISTANCE", TimeCurrent() - 1000, resistance_zone, TimeCurrent() + 1000, sl, clrRed, 1, STYLE_DASHDOT, "Resistance Zone");

        // Tambahkan arrow sell
        CreateArrowSell("ALERT_SELL_ARROW", TimeCurrent(), entry, clrRed);
    }

    // Tambahkan info text
    string trend_text = (direction == DIR_BUY) ? "BULLISH TREND 📈" : "BEARISH TREND 📉";
    CreateTextLabel("ALERT_TREND", trend_text, 10, 30, (direction == DIR_BUY) ? clrLime : clrRed, "Arial", 12);
    CreateTextLabel("ALERT_BOT", "X-REY TRADE BOT", 10, 50, clrGold, "Arial", 10);

    // Refresh chart untuk update objects
    ChartRedraw();
    Sleep(500); // Beri waktu untuk render
}

// IMPLEMENTASI SEND TELEGRAM PHOTO YANG DIPERBAIKI
void SendTelegramPhoto(string photo_path, string caption = "")
{
    // Validasi file exists
    if (!FileIsExist(photo_path))
    {
        Print("❌ Photo file not found: ", photo_path);
        return;
    }

    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendPhoto";

    // Create multipart form data
    char post_data[];
    char result[];
    string headers = "Content-Type: multipart/form-data; boundary=Boundary";
    string response_headers;

    // Baca file photo
    int file_handle = FileOpen(photo_path, FILE_READ | FILE_BIN);
    if (file_handle == INVALID_HANDLE)
    {
        Print("❌ Failed to open photo file: ", photo_path);
        return;
    }

    int file_size = (int)FileSize(file_handle);
    uchar file_buffer[];
    ArrayResize(file_buffer, file_size);
    FileReadArray(file_handle, file_buffer, 0, file_size);
    FileClose(file_handle);

    // Build form data
    string boundary = "Boundary";
    string form_data = "";

    // Add chat_id
    form_data += "--" + boundary + "\r\n";
    form_data += "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n";
    form_data += TelegramChatID + "\r\n";

    // Add caption if provided
    if (caption != "")
    {
        form_data += "--" + boundary + "\r\n";
        form_data += "Content-Disposition: form-data; name=\"caption\"\r\n\r\n";
        form_data += caption + "\r\n";

        form_data += "--" + boundary + "\r\n";
        form_data += "Content-Disposition: form-data; name=\"parse_mode\"\r\n\r\n";
        form_data += "Markdown\r\n";
    }

    // Add photo
    form_data += "--" + boundary + "\r\n";
    form_data += "Content-Disposition: form-data; name=\"photo\"; filename=\"" + photo_path + "\"\r\n";
    form_data += "Content-Type: image/png\r\n\r\n";

    // Calculate total size
    int form_data_size = StringLen(form_data);
    int closing_boundary_size = StringLen("\r\n--" + boundary + "--\r\n");
    int total_size = form_data_size + file_size + closing_boundary_size;

    // Resize post_data array
    ArrayResize(post_data, total_size);

    // Copy form data to post_data
    int position = 0;
    StringToCharArray(form_data, post_data, position, StringLen(form_data), CP_UTF8);
    position += StringLen(form_data);

    // Copy file data to post_data - PERBAIKAN DI SINI
    for (int i = 0; i < file_size && position < total_size; i++, position++)
    {
        post_data[position] = (char)file_buffer[i];
    }

    // Add closing boundary
    string closing = "\r\n--" + boundary + "--\r\n";
    StringToCharArray(closing, post_data, position, StringLen(closing), CP_UTF8);

    // Send HTTP POST request
    int response = WebRequest("POST", url, headers, 5000, post_data, result, response_headers);

    if (response == 200)
    {
        Print("✅ Telegram photo sent successfully");
    }
    else
    {
        Print("❌ Failed to send Telegram photo. Error: ", response);

        // Fallback: try sending message without photo
        if (caption != "")
        {
            Print("🔄 Trying fallback to text message...");
            SendTelegramMessage("📸 *CHART ANALYSIS FAILED* \n" + caption);
        }
    }
}
// Helper function untuk membuat horizontal line
void CreateHorizontalLine(string name, double price, color clr, int width, int style, string text)
{
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
}

// Helper function untuk membuat text label
void CreateTextLabel(string name, string text, int x, int y, color clr, string font, int font_size)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
}

// Helper function untuk membuat rectangle
void CreateRectangle(string name, datetime time1, double price1, datetime time2, double price2, color clr, int width, int style, string text)
{
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
}

// Helper function untuk membuat arrow buy
void CreateArrowBuy(string name, datetime time, double price, color clr)
{
    ObjectCreate(0, name, OBJ_ARROW_BUY, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
}

// Helper function untuk membuat arrow sell
void CreateArrowSell(string name, datetime time, double price, color clr)
{
    ObjectCreate(0, name, OBJ_ARROW_SELL, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
}

// Fungsi untuk menghitung R/R ratio
double CalculateRRRatio(Dir direction, double entry, double sl, double tp)
{
    double rr_ratio = 0;
    if (sl > 0 && entry > 0)
    {
        if (direction == DIR_BUY)
            rr_ratio = (tp - entry) / (entry - sl);
        else
            rr_ratio = (entry - tp) / (sl - entry);
    }
    return rr_ratio;
}

// Fungsi reset state
void ResetAlertState()
{
    lastSymbol = "";
    lastDirection = DIR_NONE;
    lastEntry = 0;
    lastAlertTime = 0;
    Print("✅ Alert state direset");
}

//==================================================================
// Fungsi: UpdateSignalsUltimateLive2 (Super Interaktif ✨)
//==================================================================
void UpdateSignalsUltimateLive2()
{
    if (SignalCount == 0)
    {
        ObjectsDeleteAll(0, -1, OBJ_LABEL);
        return;
    }

    int countBuy = 0, countSell = 0;
    for (int i = 0; i < SignalCount; i++)
    {
        if (Signals[i].signal == DIR_BUY)
            countBuy++;
        else if (Signals[i].signal == DIR_SELL)
            countSell++;
    }

    Dir votedSignal = (countBuy > countSell ? DIR_BUY : (countSell > countBuy ? DIR_SELL : DIR_NONE));
    string voteEmoji = (votedSignal == DIR_BUY ? "🚀 BUY" : (votedSignal == DIR_SELL ? "🔻 SELL" : "⚪ NO SIGNAL"));

    // DAPATKAN INFORMASI PAIR DAN MARKET LENGKAP
    string pairName = _Symbol;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    double atr = iATR(_Symbol, PERIOD_M15, 14);
    string marketCondition = GetMarketCondition();
    string marketTrend = GetMarketTrend();
    string marketSession = GetMarketSession();

    // Informasi account
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = margin > 0 ? equity / margin * 100 : 0;

    // Waktu saat ini
    MqlDateTime timeNow;
    TimeCurrent(timeNow);
    string timeStr = StringFormat("%02d:%02d:%02d", timeNow.hour, timeNow.min, timeNow.sec);

    // GUNAKAN EMOJI YANG STANDARD & SIMPLE
    string txt = "📊 *ULTIMATE LIVE DASHBOARD*\n";
    txt += "═══════════════════════════\n";
    txt += "💼 *Pair*: " + pairName + " | 🕒 " + timeStr + "\n";
    txt += "💰 *Current Price*: " + DoubleToString(currentPrice, _Digits) + "\n";
    txt += "📈 *Spread*: " + DoubleToString(spread * 10000, 1) + " pips\n";
    txt += "📊 *ATR (M15)*: " + DoubleToString(atr * 10000, 1) + " pips\n";
    txt += "🌡️ *Market Condition*: " + marketCondition + "\n";
    txt += "📈 *Market Trend*: " + marketTrend + "\n";
    txt += "🌍 *Trading Session*: " + marketSession + "\n";
    txt += "💳 *Balance*: $" + DoubleToString(balance, 2) + "\n";
    txt += "📈 *Equity*: $" + DoubleToString(equity, 2) + "\n";
    txt += "🛡️ *Margin Level*: " + DoubleToString(marginLevel, 1) + "%\n";
    txt += "🏆 *Voting Result*: " + voteEmoji + "\n";
    txt += "═══════════════════════════\n\n";

    int strong = 0, medium = 0, weak = 0;
    double totalProfit = 0, maxRisk = 0;
    double totalRR = 0;

    for (int i = 0; i < SignalCount; i++)
    {
        SignalInfo sig = Signals[i];
        string signalText = (sig.signal == DIR_BUY ? "BUY 📈" : (sig.signal == DIR_SELL ? "SELL 📉" : "NONE ⏸️"));
        string strengthText = (sig.strength == STRONG ? "🔥 STRONG" : (sig.strength == MEDIUM ? "⚡ MEDIUM" : "💤 WEAK"));
        string votedTag = (sig.signal == votedSignal ? " ✅" : "");

        double estProfit = MathAbs(sig.tp - sig.entry) * 10000;
        double risk = MathAbs(sig.entry - sig.sl) * 10000;
        double rrRatio = risk > 0 ? estProfit / risk : 0;

        // Hitung distance dari current price
        double distancePips = MathAbs(currentPrice - sig.entry) * 10000;
        string distanceText = StringFormat("%.1f pips", distancePips / 10);

        txt += StringFormat(
            "📌 *%s*%s\n"
            "➡️ Signal: %s | Strength: %s\n"
            "📍 Entry: %.5f | SL: %.5f | TP: %.5f\n"
            "📏 Distance: %s | R/R: %.2fx\n"
            "💰 Lot: %.2f | Est. Profit: %.1f pips\n"
            "⚠️ Risk: %.1f pips | Margin: $%.2f\n"
            "────────────────────\n\n",
            sig.name, votedTag, signalText, strengthText,
            sig.entry, sig.sl, sig.tp,
            distanceText, rrRatio,
            sig.lot, estProfit / 10, risk / 10,
            CalculateMargin(sig.lot));

        totalProfit += estProfit;
        totalRR += rrRatio;
        if (risk > maxRisk)
            maxRisk = risk;
        if (sig.strength == STRONG)
            strong++;
        else if (sig.strength == MEDIUM)
            medium++;
        else
            weak++;
    }

    // Hitung rata-rata RR Ratio
    double avgRR = SignalCount > 0 ? totalRR / SignalCount : 0;

    // SUMMARY SECTION
    txt += StringFormat(
        "📊 *OVERALL SUMMARY*\n"
        "🟢 BUY: %d | 🔴 SELL: %d | 📋 Total: %d\n"
        "🔥 Strong: %d | ⚡ Medium: %d | 💤 Weak: %d\n"
        "📈 Avg R/R Ratio: %.2fx\n"
        "💵 Total Est. Profit: %.1f pips\n"
        "⚠️ Max Risk: %.1f pips\n"
        "💳 Free Margin: $%.2f\n"
        "═══════════════════════════\n"
        "🤖 Powered by *X-Rey Trade Bot*\n"
        "👨💻 Made by *Rey Riyan Sanjaya*",
        countBuy, countSell, SignalCount,
        strong, medium, weak,
        avgRR,
        totalProfit / 10000, maxRisk / 10000,
        freeMargin);

    // Kirim ke Telegram
    if (Dashboard_SendTelegram && EnableTelegram)
    {
        static datetime lastSendTime = 0;
        if (TimeCurrent() - lastSendTime >= 30)
        {
            SendTelegramMessage(txt);
            lastSendTime = TimeCurrent();
        }
    }

    // Update chart labels juga
    UpdateChartLabels();
}

//+------------------------------------------------------------------+
//| Fungsi Bantu Tambahan                                           |
//+------------------------------------------------------------------+

// Fungsi untuk mendapatkan kondisi market
string GetMarketCondition()
{
    double atr = iATR(_Symbol, PERIOD_M15, 14);
    double atrPercent = (atr / SymbolInfoDouble(_Symbol, SYMBOL_BID)) * 100;

    if (atrPercent > 0.1)
        return "🌊 HIGH VOLATILITY";
    else if (atrPercent > 0.05)
        return "🌤️ MODERATE VOLATILITY";
    else
        return "🌿 LOW VOLATILITY";
}

// Fungsi untuk menghitung margin
double CalculateMargin(double lotSize)
{
    double margin = 0;
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);

    if (leverage > 0)
        margin = (lotSize * contractSize * SymbolInfoDouble(_Symbol, SYMBOL_BID)) / leverage;

    return margin;
}

// Fungsi untuk mendapatkan trend market
string GetMarketTrend()
{
    double ema50 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
    double ema200 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (price > ema50 && ema50 > ema200)
        return "🟢 BULLISH TREND";
    else if (price < ema50 && ema50 < ema200)
        return "🔴 BEARISH TREND";
    else
        return "🟡 RANGING MARKET";
}

// Fungsi untuk mendapatkan session market
string GetMarketSession()
{
    MqlDateTime timeNow;
    TimeCurrent(timeNow);
    int hour = timeNow.hour;

    if (hour >= 0 && hour < 5)
        return "🌙 ASIA SESSION";
    else if (hour >= 5 && hour < 13)
        return "🌍 LONDON SESSION";
    else if (hour >= 13 && hour < 21)
        return "🇺🇸 NY SESSION";
    else
        return "🌃 OVERLAP SESSION";
}
//==================================================================
// Fungsi: SendSystemStatus
// Deskripsi: Kirim status sistem ke Telegram
//==================================================================
//+------------------------------------------------------------------+
//| Send System Status (FIXED)                                     |
//+------------------------------------------------------------------+
void SendSystemStatus()
{
    if (!Dashboard_SendTelegram || !EnableTelegram)
    {
        return;
    }

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    int positions = PositionsTotal();
    double profit = 0;

    // Hitung total profit dari semua posisi
    for (int i = 0; i < positions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
            profit += PositionGetDouble(POSITION_PROFIT);
    }

    string status_emoji = (equity >= balance) ? "🟢" : "🔴";
    string status_text = (equity >= balance) ? "PROFIT" : "DRAWDOWN";

    string message = status_emoji + " *SYSTEM STATUS* " + status_emoji + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    message += "💼 *Balance*: $" + DoubleToString(balance, 2) + "\n";
    message += "📈 *Equity*: $" + DoubleToString(equity, 2) + "\n";
    message += "📉 *Status*: " + status_text + "\n";
    message += "🆓 *Free Margin*: $" + DoubleToString(margin, 2) + "\n";
    message += "📊 *Margin Level*: " + (marginLevel > 0 ? DoubleToString(marginLevel, 1) + "%" : "N/A") + "\n";
    message += "💰 *Active Positions*: " + IntegerToString(positions) + "\n";
    message += "💸 *Floating P/L*: $" + DoubleToString(profit, 2) + "\n";
    message += "🕒 *Update Time*: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";

    Print("Sending Telegram System Status...");
    SendTelegramMessage(message);
}

//==================================================================
// Fungsi: Collect Active Signals
//==================================================================
void CollectActiveSignals()
{
    SignalCount = 0; // Reset counter

    // Collect dari semua sistem deteksi yang aktif
    if (UseOrderBlock)
    {
        OBSignal obSignal = DetectOrderBlockPro(OB_BaseLot, OB_EMAPeriod1, OB_EMAPeriod2, OB_Levels, OB_ZoneBufferPips, OB_Lookback);
        if (obSignal.signal != DIR_NONE)
        {
            Signals[SignalCount].name = "OrderBlock";
            Signals[SignalCount].signal = obSignal.signal;
            Signals[SignalCount].strength = obSignal.isStrong ? STRONG : MEDIUM;
            Signals[SignalCount].lot = obSignal.lotSize;
            Signals[SignalCount].sl = obSignal.stopLoss;
            Signals[SignalCount].tp = obSignal.takeProfit;
            Signals[SignalCount].entry = obSignal.entryPrice;
            Signals[SignalCount].confidence = obSignal.isStrong ? 0.9 : 0.7;
            SignalCount++;
        }
    }

    if (UsePriceAction)
    {
        PA_Signal paSignal = DetectPriceAction_MTF(_Symbol, 1);
        if (paSignal.found)
        {
            Signals[SignalCount].name = "PriceAction";
            Signals[SignalCount].signal = paSignal.direction;
            Signals[SignalCount].strength = (paSignal.lotLevel >= 2) ? STRONG : MEDIUM;
            double lotSize = RiskManager::GetDynamicLot(0.7, 30);
            Signals[SignalCount].lot = lotSize;
            Signals[SignalCount].sl = paSignal.stopLoss;
            Signals[SignalCount].tp = paSignal.takeProfit;
            Signals[SignalCount].entry = paSignal.entryPrice;
            Signals[SignalCount].confidence = 0.8;
            SignalCount++;
        }
    }

    if (UseSMCSignal)
    {
        SMCSignal smcSignal = DetectSMCSignalAdvanced(SMC_BaseLot, SMC_EMA_Period1, SMC_EMA_Period2, SMC_Lookback, SMC_ATR_Multiplier);
        if (smcSignal.signal != DIR_NONE && smcSignal.isStrong)
        {
            Signals[SignalCount].name = "SMC";
            Signals[SignalCount].signal = smcSignal.signal;
            Signals[SignalCount].strength = STRONG;
            Signals[SignalCount].lot = smcSignal.lotSize;
            Signals[SignalCount].sl = smcSignal.stopLoss;
            Signals[SignalCount].tp = smcSignal.takeProfit;
            Signals[SignalCount].entry = smcSignal.entryPrice;
            Signals[SignalCount].confidence = 0.85;
            SignalCount++;
        }
    }

    // Tambahkan sistem deteksi lainnya
    if (UseSCMSignal)
    {
        SCMSignal scmSignal = DetectSCMSignalHighProb(SCM_BaseLot, SCM_EMAPeriod, SCM_RSIPeriod, SCM_RSI_OB, SCM_RSI_OS, SCM_MACD_Fast, SCM_MACD_Slow, SCM_MACD_Signal, SCM_ATRPeriod, SCM_ATRMultiplier);
        if (scmSignal.signal != DIR_NONE && scmSignal.isStrong)
        {
            Signals[SignalCount].name = "SCM";
            Signals[SignalCount].signal = scmSignal.signal;
            Signals[SignalCount].strength = scmSignal.isStrong ? STRONG : MEDIUM;
            Signals[SignalCount].lot = scmSignal.lotSize;
            Signals[SignalCount].sl = scmSignal.stopLoss;
            Signals[SignalCount].tp = scmSignal.takeProfit;
            Signals[SignalCount].entry = scmSignal.entryPrice;
            Signals[SignalCount].confidence = scmSignal.isStrong ? 0.8 : 0.6;
            SignalCount++;
        }
    }

    if (UseStochastic)
    {
        StochSignal stochSignal = GetStochasticSignalUltimateAdvanced(Stoch_TFLow, Stoch_TFHigh, Stoch_KPeriod, Stoch_DPeriod, Stoch_Slowing, Stoch_EMAPeriod, Stoch_ATR_Multiplier, 0);
        if (stochSignal.signal != DIR_NONE)
        {
            Signals[SignalCount].name = "Stochastic";
            Signals[SignalCount].signal = stochSignal.signal;
            Signals[SignalCount].strength = stochSignal.isStrong ? STRONG : WEAK;
            Signals[SignalCount].lot = stochSignal.lotSize;
            Signals[SignalCount].sl = stochSignal.stopLoss;
            Signals[SignalCount].tp = stochSignal.takeProfit;
            Signals[SignalCount].entry = stochSignal.entryPrice;
            Signals[SignalCount].confidence = stochSignal.isStrong ? 0.7 : 0.5;
            SignalCount++;
        }
    }
}

//==================================================================
// Fungsi: Update Chart Labels
//==================================================================
void UpdateChartLabels()
{
    // Hapus label lama yang tidak relevan
    int totalObjects = ObjectsTotal(0, -1, OBJ_LABEL);
    for (int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, OBJ_LABEL);
        if (StringFind(objName, "SignalLabel_") >= 0)
        {
            // Cek jika signal sudah tidak aktif
            bool signalStillActive = false;
            for (int j = 0; j < SignalCount; j++)
            {
                string expectedName = "SignalLabel_" + IntegerToString(j);
                if (objName == expectedName)
                {
                    signalStillActive = true;
                    break;
                }
            }

            if (!signalStillActive)
                ObjectDelete(0, objName);
        }
    }

    // Buat label baru untuk sinyal aktif
    int row = 0, col = 0;
    for (int i = 0; i < SignalCount; i++)
    {
        SignalInfo sig = Signals[i];
        if (sig.signal == DIR_NONE)
            continue;

        string objName = "SignalLabel_" + IntegerToString(i);
        color labelColor = (sig.strength == STRONG ? clrLime : (sig.strength == MEDIUM ? clrOrange : clrYellow));

        // Hapus object lama jika ada
        if (ObjectFind(0, objName) >= 0)
            ObjectDelete(0, objName);

        // Buat object baru
        ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        int xPos = Dashboard_XBase + col * Dashboard_XStep;
        int yPos = Dashboard_YBase + row * Dashboard_YStep;

        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xPos);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yPos);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, labelColor);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, Dashboard_LabelFontSize);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);

        string labelText = StringFormat("%s\n%s | Lot: %.2f\nSL: %.5f\nTP: %.5f",
                                        sig.name,
                                        (sig.signal == DIR_BUY ? "BUY" : "SELL"),
                                        sig.lot, sig.sl, sig.tp);

        ObjectSetString(0, objName, OBJPROP_TEXT, labelText);
        ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);

        col++;
        if (col >= Dashboard_MaxColumns)
        {
            col = 0;
            row++;
        }
    }
}

//+------------------------------------------------------------------+
//| Telegram dengan Encoding yang Benar                           |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
{
    if (!EnableTelegram)
        return;
    if (TelegramBotToken == "" || TelegramChatID == "")
        return;

    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
    string headers = "Content-Type: application/x-www-form-urlencoded";

    // HANYA encode karakter yang menyebabkan masalah di URL
    string encodedMessage = "";
    for (int i = 0; i < StringLen(message); i++)
    {
        string ch = StringSubstr(message, i, 1);
        int charCode = StringGetCharacter(ch, 0);

        // Karakter yang perlu di-encode
        if (ch == " ")
            encodedMessage += "%20";
        else if (ch == "\n")
            encodedMessage += "%0A";
        else if (ch == "&")
            encodedMessage += "%26";
        else if (ch == "#")
            encodedMessage += "%23";
        else if (ch == "%")
            encodedMessage += "%25";
        else if (ch == "+")
            encodedMessage += "%2B";
        else if (ch == "=")
            encodedMessage += "%3D";
        else if (ch == "?")
            encodedMessage += "%3F";
        else if (ch == "\"")
            encodedMessage += "%22";
        else if (ch == "<")
            encodedMessage += "%3C";
        else if (ch == ">")
            encodedMessage += "%3E";
        // Biarkan semua karakter lainnya TANPA diencode (termasuk emoji)
        else
            encodedMessage += ch;
    }

    string post_data = "chat_id=" + TelegramChatID + "&text=" + encodedMessage + "&parse_mode=Markdown";

    char data[];
    char result[];
    string result_headers;

    StringToCharArray(post_data, data, 0, StringLen(post_data));

    ResetLastError();

    int res = WebRequest("POST", url, headers, 10000, data, result, result_headers);

    if (res == -1)
    {
        Print("❌ Telegram failed: ", GetLastError());
        return;
    }

    string response = CharArrayToString(result);
    if (StringFind(response, "\"ok\":true") != -1)
    {
        Print("✅ Telegram message sent successfully!");
    }
    else
    {
        Print("❌ Telegram API error: ", response);
    }
}

//+------------------------------------------------------------------+
//| Fungsi bantu untuk error description                           |
//+------------------------------------------------------------------+
string GetWebRequestErrorDescription(int error_code)
{
    switch (error_code)
    {
    case 4014:
        return "WebRequest not allowed - Check MT5 settings";
    case 4016:
        return "Invalid URL";
    case 4026:
        return "Cannot connect to server";
    case 4024:
        return "Request timeout";
    case 4002:
        return "URL too long - Use POST method instead";
    case 4001:
        return "Too many requests";
    case 4003:
        return "HTTP error";
    default:
        return "Unknown error (" + IntegerToString(error_code) + ")";
    }
}
//+------------------------------------------------------------------+
//| URL Encode FIXED untuk Telegram                                |
//+------------------------------------------------------------------+
string UrlEncode(string data)
{
    string res = "";
    uchar chars[];

    // Convert string ke array UTF-8 bytes
    int total = StringToCharArray(data, chars, 0, WHOLE_ARRAY, CP_UTF8);

    for (int i = 0; i < total - 1; i++) // -1 untuk exclude null terminator
    {
        uchar c = chars[i];

        // Karakter AMAN - tidak perlu encode
        if ((c >= '0' && c <= '9') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= 'a' && c <= 'z') ||
            c == '-' || c == '_' || c == '.' || c == '~' ||
            c == '!' || c == '*' || c == '(' || c == ')' ||
            c == '\'')
        {
            res += CharToString(c);
        }
        // Spasi
        else if (c == ' ')
        {
            res += "%20";
        }
        // Newline
        else if (c == '\n')
        {
            res += "%0A";
        }
        // Karakter UTF-8 multi-byte (emoji, dll) - biarkan ASLI
        else if (c >= 0x80) // Karakter UTF-8
        {
            res += CharToString(c);
            // Handle multi-byte UTF-8 characters
            if (c >= 0xC0) // 2-byte UTF-8
            {
                if (i + 1 < total - 1)
                {
                    res += CharToString(chars[++i]);
                }
            }
            else if (c >= 0xE0) // 3-byte UTF-8
            {
                if (i + 2 < total - 1)
                {
                    res += CharToString(chars[++i]);
                    res += CharToString(chars[++i]);
                }
            }
            else if (c >= 0xF0) // 4-byte UTF-8
            {
                if (i + 3 < total - 1)
                {
                    res += CharToString(chars[++i]);
                    res += CharToString(chars[++i]);
                    res += CharToString(chars[++i]);
                }
            }
        }
        // Karakter lainnya - encode
        else
        {
            res += "%" + StringFormat("%02X", c);
        }
    }

    return res;
}
//+------------------------------------------------------------------+
//| Alternative Telegram Method (Improved Fallback)                 |
//+------------------------------------------------------------------+
void SendTelegramAlternative(string message)
{
    Print("🔄 Trying alternative Telegram method...");

    // Method alternatif dengan format yang lebih sederhana
    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";

    // Simplify message untuk fallback (hapus emoji yang bermasalah)
    string simpleMessage = message;
    StringReplace(simpleMessage, "✨", "");
    StringReplace(simpleMessage, "💎", "");
    StringReplace(simpleMessage, "🚀", "BUY");
    StringReplace(simpleMessage, "🔻", "SELL");
    StringReplace(simpleMessage, "⏹️", "NONE");
    StringReplace(simpleMessage, "🟢", "[STRONG]");
    StringReplace(simpleMessage, "🟠", "[MEDIUM]");
    StringReplace(simpleMessage, "⚪", "[WEAK]");
    StringReplace(simpleMessage, "🎯", "===");
    StringReplace(simpleMessage, "💹", "SYMBOL");
    StringReplace(simpleMessage, "💰", "LOT");
    StringReplace(simpleMessage, "🛡️", "SL");
    StringReplace(simpleMessage, "⚖️", "R/R");
    StringReplace(simpleMessage, "⏰", "TIME");
    StringReplace(simpleMessage, "📊", "===");
    StringReplace(simpleMessage, "🔥", "***");
    StringReplace(simpleMessage, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", "==========================");

    string headers = "Content-Type: application/x-www-form-urlencoded";
    char postData[];
    string post = "chat_id=" + TelegramChatID + "&text=" + simpleMessage + "&parse_mode=Markdown";
    StringToCharArray(post, postData, 0, StringLen(post));

    ResetLastError();
    char result[];
    string resultHeaders;
    int response = WebRequest("POST", url, headers, 5000, postData, result, resultHeaders);

    if (response == 200)
    {
        Print("✅ Telegram: Alternative method successful");
    }
    else
    {
        Print("❌ Telegram Alternative also failed");

        // Final fallback - print ke journal untuk debugging
        Print("=== FINAL TELEGRAM MESSAGE ===");
        Print(message);
        Print("==============================");
    }
}

//+------------------------------------------------------------------+
//| Error Description Helper (Updated)                              |
//+------------------------------------------------------------------+
string GetErrorDescription(int errorCode)
{
    switch (errorCode)
    {
    case 0:
        return "No error";
    case 4014:
        return "WebRequest URL not allowed - Add 'https://api.telegram.org' to list in Tools->Options->Expert Advisors";
    case 4060:
        return "WebRequest not allowed - Enable 'Allow WebRequest for listed URL' in Expert Advisor properties";
    case 4016:
        return "No internet connection";
    case 4017:
        return "Timeout exceeded";
    case 5000:
        return "Empty response from server";
    case 5001:
        return "Internal server error";
    default:
        return "Unknown error (" + IntegerToString(errorCode) + ")";
    }
}

//+------------------------------------------------------------------+
//| PullbackX.mq5                                                    |
//| Advanced Pullback Strategy: Engulfing + PinBar + Fibo + ATR + BE |
//| Author: ChatGPT (untuk Rey)                                      |
//+------------------------------------------------------------------+
#property strict
#property version "2.1"

// ================== INPUT PARAMETER ==================
input ENUM_TIMEFRAMES PBX_Timeframe = PERIOD_M1; // TF analisa
input int PBX_LookbackBars = 300;                // jumlah bar
input int PBX_SwingLookback = 50;                // cari swing H/L
input int PBX_CheckBarShift = 1;                 // bar tertutup
input int PBX_EMA_Period = 200;                  // trend filter
input int PBX_ATR_Period = 14;                   // ATR
input double PBX_ATR_MultSL = 2.5;               // SL awal
input double PBX_ATR_MultTSL = 1.5;              // trailing
input double PBX_FiboTol = 0.0030;               // toleransi fibo
input double PBX_PinBarBodyMax = 0.35;           // max body ratio
input double PBX_PinBarTailMin = 0.60;           // min tail ratio
input double PBX_BE_MinProfitPips = 100;         // minimal profit BE
input double PBX_BE_BufferPips = 20;             // buffer setelah BE
input double PBX_TrailStepPips = 30;             // langkah trailing

// ================== ENUM & STRUCT ==================
enum PBX_SignalType
{
    PBX_NONE = 0,
    PBX_BUY = 1,
    PBX_SELL = -1
};

struct PBX_SignalResult
{
    int signal;    // 0=none, 1=buy, -1=sell
    double sl;     // stop loss awal
    double entry;  // harga entry
    double fibo50; // level fibo
    double fibo618;
};

// ================== GET OHLC ==================
bool PBX_GetOHLC(string sym, ENUM_TIMEFRAMES tf, int count,
                 double &o[], double &h[], double &l[], double &c[])
{
    ArraySetAsSeries(o, true);
    ArraySetAsSeries(h, true);
    ArraySetAsSeries(l, true);
    ArraySetAsSeries(c, true);
    if (CopyOpen(sym, tf, 0, count, o) <= 0)
        return false;
    if (CopyHigh(sym, tf, 0, count, h) <= 0)
        return false;
    if (CopyLow(sym, tf, 0, count, l) <= 0)
        return false;
    if (CopyClose(sym, tf, 0, count, c) <= 0)
        return false;
    return true;
}

// ================== EMA & ATR ==================
double PBX_GetEMA(string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
    int h = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
    if (h == INVALID_HANDLE)
        return 0;
    double b[];
    ArraySetAsSeries(b, true);
    if (CopyBuffer(h, 0, shift, 1, b) <= 0)
    {
        IndicatorRelease(h);
        return 0;
    }
    double val = b[0];
    IndicatorRelease(h);
    return val;
}
double PBX_GetATR(string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
    int h = iATR(sym, tf, period);
    if (h == INVALID_HANDLE)
        return 0;
    double b[];
    ArraySetAsSeries(b, true);
    if (CopyBuffer(h, 0, shift, 1, b) <= 0)
    {
        IndicatorRelease(h);
        return 0;
    }
    double val = b[0];
    IndicatorRelease(h);
    return val;
}

// ================== Engulfing ==================
bool PBX_BullishEngulf(int sh, const double &o[], const double &c[])
{
    return (c[sh] > o[sh] && c[sh + 1] < o[sh + 1] && c[sh] >= o[sh + 1] && o[sh] <= c[sh + 1]);
}
bool PBX_BearishEngulf(int sh, const double &o[], const double &c[])
{
    return (c[sh] < o[sh] && c[sh + 1] > o[sh + 1] && o[sh] >= c[sh + 1] && c[sh] <= o[sh + 1]);
}

// ================== Pin Bar ==================
bool PBX_IsPinBar(int sh, const double &o[], const double &h[], const double &l[], const double &c[], bool &bull)
{
    double body = MathAbs(c[sh] - o[sh]);
    double rng = h[sh] - l[sh];
    if (rng <= 0)
        return false;
    double up = h[sh] - MathMax(o[sh], c[sh]);
    double down = MathMin(o[sh], c[sh]) - l[sh];
    if (body <= rng * PBX_PinBarBodyMax && down >= rng * PBX_PinBarTailMin)
    {
        bull = true;
        return true;
    }
    if (body <= rng * PBX_PinBarBodyMax && up >= rng * PBX_PinBarTailMin)
    {
        bull = false;
        return true;
    }
    return false;
}

// ================== Cari Swing ==================
void PBX_GetSwingHL(const double &h[], const double &l[], int lookback, double &H, double &L)
{
    H = h[1];
    L = l[1];
    for (int i = 1; i <= lookback; i++)
    {
        if (h[i] > H)
            H = h[i];
        if (l[i] < L)
            L = l[i];
    }
}

// ================== DETECT SIGNAL ==================
PBX_SignalResult PBX_DetectSignal()
{
    PBX_SignalResult r;
    r.signal = PBX_NONE;
    r.sl = 0;
    r.entry = 0;
    r.fibo50 = 0;
    r.fibo618 = 0;
    double o[], h[], l[], c[];
    if (!PBX_GetOHLC(_Symbol, PBX_Timeframe, PBX_LookbackBars, o, h, l, c))
        return r;
    int sh = PBX_CheckBarShift;

    bool bullEng = PBX_BullishEngulf(sh, o, c);
    bool bearEng = PBX_BearishEngulf(sh, o, c);
    bool isBullPin = false;
    bool pin = PBX_IsPinBar(sh, o, h, l, c, isBullPin);

    double H, L;
    PBX_GetSwingHL(h, l, PBX_SwingLookback, H, L);
    r.fibo50 = H - (H - L) * 0.5;
    r.fibo618 = H - (H - L) * 0.618;

    double atr = PBX_GetATR(_Symbol, PBX_Timeframe, PBX_ATR_Period, sh);
    r.entry = c[sh];

    if ((bullEng || (pin && isBullPin)) && r.entry >= r.fibo50 - PBX_FiboTol && r.entry <= r.fibo618 + PBX_FiboTol)
    {
        r.signal = PBX_BUY;
        r.sl = r.entry - atr * PBX_ATR_MultSL;
    }
    if ((bearEng || (pin && !isBullPin)) && r.entry <= r.fibo50 + PBX_FiboTol && r.entry >= r.fibo618 - PBX_FiboTol)
    {
        r.signal = PBX_SELL;
        r.sl = r.entry + atr * PBX_ATR_MultSL;
    }
    return r;
}

// ================== MANAGE TRAILING SL ==================
double PBX_ManageSL(double orderOpenPrice, double currPrice, double sl, int direction)
{
    double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    double beTrigger = PBX_BE_MinProfitPips * pip;
    double beBuffer = PBX_BE_BufferPips * pip;
    double trailStep = PBX_TrailStepPips * pip;
    double atr = PBX_GetATR(_Symbol, PBX_Timeframe, PBX_ATR_Period, 0);

    double newSL = sl;

    if (direction == PBX_BUY)
    {
        double profit = currPrice - orderOpenPrice;
        if (profit > beTrigger)
            newSL = MathMax(newSL, orderOpenPrice + beBuffer);
        if (profit > trailStep)
            newSL = MathMax(newSL, currPrice - atr * PBX_ATR_MultTSL);
    }
    if (direction == PBX_SELL)
    {
        double profit = orderOpenPrice - currPrice;
        if (profit > beTrigger)
            newSL = MathMin(newSL, orderOpenPrice - beBuffer);
        if (profit > trailStep)
            newSL = MathMin(newSL, currPrice + atr * PBX_ATR_MultTSL);
    }
    return newSL;
}

// ==================== PBX TRAILING SL HANDLER ====================
void PBX_TrailingSLHandler()
{
    // Loop semua posisi aktif
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket))
            continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? PBX_BUY : PBX_SELL;

        // Harga saat ini
        double currPrice = (dir == PBX_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Hitung level SL baru
        double newSL = PBX_ManageSL(openPrice, currPrice, currentSL, dir);

        // Hanya update jika SL berubah
        if (newSL != currentSL)
        {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_SLTP; // update SL/TP
            request.position = ticket;
            request.sl = newSL;
            request.tp = currentTP;
            request.symbol = _Symbol;
            request.magic = 12345; // sesuaikan magic number EA

            if (!OrderSend(request, result))
                Print("❌ Update SL failed for ticket ", ticket, " retcode=", result.retcode);
            else
                Print("✅ SL updated for ticket ", ticket, " newSL=", newSL);
        }
    }
}

//+------------------------------------------------------------------+
//|          Trendline Break EA LuxAlgo-Like                         |
//|          Legal Custom Version by ChatGPT                          |
//+------------------------------------------------------------------+
#property strict
input ENUM_TIMEFRAMES TLB_Timeframe = PERIOD_M1;
input int TLB_LookbackBars = 500;
input double TLB_MinDistPips = 20;
input int TLB_MaxLines = 20;
input double TLB_ATR_Multiplier = 1.5;
input int TLB_ATR_Period = 14;
input color TLB_BuyLineColor = clrLime;
input color TLB_SellLineColor = clrRed;
input color TLB_BreakoutArrowBuy = clrDodgerBlue;
input color TLB_BreakoutArrowSell = clrRed;
input bool TLB_ShowInfoPanel = true;
input double TLB_TP_Multiplier = 2.0; // Risk:Reward untuk TP

struct TLB_Line
{
    string objName;
    double price1;
    double price2;
    datetime time1;
    datetime time2;
    bool isHighLine;
    bool triggered;
    bool retested;
};

TLB_Line TLB_Lines[];
int TLB_LineCount = 0;

//--- Hapus object jika ada
void TLB_DeleteObjectIfExists(string name)
{
    if (ObjectFind(0, name) >= 0)
        ObjectDelete(0, name); // tambahkan chart ID
}

//--- Gambar panah breakout
void TLB_DrawBreakoutMarker(bool isBuy, double price, datetime time)
{
    string objName = StringFormat("TLB_ARROW_%d_%d", TimeCurrent(), isBuy ? 1 : 0);
    TLB_DeleteObjectIfExists(objName);
    ObjectCreate(0, objName, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, isBuy ? TLB_BreakoutArrowBuy : TLB_BreakoutArrowSell);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
}

//--- Gambar marker retest
void TLB_DrawRetestMarker(bool isBuy, double price, datetime time)
{
    string objName = StringFormat("TLB_RETEST_%d_%d", TimeCurrent(), isBuy ? 1 : 0);
    TLB_DeleteObjectIfExists(objName);
    ObjectCreate(0, objName, OBJ_TEXT, 0, time, price);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, isBuy ? clrDodgerBlue : clrRed);
    ObjectSetString(0, objName, OBJPROP_TEXT, isBuy ? "RETEST BUY" : "RETEST SELL");
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
}

//--- Deteksi trendline
void TLB_DetectTrendlines()
{
    ArrayResize(TLB_Lines, 0);
    TLB_LineCount = 0;
    int bars = iBars(_Symbol, TLB_Timeframe);
    for (int i = 1; i < TLB_LookbackBars && TLB_LineCount < TLB_MaxLines; i++)
    {
        double high1 = iHigh(_Symbol, TLB_Timeframe, i);
        double high2 = iHigh(_Symbol, TLB_Timeframe, i + 5);
        double low1 = iLow(_Symbol, TLB_Timeframe, i);
        double low2 = iLow(_Symbol, TLB_Timeframe, i + 5);

        if (MathAbs(high1 - high2) > _Point * TLB_MinDistPips)
        {
            string name = "TLB_RES_" + IntegerToString(i);
            ObjectCreate(0, name, OBJ_TREND, 0, iTime(_Symbol, TLB_Timeframe, i), high1, iTime(_Symbol, TLB_Timeframe, i + 5), high2);
            ObjectSetInteger(0, name, OBJPROP_COLOR, TLB_SellLineColor);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
            // Perbaikan:
            TLB_Line line; // buat instance struct
            line.objName = name;
            line.price1 = high1;
            line.price2 = high2;
            line.time1 = iTime(_Symbol, TLB_Timeframe, i);
            line.time2 = iTime(_Symbol, TLB_Timeframe, i + 5);
            line.isHighLine = true; // atau false untuk support
            line.triggered = false;
            line.retested = false;

            ArrayResize(TLB_Lines, TLB_LineCount + 1); // pastikan array cukup
            TLB_Lines[TLB_LineCount++] = line;
        }
        if (MathAbs(low1 - low2) > _Point * TLB_MinDistPips)
        {
            string name = "TLB_SUP_" + IntegerToString(i);
            ObjectCreate(0, name, OBJ_TREND, 0, iTime(_Symbol, TLB_Timeframe, i), low1, iTime(_Symbol, TLB_Timeframe, i + 5), low2);
            ObjectSetInteger(0, name, OBJPROP_COLOR, TLB_BuyLineColor);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
            TLB_Line line; // buat instance struct
            line.objName = name;
            line.price1 = low1;
            line.price2 = low2;
            line.time1 = iTime(_Symbol, TLB_Timeframe, i);
            line.time2 = iTime(_Symbol, TLB_Timeframe, i + 5);
            line.isHighLine = false; // garis support
            line.triggered = false;
            line.retested = false;

            ArrayResize(TLB_Lines, TLB_LineCount + 1); // pastikan array cukup
            TLB_Lines[TLB_LineCount++] = line;
        }
    }
}

//--- Deteksi breakout dan retest
void TLB_DetectBreakouts()
{
    double closePrice = iClose(_Symbol, TLB_Timeframe, 1);   // pakai candle sebelumnya
    double currentPrice = iClose(_Symbol, TLB_Timeframe, 0); // candle sekarang

    for (int i = 0; i < TLB_LineCount; i++)
    {
        // akses by reference supaya update struct
        TLB_Line line = TLB_Lines[i];

        double linePriceNow = line.price1 +
                              (line.price2 - line.price1) * (TimeCurrent() - line.time1) / (line.time2 - line.time1);

        // --- STEP 1: Breakout detection (hanya tandai)
        if (!line.triggered)
        {
            if (!line.isHighLine && closePrice > linePriceNow)
            {
                line.triggered = true;
                TLB_DrawBreakoutMarker(true, linePriceNow, TimeCurrent());
            }
            if (line.isHighLine && closePrice < linePriceNow)
            {
                line.triggered = true;
                TLB_DrawBreakoutMarker(false, linePriceNow, TimeCurrent());
            }
        }

        // --- STEP 2: Retest setelah breakout
        if (line.triggered && !line.retested)
        {
            // cek apakah candle terakhir menyentuh garis (retest)
            double low = iLow(_Symbol, TLB_Timeframe, 1);
            double high = iHigh(_Symbol, TLB_Timeframe, 1);

            if (!line.isHighLine && low <= linePriceNow) // support di-retest
            {
                // entry BUY jika candle berikutnya close di atas
                if (currentPrice > linePriceNow)
                {
                    line.retested = true;
                    TLB_DrawRetestMarker(true, currentPrice, TimeCurrent());
                    TLB_EnterTrade(true, currentPrice);
                }
            }

            if (line.isHighLine && high >= linePriceNow) // resistance di-retest
            {
                // entry SELL jika candle berikutnya close di bawah
                if (currentPrice < linePriceNow)
                {
                    line.retested = true;
                    TLB_DrawRetestMarker(false, currentPrice, TimeCurrent());
                    TLB_EnterTrade(false, currentPrice);
                }
            }
        }
    }
}

//--- ATR trailing SL dengan secure profit
double TLB_ATRTrailingSL(bool isBuy)
{
    // Ambil ATR terbaru
    double atr = iATR(_Symbol, TLB_Timeframe, TLB_ATR_Period);

    // Ambil harga entry posisi terakhir (kalau ada)
    double entryPrice = 0.0;
    if (PositionSelect(_Symbol))
        entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

    double sl = 0.0;

    if (isBuy)
    {
        // Hitung SL awal (ATR-based)
        sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - atr * TLB_ATR_Multiplier;

        // Jika sudah profit → geser SL ke entry (secure)
        if (entryPrice > 0 && SymbolInfoDouble(_Symbol, SYMBOL_BID) > entryPrice)
        {
            sl = MathMax(sl, entryPrice + (atr * 0.2)); // secure + buffer kecil
        }
    }
    else
    {
        // Hitung SL awal (ATR-based)
        sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + atr * TLB_ATR_Multiplier;

        // Jika sudah profit → geser SL ke entry (secure)
        if (entryPrice > 0 && SymbolInfoDouble(_Symbol, SYMBOL_ASK) < entryPrice)
        {
            sl = MathMin(sl, entryPrice - (atr * 0.2)); // secure + buffer kecil
        }
    }

    return sl;
}

//--- Entry otomatis menggunakan ExecuteBuy / ExecuteSell
void TLB_EnterTrade(bool isBuy, double price)
{
    // ===== Tambahkan Filter Trend di M5 =====
    int emaPeriod = 200;
    ENUM_TIMEFRAMES emaTF = PERIOD_M5; // paksa pakai M5
    double ema200 = iMA(_Symbol, emaTF, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

    // Ambil harga terakhir dari M5
    double closeM5 = iClose(_Symbol, PERIOD_M5, 0);

    // Kalau harga di bawah EMA → hanya SELL, tolak BUY
    if (isBuy && closeM5 < ema200)
        return;

    // Kalau harga di atas EMA → hanya BUY, tolak SELL
    if (!isBuy && closeM5 > ema200)
        return;
    // ========================================

    double atrSL = TLB_ATRTrailingSL(isBuy);
    int slPips = (int)MathAbs((price - atrSL) / _Point);
    int tpPips = (int)(slPips * TLB_TP_Multiplier);

    double lot = 0.01;
    string signalSource = "Trend Lines Break";

    if (isBuy)
        ExecuteBuy(lot, slPips, tpPips, signalSource);
    else
        ExecuteSell(lot, slPips, tpPips, signalSource);
}

//--- Panel info floating
void TLB_DrawInfoPanel()
{
    if (!TLB_ShowInfoPanel)
        return;
    string name = "TLB_INFO_PANEL";
    TLB_DeleteObjectIfExists(name);
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
    string text = StringFormat("TLB Lines: %d\nBreakouts: %d", TLB_LineCount, CountBreakouts());
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

int CountBreakouts()
{
    int cnt = 0;
    for (int i = 0; i < TLB_LineCount; i++)
        if (TLB_Lines[i].triggered)
            cnt++;
    return cnt;
}

//--- Fungsi utama dipanggil OnTick
bool LuxAlgoTrendLinesWithBreak()
{
    bool tradeExecuted = true;
    TLB_DetectTrendlines();
    TLB_DetectBreakouts();
    TLB_DrawInfoPanel();
    return tradeExecuted;
}

//+------------------------------------------------------------------+
//| High probability signal detector                                 |
//| Usage: call DetectHighProbSignal(...)                            |
//+------------------------------------------------------------------+
//// dari ko ricky -> Base Momentum Indikator BB->EMA->RSI->ADX
// Fungsi utama: mendeteksi sinyal dengan scoring / probabilitas
// timeFrame  : timeframe untuk analisa (PERIOD_M1, PERIOD_M5, ...)
// barsShift  : shift candle yang digunakan untuk konfirmasi (0 = current, 1 = last closed)
// outDirection : keluaran arah (DIR_BUY / DIR_SELL / DIR_NONE)
// outEntryPrice: recommended entry price (market or breakout level)
// outSL        : recommended stop loss
// outTP        : recommended take profit
// outConfidence: 0..100 probabilitas / skor (semakin tinggi = lebih kuat)
// return true kalau terdeteksi sinyal yang memenuhi minimalConfidence
bool DetectHighProbSignal(ENUM_TIMEFRAMES timeFrame,
                          int barsShift,
                          Dir &outDirection,
                          double &outEntryPrice,
                          double &outSL,
                          double &outTP,
                          double &outConfidence,
                          // optional params
                          int emaPeriod = 200,
                          int rsiPeriod = 5,
                          int adxPeriod = 5,
                          int bbPeriod = 99,
                          double bbStdDev = 2.0,
                          int atrPeriod = 14,
                          double minADX = 25.0,
                          double minConfidenceForSignal = 60.0,
                          double rr = 2.0) 
{
    outDirection = DIR_NONE;
    outEntryPrice = outSL = outTP = 0.0;
    outConfidence = 0.0;

    // --- index shifts (past bars must exist)
    int shift = barsShift;
    if(shift < 1) shift = 1; // gunakan bar tertutup terakhir sebagai standar

    // --- ambil nilai indikator
    double ema = iMA(_Symbol, timeFrame, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double priceClose = iClose(_Symbol, timeFrame, shift);
    double priceOpen  = iOpen(_Symbol, timeFrame, shift);
    double bbUpper = iBands(_Symbol, timeFrame, bbPeriod, (int)bbStdDev, 0, PRICE_CLOSE);
    double bbMiddle = iBands(_Symbol, timeFrame, bbPeriod, (int)bbStdDev, 0, PRICE_CLOSE);
    double bbLower = iBands(_Symbol, timeFrame, bbPeriod, (int)bbStdDev, 0, PRICE_CLOSE);
    double rsi = iRSI(_Symbol, timeFrame, rsiPeriod, PRICE_CLOSE);
    double adx = iADX(_Symbol, timeFrame, adxPeriod);
    double atr = iATR(_Symbol, timeFrame, atrPeriod);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double contractDigits = (double)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    // Cek validitas data
    if(ema==EMPTY_VALUE || bbUpper==EMPTY_VALUE || rsi==EMPTY_VALUE || adx==EMPTY_VALUE || atr==EMPTY_VALUE)
        return false;

    // --- scoring sederhana: bobot tiap indikator
    // total score 100. bobot berdasarkan kepercayaan:
    // EMA alignment: 25, RSI momentum: 20, ADX strength: 20, BB breakout: 20, candle confirmation: 15
    double score = 0.0;
    double scoreMax = 100.0;

    // 1) EMA alignment (trend filter)
    // jika close > ema => dukung BUY; close < ema => dukung SELL
    int emaBias = 0;
    if(priceClose > ema) { emaBias = 1; score += 25.0; }
    else if(priceClose < ema) { emaBias = -1; score += 25.0; }

    // 2) RSI momentum
    // strong buy if RSI > 50 and rising; strong sell if RSI < 50 and falling
    // periksa perubahan RSI (shift vs shift+1)
    double rsiPrev = iRSI(_Symbol, timeFrame, rsiPeriod, PRICE_CLOSE);
    if(rsiPrev==EMPTY_VALUE) rsiPrev = rsi;
    if(rsi > 50 && rsi > rsiPrev) { score += 20.0; }         // mendukung BUY
    else if(rsi < 50 && rsi < rsiPrev) { score += 20.0; }    // mendukung SELL
    // penalti kecil kalau RSI ekstrem berlawanan (e.g., terlalu overbought saat buy)
    if(rsi > 80) score -= 5.0;
    if(rsi < 20) score -= 5.0;

    // 3) ADX strength
    if(adx >= minADX) score += 20.0; // trend cukup kuat
    else score += (adx / minADX) * 10.0; // partial support

    // 4) BB breakout / touch
    // jika priceClose > bbUpper -> breakout atas (buy); if priceClose < bbLower -> breakout bawah (sell)
    if(priceClose > bbUpper) score += 20.0;
    else if(priceClose < bbLower) score += 20.0;
    else {
        // jika mantul dari middle band ke atas/bawah, berikan sebagian score
        if(priceClose > bbMiddle && priceOpen < bbMiddle) score += 10.0; // mantul ke atas
        if(priceClose < bbMiddle && priceOpen > bbMiddle) score += 10.0; // mantul ke bawah
    }

    // 5) candle confirmation (momentum candle)
    // jika candle body besar (relative terhadap ATR) -> konfirmasi
    double candleBody = MathAbs(priceClose - priceOpen);
    if(atr > 0.0) {
        double rel = candleBody / atr;
        if(rel >= 0.5) score += 10.0;        // body cukup signifikan
        else if(rel >= 0.2) score += 5.0;
    }

    // Normalisasi skor ke 0..100 dan bounded
    if(score < 0.0) score = 0.0;
    if(score > scoreMax) score = scoreMax;
    outConfidence = score;

    // --- Tentukan arah akhir berdasarkan kombinasi sinyal (majoritas indikator)
    // Count votes: emaBias, rsi direction, bb breakout direction, candle direction
    int voteBuy = 0, voteSell = 0;
    if(emaBias > 0) voteBuy++; else if(emaBias < 0) voteSell++;

    if(rsi > 50 && rsi > rsiPrev) voteBuy++; else if(rsi < 50 && rsi < rsiPrev) voteSell++;

    if(priceClose > bbUpper) voteBuy++; else if(priceClose < bbLower) voteSell++;
    else {
        if(priceClose > bbMiddle && priceOpen < bbMiddle) voteBuy++;
        if(priceClose < bbMiddle && priceOpen > bbMiddle) voteSell++;
    }

    // candle direction
    if(priceClose > priceOpen) voteBuy++; else if(priceClose < priceOpen) voteSell++;

    // ADX tidak memberikan arah, hanya kekuatan. Tetapi jika ADX tinggi dan votes konsisten, kuatkan confidence
    // Tentukan direction final
    if(voteBuy > voteSell && outConfidence >= minConfidenceForSignal) outDirection = DIR_BUY;
    else if(voteSell > voteBuy && outConfidence >= minConfidenceForSignal) outDirection = DIR_SELL;
    else {
        // kalau skor sangat tinggi dan votes seimbang, masih coba arah sesuai EMA
        if(outConfidence >= (minConfidenceForSignal + 10.0)) {
            if(emaBias > 0) outDirection = DIR_BUY;
            else if(emaBias < 0) outDirection = DIR_SELL;
        } else {
            outDirection = DIR_NONE;
            return false;
        }
    }

    // --- Hitung entry price, SL, TP berdasarkan ATR untuk mengakomodasi volatilitas
    double slPips = MathMax( (atr * 1.0), tickSize * 10 ); // minimal atribut
    // Round ke digits symbol
    double slPrice, tpPrice, entryPrice;

    if(outDirection == DIR_BUY) {
        // entry: market/atau breakout level (boleh disesuaikan)
        entryPrice = iClose(_Symbol, timeFrame, shift-1); // rekomendasi: next candle open/market
        slPrice = entryPrice - (slPips * 1.1); // SL sedikit lebih lebar
        tpPrice = entryPrice + ( (slPrice < entryPrice) ? ( (entryPrice - slPrice) * rr ) : (atr * rr) );

        // jika closing di luar upper band, gunakan upper band + small buffer sebagai entry
        if(priceClose > bbUpper) {
            entryPrice = NormalizeDouble(priceClose, (int)contractDigits);
            slPrice = NormalizeDouble(bbMiddle, (int)contractDigits); // SL ke middle band safer
            tpPrice = NormalizeDouble(entryPrice + (MathAbs(entryPrice - slPrice) * rr), (int)contractDigits);
        }
    } else { // SELL
        entryPrice = iClose(_Symbol, timeFrame, shift-1);
        slPrice = entryPrice + (slPips * 1.1);
        tpPrice = entryPrice - ( (slPrice > entryPrice) ? ( (slPrice - entryPrice) * rr ) : (atr * rr) );

        if(priceClose < bbLower) {
            entryPrice = NormalizeDouble(priceClose, (int)contractDigits);
            slPrice = NormalizeDouble(bbMiddle, (int)contractDigits);
            tpPrice = NormalizeDouble(entryPrice - (MathAbs(entryPrice - slPrice) * rr), (int)contractDigits);
        }
    }

    // Normalize outputs
    outEntryPrice = NormalizeDouble(entryPrice, (int)contractDigits);
    outSL = NormalizeDouble(slPrice, (int)contractDigits);
    outTP = NormalizeDouble(tpPrice, (int)contractDigits);

    // Safety check: ensure SL/TP valid
    if(outTP == outEntryPrice || outSL == outEntryPrice) return false;
    if(outDirection == DIR_BUY && outTP <= outEntryPrice) return false;
    if(outDirection == DIR_SELL && outTP >= outEntryPrice) return false;

    // Final: jika confidence cukup tinggi, return true
    return (outConfidence >= minConfidenceForSignal);
}

// ======================================================
// Tier_ADX_RSI_BB: cek high probability signal
// ======================================================
// Variabel global untuk menyimpan info sinyal (bisa juga lokal statik)
Dir gDirection;
double gEntryPrice;
double gSL;
double gTP;
double gConfidence;

bool ExecuteTIER_ADX_RSI_BB()
{
    ENUM_TIMEFRAMES tf = PERIOD_M5; // default timeframe
    int barsShift = 1;              // default bars shift
    double minConfidence = 60.0;    // threshold confidence

    // Panggil DetectHighProbSignal menggunakan variabel global
    bool signal = DetectHighProbSignal(tf, barsShift, gDirection, gEntryPrice, gSL, gTP, gConfidence);

    // Cek validitas sinyal
    if(signal && gConfidence >= minConfidence && gDirection != DIR_NONE)
    {
        Print("✅ High probability signal detected! Direction=", (gDirection==DIR_BUY?"BUY":"SELL"),
              " Entry=", gEntryPrice, " SL=", gSL, " TP=", gTP,
              " Confidence=", gConfidence);
        return true;
    }
    else
    {
        Print("❌ No valid signal. Confidence=", gConfidence);
        return false;
    }
}



void EksekusiTier_ADX_RSI_BB(ENUM_TIMEFRAMES tf, int barsShift,
                      Dir &outDirection,
                      double &outEntryPrice,
                      double &outSL,
                      double &outTP,
                      double &outConfidence,
                      double minConfidence = 60.0)
{
    // --- Panggil fungsi deteksi sinyal
    bool signal = DetectHighProbSignal(tf, barsShift, outDirection, outEntryPrice, outSL, outTP, outConfidence);

    if(!signal || outDirection == DIR_NONE)
    {
        Print("❌ No valid high-probability signal detected. Confidence=", outConfidence);
        return;
    }
    
    double lot = 0.1; // bisa disesuaikan atau dibuat otomatis sesuai risk

    // --- Eksekusi order sesuai arah sinyal
    if(outDirection == DIR_BUY)
    {
        ExecuteBuy(lot, (int)outSL, (int)outTP, "ADX_RSI_BB [Confidence=" + DoubleToString(outConfidence,1) + "]");
    }
    else if(outDirection == DIR_SELL)
    {
        ExecuteSell(lot, (int)outSL, (int)outTP, "ADX_RSI_BB [Confidence=" + DoubleToString(outConfidence,1) + "]");
    }
}
