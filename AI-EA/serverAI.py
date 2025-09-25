#==================================================================
# ai_signal_filter_server.py
# Versi: 2.0
# Author: Rey Riyan Sanjaya
# Deskripsi:
#   REST API AI Signal Filter untuk MT5
#   - Menerima multi-sinyal dari EA (10+ sinyal per pair)
#   - Menggunakan AI (XGBoost / Random Forest) untuk memilih sinyal terbaik
#   - Mengembalikan JSON sinyal terbaik (Signal, Lot, SL, TP, Probability, IsStrong)
#==================================================================

"""
===================== PANDUAN PENGGUNAAN =======================

1. Include library di EA:
      #include "AISignalFilterAPI.mqh"

2. Siapkan REST API server ini dan jalankan:
      python ai_signal_filter_server.py

3. Endpoint utama:
      POST http://127.0.0.1:5000/filter_signals
   - Body JSON (contoh 10 sinyal):
     {
         "symbol": "EURUSD",
         "balance": 1000,
         "signals": [
             {"signal":"BUY","feature1":0.5,...,"featureN":0.7},
             {"signal":"SELL","feature1":0.3,...,"featureN":0.1},
             ...
         ]
     }

4. Output JSON:
     {
         "Signal":"BUY",
         "Lot":0.05,
         "SL":1.2345,
         "TP":1.2370,
         "Probability":0.85,
         "IsStrong":1
     }

5. Integrasi EA:
   - EA mengirim array 10+ sinyal per pair
   - AI memfilter sinyal terbaik
   - EA menggunakan output untuk entry (OpenTrade)

6. Catatan:
   - Probabilitas >= 0.7 → sinyal layak entry
   - Lot dihitung otomatis sesuai balance & SL
   - Model AI harus dilatih offline dan disimpan sebagai ai_model.pkl
"""

from flask import Flask, jsonify, request
import joblib
import pandas as pd
import numpy as np

app = Flask(__name__)

# =================== CONFIG ===================
MODEL_PATH = "ai_model.pkl"  # XGBoost / Random Forest
DEFAULT_LOT = 0.01
RISK_PERCENT = 1.0
TP_MULTIPLIER = 2.0
PROB_THRESHOLD_STRONG = 0.8
# ============================================

# Load model
model = joblib.load(MODEL_PATH)

# Hitung lot dinamis
def calculate_lot(balance, risk_percent, sl_pips):
    risk_amount = balance * risk_percent / 100
    pip_value = 10  # sesuaikan dengan pair
    lot = risk_amount / (sl_pips * pip_value)
    lot = max(lot, DEFAULT_LOT)
    return round(lot, 2)

# =================== API ROUTE ===================
@app.route("/filter_signals", methods=["POST"])
def filter_signals():
    """
    POST request JSON:
    {
        "symbol": "EURUSD",
        "balance": 1000,
        "signals": [
            {"signal":"BUY","feature1":0.5,...,"featureN":0.7},
            {"signal":"SELL","feature1":0.3,...,"featureN":0.1},
            ...
        ]
    }
    """
    data = request.get_json()
    symbol = data.get("symbol", "EURUSD")
    balance = float(data.get("balance", 1000))
    signals = data.get("signals", [])

    if len(signals) == 0:
        return jsonify({"error":"No signals received"}), 400

    # Extract features untuk AI
    features_list = []
    for s in signals:
        # Ambil semua key kecuali 'signal'
        features = [v for k,v in s.items() if k != "signal"]
        features_list.append(features)
    
    X = pd.DataFrame(features_list)

    # Prediksi probabilitas untuk setiap sinyal
    probs = model.predict_proba(X)[:,1]  # asumsikan class 1 = BUY
    best_idx = np.argmax(probs)
    best_signal_raw = signals[best_idx]
    best_prob = probs[best_idx]

    # Tentukan sinyal akhir
    signal_type = best_signal_raw.get("signal","NONE").upper()
    if signal_type=="BUY":
        signal = "BUY"
    elif signal_type=="SELL":
        signal = "SELL"
    else:
        signal = "NONE"

    # SL dan TP default
    sl = 0.0010
    tp = sl * TP_MULTIPLIER

    # Flag sinyal kuat
    is_strong = int(best_prob >= PROB_THRESHOLD_STRONG)

    # Lot sesuai balance dan SL
    lot = calculate_lot(balance, RISK_PERCENT, sl*10000)

    # Kembalikan JSON
    return jsonify({
        "Signal": signal,
        "Lot": lot,
        "SL": round(sl,5),
        "TP": round(tp,5),
        "Probability": round(float(best_prob),2),
        "IsStrong": is_strong
    })

# =================== RUN SERVER ===================
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
