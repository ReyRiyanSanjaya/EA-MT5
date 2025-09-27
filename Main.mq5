//==================================================================
// main.mq5
// Entry Point Expert Advisor (EA)
//
// Fungsi:
//   - Memanggil framework inti (App.mqh)
//   - Registrasi strategi yang akan digunakan
//   - Menentukan strategi aktif
//   - Menghubungkan lifecycle EA: OnInit, OnTick, OnDeinit
//
// Struktur project:
//   MQL5/Experts/ProjectAnda/main.mq5
//   MQL5/Include/App.mqh
//   MQL5/Include/Modules/FilterEngine.mqh
//   MQL5/Include/Strategies/TrendFollowing.mqh
//
//==================================================================

#include <App.mqh>
#include <Strategies/TrendFollowing.mqh>

//----------------------------------------------------------
// Buat instance strategi global
//----------------------------------------------------------
static TrendFollowing g_trendFollowing;

//----------------------------------------------------------
// EA Lifecycle
//----------------------------------------------------------
int OnInit()
{
   // Inisialisasi App
   if(!App::Init())
      return INIT_FAILED;

   // Registrasi strategi diambil dari include/app.mqh
   App::RegisterStrategy(&g_trendFollowing);

   // Load strategi default
   App::LoadStrategy("TrendFollowing");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   App::OnTick();
}

void OnDeinit(const int reason)
{
   App::Deinit(reason);
}

//==================================================================
// EOF
//==================================================================
