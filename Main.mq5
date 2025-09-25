//+------------------------------------------------------------------+
//| main.mq5 - Momentum EA (Refactored Entry Point)                 |
//| Berdasarkan: MomentumEA_M5M15.mq5                               |
//| Framework: Mini MQL5 EA Framework                               |
//+------------------------------------------------------------------+
#property copyright "2025, MS-Traders"
#property version   "2.00"
#property strict

#include "App.mqh"

//-------------------------------------------------------------------
// Global instance
//-------------------------------------------------------------------
CApp app;

//-------------------------------------------------------------------
// OnInit
//-------------------------------------------------------------------
int OnInit()
  {
   Print("=== EA Initializing (Momentum Framework) ===");

   if(!app.Initialize())
     {
      Print("❌ EA initialization failed!");
      return INIT_FAILED;
     }

   Print("✅ EA Initialized Successfully");
   return INIT_SUCCEEDED;
  }

//-------------------------------------------------------------------
// OnDeinit
//-------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   Print("=== EA Deinitializing === Reason: ", reason);
   app.Deinitialize();
   Print("=== EA Deinitialized ===");
  }

//-------------------------------------------------------------------
// OnTick
//-------------------------------------------------------------------
void OnTick()
  {
   app.Run();   // Jalankan engine utama
  }
//+------------------------------------------------------------------+
