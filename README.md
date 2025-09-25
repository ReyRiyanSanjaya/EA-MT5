MQL5Project/
│── EA.mq5                  // File utama EA (entry point)
│── App.mqh                 // Core App & Strategy Loader
│── Config.mqh              // Setting global (risk, magic, dll)
│── README.md               // Dokumentasi singkat
│
├── Strategies/             // Kumpulan strategi trading
│   ├── StrategyBase.mqh    // Interface/abstract class strategi
│   ├── TrendFollowing.mqh  // Contoh strategi: trend following
│   └── MeanReversion.mqh   // Contoh strategi lain
│
├── Modules/                // Komponen tambahan (helper/engine)
│   ├── RiskManager.mqh     // Risk & money management
│   ├── TradeExecutor.mqh   // Modul eksekusi order
│   ├── IndicatorEngine.mqh // Modul indikator custom
│   └── FilterEngine.mqh    // Modul filter (time/news/session)
│
├── Interfaces/             // Antarmuka atau enum
│   ├── Types.mqh           // Enum: Dir (Buy/Sell/None), dll
│   └── IStrategy.mqh       // Interface strategi
│   └── MathUtils.mqh       // Interface strategi
│
└── Utils/                  // Fungsi utilitas
    ├── Logger.mqh          // Logging aktivitas
    └── MathUtils.mqh       // Fungsi matematis (RR ratio, dsb)
