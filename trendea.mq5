//+------------------------------------------------------------------+
//|                                                    trendtest.mq5 |
//|                                  Copyright 2023, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "STE"
#property link      "hiepit127@gmail.com"
#property version   "1.00"

#resource "\\Indicators\\supertrend.ex5"

#define SPREAD SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)

#include <Trade\Trade.mqh> CTrade trade;
#include <Trade\OrderInfo.mqh> COrderInfo m_order;
#include <Trade\PositionInfo.mqh> CPositionInfo m_position;

// TRADE SETTING
input double      iLot          =         0.01;
input int      iStopLoss        =         2000;
input int      iTakeProfit      =         2000;
input double   iMul             =         2;
input int      iOderStep        =         200;
input bool     iUseTradingStop  =         false;
input int      iTradingStep     =         300;
input double   iMaxLot          =         2.56;
// FILTER SIGNAL
input int      iSpread       =            125;
input int      iStartHour    =            14;          // start time
input int      iEndHour      =            22;         // end time
input bool     useAdx        =            false;       // filter with ADX
input bool     useEMA        =            true;      // filter with EMA

datetime expire_date = D'27.10.2023';

int sp_trend_h, ma50_h, ma150_h, adx_h, lose_streak;
double trend[], sp_trend[], ma50[], ma150[], adx[], pdl[], ndl[];

enum Request {
   NOT,
   BUY,
   SELL
};

Request mainRequest = NOT;

ulong trade_ticket = 0;

MqlTick tick;

bool buy_signal = false;
bool sell_signal = false;

double block_signal = false;

bool CheckSpread() {
   return SPREAD <= iSpread;
}

bool isNewCandle() {
   datetime current = TimeCurrent();
   return current == iTime(_Symbol, _Period, 0);
}

int GetLastOrderIsLose() {
  bool setup = HistorySelect(0, TimeCurrent());
  if(!setup) {
    return 0;
  }
  int totalDeals = HistoryDealsTotal();
  if(totalDeals == 0) {
    return 0;
  }
  int result = 0;
  for(int i = totalDeals - 1; i >= 0; i--) {
    ulong LatestTicket = HistoryDealGetTicket(i);
    if(LatestTicket == 0) {
      continue;
    }
    string symbol = HistoryDealGetString(LatestTicket, DEAL_SYMBOL);
    int dealType = HistoryDealGetInteger(LatestTicket, DEAL_TYPE);
    if(symbol != Symbol()) {
      continue;
    }
    if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) {
      double Profit = HistoryDealGetDouble(LatestTicket, DEAL_PROFIT);
      if(Profit != 0) {
        if(Profit < 0) {
          result++;
        } else {
          return result;
        }
      }
    }
  }
  return result;
}

bool TimeCheck() {
   MqlDateTime now;
   TimeToStruct(TimeLocal(), now);   
   bool flag = false;
   if (iStartHour < iEndHour && (now.hour <= iEndHour && now.hour >= iStartHour)) flag = true;
   if (iStartHour > iEndHour && (now.hour >= iStartHour || now.hour <= iEndHour)) flag = true;
   if (iStartHour == iEndHour && now.hour == iStartHour) flag = true;
   
   return flag ;
}


int OnInit() {
   sp_trend_h = iCustom(_Symbol, _Period, "::Indicators\\supertrend.ex5");
   ma50_h = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   ma150_h = iMA(_Symbol, _Period, 150, 0, MODE_EMA, PRICE_CLOSE);
   adx_h = iADX(_Symbol, _Period, 14);
   ArraySetAsSeries(trend, true);
   ArraySetAsSeries(sp_trend, true);
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(ma150, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(pdl, true);
   ArraySetAsSeries(ndl, true);
   ArraySetAsSeries(ndl, true);
   return(INIT_SUCCEEDED);
}

void draw_signal(double entry, double trend_line, bool typeSignal) {
   // draw signal
   string signal_name = typeSignal ? "Buy Signal " : "Sell Signal ";

   datetime current = TimeCurrent();
   string signal = signal_name + " at " + (string)current;
   if (ObjectFind(ChartID(), signal) != 0) {
      ObjectCreate(ChartID(), signal, OBJ_TEXT , 0, current, trend_line + (typeSignal ? -0.5 : 0.5) );
      ObjectSetInteger(ChartID(), signal, OBJPROP_WIDTH, 5);
      ObjectSetInteger(ChartID(), signal, OBJPROP_COLOR, typeSignal ? clrBlue : clrRed);
      ObjectSetString(ChartID(), signal, OBJPROP_TEXT, typeSignal ? "BUY" : "SELL");
      string entry_name = (typeSignal ? "Buy " : "Sell ") + (string)entry + " at " + (string)current;
      
      ObjectCreate(ChartID(), entry_name, OBJ_RECTANGLE, 0, current, entry);
      ObjectSetInteger(ChartID(), entry_name, OBJPROP_WIDTH, 5);
      ObjectSetInteger(ChartID(), entry_name, OBJPROP_COLOR, typeSignal ? clrBlue : clrRed);
   }
}


void BindData() {
   CopyBuffer(sp_trend_h, 8, 0, 10, trend);
   CopyBuffer(sp_trend_h, 2, 0, 10, sp_trend);
   CopyBuffer(ma150_h, 0, 0, 10, ma150);
   CopyBuffer(ma50_h, 0, 0, 10, ma50);
   CopyBuffer(adx_h, 0, 0, 10, adx);
   CopyBuffer(adx_h, 1, 0, 10, pdl);
   CopyBuffer(adx_h, 2, 0, 10, ndl);
   lose_streak = GetLastOrderIsLose();
   SymbolInfoTick(_Symbol, tick);
   
   string strCmt = "TrendEA\n";
   strCmt += (string)TimeLocal();
   strCmt += "\nSpread: " + (string)SPREAD;
   strCmt += "\nLose Streak: " + (string)lose_streak;
   
   Comment(strCmt);
}

void OnDeinit(const int reason) {

}

double getLots() {
   double mulLot = iLot * pow(iMul, lose_streak);
   double lot = MathMin(iMaxLot, mulLot);
   return NormalizeDouble(lot, 2);
}

void CalSignal() {
   buy_signal = trend[1] == 1 && trend[2] == -1 && trend[0] == 1;
   sell_signal = trend[1] == -1 && trend[2] ==  1 && trend[0] == -1;
   
      if (isNewCandle() && !block_signal) {
      if (buy_signal && trend[0] == 1) {
         mainRequest = BUY;
         block_signal = true;
         EventSetTimer(PeriodSeconds(_Period));
         draw_signal(tick.ask, trend[0], true);
      }else if (sell_signal && trend[0] == -1) {
         mainRequest = SELL;
         block_signal = true;
         EventSetTimer(PeriodSeconds(_Period));
         draw_signal(tick.ask, trend[0], false);
      }else mainRequest = NOT;
   }else {
      mainRequest = NOT;
   }
}

void Trading() {
   for (int i = 0; i < OrdersTotal() ; i++) {
      if (m_order.SelectByIndex(i) && m_order.Symbol() == _Symbol) {
         if (MathAbs(tick.ask - m_order.PriceOpen() ) > iStopLoss *_Point) {
            trade.OrderDelete(m_order.Ticket());
         }
      }
   }


   if (!iUseTradingStop) return;

   for (int i = 0; i < PositionsTotal(); i ++) {
      if (m_position.SelectByIndex(i) && m_order.Symbol() == _Symbol) {
         if (m_position.PositionType() == POSITION_TYPE_BUY && m_position.TakeProfit() - tick.ask < iTradingStep * _Point) {
            double newTP = m_position.TakeProfit() +  iStopLoss*_Point;
            double newSL = m_position.StopLoss() + iStopLoss*_Point;
            trade.PositionModify(m_position.Ticket(), newSL, newTP);
         }
         if (m_position.PositionType() == POSITION_TYPE_SELL && tick.bid - m_position.TakeProfit() < iTradingStep * _Point) {
            double newTP = m_position.TakeProfit() -  iStopLoss*_Point;
            double newSL = m_position.StopLoss() - iStopLoss*_Point;
            trade.PositionModify(m_position.Ticket(), newSL, newTP);
         }
      }
   }
   
}

void MainOrder() {
   if (!TimeCheck()) return;
   if (!CheckSpread()) return;
   if (OrdersTotal() > 0 || PositionsTotal() > 0) return;
   switch (mainRequest) {
      case BUY: {
         if (useAdx && ( adx[0] < 30 || ndl[0] > pdl[0])) {
            Print("ADX Break buy signal at: " + (string)tick.ask);
            return;
         }
         
         if (useEMA && (tick.ask < ma50[0] || tick.ask < ma150[0])) {
            Print("EMA Break buy signal at: " + (string)tick.ask);
            return;
         }
         double entry = iHigh(_Symbol, _Period, 1) + iOderStep *_Point;
         double sl    = entry - iStopLoss * _Point;
         double tp    = entry + iTakeProfit * _Point;
         trade.BuyStop(getLots(), entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0);
         break;
      }
      case SELL: {
         if (useAdx && ( adx[0] < 30 || ndl[0] < pdl[0])) {
            Print("ADX Break sell signal at: " + (string)tick.bid);
            return;
         }
         
         if (useEMA && (tick.bid > ma50[0] || tick.bid > ma150[0])) {
            Print("EMA Break sell signal at: " + (string)tick.bid);
            return;
         }
         double entry = iLow(_Symbol, _Period, 1) - iOderStep *_Point;
         double sl    = entry + iStopLoss * _Point;
         double tp    = entry - iTakeProfit * _Point;
         trade.SellStop(getLots(), entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0);
         break;
      }
      default:
         return;
   }
}

void OnTick() {

   if (TimeCurrent() > expire_date) {
      Print("Beta version expire");
      return;
   }

   BindData();
   CalSignal();
   Trading();
   MainOrder();
}



void OnTimer() {
   block_signal = false;
}