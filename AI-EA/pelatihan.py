"""
==================================================================
Signal AI Filter - Template Python
Versi: 1.0
Author: Rey Riyan Sanjaya

Deskripsi:
    Template ini digunakan untuk melatih AI Filter untuk sinyal Forex.
    - Menerima sinyal dari berbagai detektor (Momentum, Candle Pattern, News Impact, Order Block, dsb.)
    - Mengubah sinyal menjadi fitur numerik
    - Melatih model XGBoost untuk memprediksi sinyal layak entry
    - Menyimpan model untuk digunakan oleh EA

PANDUAN PENGGUNAAN:
1. Persiapkan dataset historis:
    - Setiap bar / candle memiliki sinyal dari semua detektor.
    - Buat label target: 1 = sinyal profitable / layak entry, 0 = tidak layak
    - Contoh CSV:
        Momentum, CandlePattern, OrderBlock, NewsImpact, ATR, EMA_Slope, Target
        1,0,1,0,12.5,0.3,1
        0,1,0,0,10.0,-0.2,0

2. Set kolom input dan target:
    - Fitur: semua kolom sinyal dan indikator numerik
    - Target: kolom 'Target'

3. Install library yang dibutuhkan:
    pip install pandas scikit-learn xgboost joblib

4. Jalankan script untuk melatih model:
    python train_signal_ai.py

5. Output:
    - File model: xgb_signal_filter.pkl
    - Model ini bisa digunakan oleh EA untuk memprediksi sinyal layak entry

6. Integrasi ke EA:
    - EA membaca model (misal via CSV / REST API / Python DLL)
    - Input EA: fitur sinyal terbaru
    - Output: probabilitas sinyal layak entry
    - Threshold probabilitas (misal 0.7) → eksekusi order
==================================================================
"""

# ========================= IMPORT ================================
import pandas as pd
from sklearn.model_selection import train_test_split
from xgboost import XGBClassifier
from sklearn.metrics import accuracy_score, confusion_matrix
import joblib

# ========================= CONFIG ================================
DATASET_CSV = "signals_dataset.csv"  # Dataset input CSV
MODEL_FILE  = "xgb_signal_filter.pkl"  # Output model

# ========================= LOAD DATA =============================
data = pd.read_csv(DATASET_CSV)

# Pisahkan fitur dan target
X = data.drop(columns=["Target"])
y = data["Target"]

# ========================= SPLIT TRAIN / TEST ====================
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# ========================= TRAIN MODEL ===========================
model = XGBClassifier(
    max_depth=5,
    n_estimators=200,
    learning_rate=0.1,
    objective="binary:logistic",
    random_state=42
)

model.fit(X_train, y_train)

# ========================= EVALUASI =============================
y_pred = model.predict(X_test)
y_prob = model.predict_proba(X_test)[:,1]  # probabilitas sinyal layak

accuracy = accuracy_score(y_test, y_pred)
cm = confusion_matrix(y_test, y_pred)

print("=== Evaluasi Model ===")
print("Accuracy:", accuracy)
print("Confusion Matrix:\n", cm)

# ========================= SIMPAN MODEL ==========================
joblib.dump(model, MODEL_FILE)
print(f"Model tersimpan sebagai {MODEL_FILE}")

# ========================= CONTOH PREDIKSI =======================
# Bisa dipakai untuk data baru
# data_baru = pd.DataFrame({
#     "Momentum":[1],
#     "CandlePattern":[0],
#     "OrderBlock":[1],
#     "NewsImpact":[0],
#     "ATR":[12.0],
#     "EMA_Slope":[0.25]
# })
# prob = model.predict_proba(data_baru)[:,1][0]
# print("Probabilitas sinyal layak entry:", prob)

"""
======================== PANDUAN PENGGUNAAN DI EA =====================

1. Output model disimpan sebagai xgb_signal_filter.pkl
2. EA bisa membaca model dengan salah satu cara:
   a) Python DLL / PyInstaller → EA panggil Python function
   b) REST API → EA request probabilitas sinyal
   c) CSV / JSON → EA baca data sinyal terbaru + probabilitas

3. Fitur untuk EA:
   - Sama seperti fitur training (Momentum, CandlePattern, OrderBlock, NewsImpact, ATR, EMA_Slope, dsb.)
   - EA membuat DataFrame kecil / CSV untuk input model
   - AI mengembalikan probabilitas (0-1)
   - Threshold probabilitas (misal 0.7) → execute order via TradeExecutor

4. Contoh pseudocode di EA:
   Signal signals[10];  // Hasil deteksi sinyal
   AISignal aiSig = FilterSignalWithAI(signals, count);  // Panggil model
   if(aiSig.probability > 0.7)
       OpenTrade(aiSig.bestSignal.signal, aiSig.bestSignal.lotSize,
                 aiSig.bestSignal.stopLoss, aiSig.bestSignal.takeProfit);
"""
