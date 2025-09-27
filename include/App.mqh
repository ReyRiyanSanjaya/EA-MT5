//==================================================================
// App.mqh
// Framework inti aplikasi EA
//
// Fungsi:
//   - Membaca konfigurasi dari Utils/Config.mqh
//   - Registrasi & manajemen strategi
//   - Integrasi modul filter
//   - Lifecycle handler (Init, OnTick, Deinit)
//
// Cara pakai di main.mq5:
//   #include <App.mqh>
//
//   int OnInit()    { return(App::Init()   ? INIT_SUCCEEDED : INIT_FAILED); }
//   void OnTick()   { App::OnTick();   }
//   void OnDeinit(const int reason) { App::Deinit(reason); }
//
//==================================================================
#pragma once

#include <Utils/Config.mqh>          // ambil semua input konfigurasi
#include <Modules/FilterEngine.mqh>  // filter modul

//==================================================================
// Interface strategi
//==================================================================
class IStrategy
{
public:
   virtual string Name() = 0;
   virtual void   OnInit() {}
   virtual void   OnTick() = 0;
   virtual void   OnDeinit() {}
};

//==================================================================
// Namespace App
//==================================================================
namespace App
{
   // daftar strategi
   static CArrayObj g_strategies;
   // strategi aktif
   static IStrategy* g_activeStrategy = NULL;
   // filter engine
   static FilterEngine g_filterEngine;

   //===============================================================
   // Registrasi strategi
   //===============================================================
   void RegisterStrategy(IStrategy* strategy)
   {
      g_strategies.Add(strategy);
   }

   //===============================================================
   // Load strategi aktif berdasarkan nama
   //===============================================================
   bool LoadStrategy(string name)
   {
      for(int i=0; i<g_strategies.Total(); i++)
      {
         IStrategy* s = (IStrategy*)g_strategies.At(i);
         if(s.Name() == name)
         {
            g_activeStrategy = s;
            g_activeStrategy.OnInit();
            Print("✅ Strategy loaded: ", name);
            return true;
         }
      }
      Print("❌ Strategy not found: ", name);
      return false;
   }

   //===============================================================
   // Init App
   //===============================================================
   bool Init()
   {
      Print("⚙️ App Init... EA: ", EA_Name);

      // contoh: aktifkan filter hanya jika EnableSMCFilter atau param lain
      if(EnableAutoTrading)
      {
         if(EnableSMCFilter)
            g_filterEngine.AddFilter(new TrendFilter(SMA_Period));

         if(EnableNewsScalp)
            g_filterEngine.AddFilter(new TimeFilter(9, 17));
      }
      return true;
   }

   //===============================================================
   // OnTick
   //===============================================================
   void OnTick()
   {
      if(EnableAutoTrading && !g_filterEngine.PassAll())
      {
         if(EnableDebug)
            Comment("⛔ Entry diblok oleh filter.");
         return;
      }

      if(g_activeStrategy != NULL)
         g_activeStrategy.OnTick();
   }

   //===============================================================
   // Deinit
   //===============================================================
   void Deinit(const int reason)
   {
      if(g_activeStrategy != NULL)
         g_activeStrategy.OnDeinit();
      Print("🛑 App Deinit. Reason: ", reason);
   }
}

//==================================================================
// EOF
//==================================================================
