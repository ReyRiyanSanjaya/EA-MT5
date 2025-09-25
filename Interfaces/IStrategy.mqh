#pragma once
#include "..\Interfaces\Types.mqh"

class IStrategy
  {
public:
   virtual string Name() { return "BaseStrategy"; }
   virtual bool CheckSignal(Dir &direction) { return false; }
   virtual void Execute(Dir direction, double lotSize) {}
  };
