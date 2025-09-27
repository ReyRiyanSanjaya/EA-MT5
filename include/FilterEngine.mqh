//==================================================================
// FilterEngine.mqh
// Modul: Filter strategi sebelum eksekusi entry
//
// Fungsi:
//   - Menyediakan interface untuk menambahkan berbagai filter
//   - Mengecek kondisi sebelum strategi boleh entry
//
// Cara integrasi di App.mqh:
//   1. #include <Modules/FilterEngine.mqh>
//   2. Tambahkan filter yang dibutuhkan, misalnya:
//        g_filterEngine.AddFilter(new TimeFilter());
//        g_filterEngine.AddFilter(new TrendFilter());
//   3. Sebelum eksekusi trade, panggil:
//        if(g_filterEngine.PassAll()) { /* lanjutkan entry */ }
//
//==================================================================

#pragma once

//==================================================================
// Interface Filter
//==================================================================
class IFilter
{
public:
    virtual bool Pass() = 0;    // return true jika filter lolos
};

//==================================================================
// Engine utama filter
//==================================================================
class FilterEngine
{
private:
    CArrayObj m_filters;   // daftar filter

public:
    // Tambah filter baru
    void AddFilter(IFilter* filter)
    {
        m_filters.Add(filter);
    }

    // Cek semua filter
    bool PassAll()
    {
        for(int i=0; i<m_filters.Total(); i++)
        {
            IFilter* f = (IFilter*)m_filters.At(i);
            if(!f.Pass())
                return false; // jika ada yang gagal, stop
        }
        return true;
    }
};

//==================================================================
// Contoh filter: hanya trading jam tertentu
//==================================================================
class TimeFilter : public IFilter
{
private:
    int m_startHour, m_endHour;
public:
    TimeFilter(int startHour=9, int endHour=17)
    {
        m_startHour = startHour;
        m_endHour   = endHour;
    }

    virtual bool Pass()
    {
        int hour = TimeHour(TimeCurrent());
        return (hour >= m_startHour && hour < m_endHour);
    }
};

//==================================================================
// Contoh filter: hanya trading jika MA menunjukkan trend
//==================================================================
class TrendFilter : public IFilter
{
private:
    int m_period;
public:
    TrendFilter(int period=50) { m_period = period; }

    virtual bool Pass()
    {
        double ma = iMA(_Symbol, PERIOD_M15, m_period, 0, MODE_SMA, PRICE_CLOSE, 0);
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        return (price > ma); // hanya buy jika harga di atas MA
    }
};

//==================================================================
// EOF
//==================================================================
