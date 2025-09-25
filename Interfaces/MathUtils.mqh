//+------------------------------------------------------------------+
//| MathUtils.mqh                                                   |
//| Fungsi helper matematika                                        |
//+------------------------------------------------------------------
#pragma once

//--- Aman untuk pembagian
double SafeDivide(double a, double b)
  {
   if(b == 0.0) return 0.0;
   return a / b;
  }

//--- Normalisasi harga sesuai digit broker
double NormalizePrice(double price)
  {
   return NormalizeDouble(price, _Digits);
  }

//--- Konversi pips ke poin
double PipsToPoints(double pips)
  {
   return pips * (_Point / _Digits == 3 || _Digits == 5 ? 10 : 1);
  }
