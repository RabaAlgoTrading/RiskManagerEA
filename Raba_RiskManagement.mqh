#property copyright "Copyright 2023, Aleix Rabassa"

// libs.
#include <Trade\trade.mqh>
#include <Trade\PositionInfo.mqh>

// Raba enums.
#include <Raba_Includes\Raba_Enums.mqh>
#include <Raba_Includes\Raba_PositionManagement.mqh>
#include <Raba_Includes\Raba_EAManagement.mqh>

/**
 * EXPERT INPUTS
 */
sinput group "### BREAK EVEN ###"
input bool InpEnableBE = true;                                          // Enable BE
input eBETSLMethods InpBEMethod = BETSLFixedPercentage;                 // BE method
input double InpBEValue = 1;                                            // BE value

sinput group "### TRAILING STOP LOSS ###"
input bool InpEnableTSL = true;                                         // Enable TSL
input bool InpTSLAfterBE = true;                                        // TSL after BE
input eBETSLMethods InpTSLMethod = BETSLFixedPercentage;                // TSL method
input double InpTSLValue = 0.5;                                         // TSL value

/**
 * DATA STRUCTURES
 */
class CSL
{
    public:
        ulong ticket;
        double sl;  
        CSL(void);
};

class CSLList
{
    public:
        void Init(ulong pExpertMagic, string pExpertSymbol);
        void Refresh();
        double GetInitialSLbyTicket(double pTicket);
        bool Exists(ulong pTicket);
        void Add(ulong pTicket, double pInitSl);
        CSLList(void);
      
    private:
        CPositionInfo pos;
        ulong ExpertMagic;
        string ExpertSymbol;
        CSL initialSL[10];
};

class CRiskManagement
{
    public:
        bool Init(ulong pExpertMagic, string ExpertSymbol);
        void Exec();
        CRiskManagement(void);
      
    private:
        CTrade trade;
        CPositionInfo pos;
        CPositionManagement pm;
        
        ulong ExpertMagic;
        string ExpertSymbol;
        CSLList initialSLList;
        
        void BreakEven();
        void TrailingStop();
        bool CheckParams();
};

/**
 * CRiskManagement METHODS
 */
CRiskManagement::CRiskManagement(void) {}

void CRiskManagement::Exec()
{
    // Update positions list.
    initialSLList.Refresh();
    
    // BE exec if needed.
    if (InpEnableBE) BreakEven();
    
    // TSL exec if needed.
    if (InpEnableTSL) TrailingStop();
}

void CRiskManagement::BreakEven()
{
    double breakEvenPips;
    double entryDistance;
    double currPrice;
    bool alreadyBE = false;
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    
    // Loop all positions.
    for (int i = 0; i < PositionsTotal(); i++) {
    
        // Select pos.
        pos.SelectByIndex(i);
        
        // Ignore other expert and symbols positions.   
        if ((pos.Magic() != ExpertMagic && ExpertMagic != NULL) || (pos.Symbol() != ExpertSymbol && ExpertSymbol != "")) {
            continue;
        }
        
        // Define alreadyBE.
        if (pos.PositionType() == POSITION_TYPE_BUY) {
            alreadyBE = pos.StopLoss() - pos.PriceOpen() >= 0;
        } else if (pos.PositionType() == POSITION_TYPE_SELL) {
            alreadyBE = pos.PriceOpen() - pos.StopLoss() >= 0;
        }
        
        // If sl exists but is not BE or TSL yet.
        if (pos.StopLoss() != 0 && !alreadyBE) {
        
            currPrice = pos.PositionType() == POSITION_TYPE_BUY ? priceBid : priceAsk;
         
            // Calc BE pips.
            if (InpTSLMethod == BETSLFixedBalance) {
                // TODO:
                breakEvenPips = 0;
            } else if (InpTSLMethod == BETSLFixedPercentage) {
                breakEvenPips = InpBEValue * MathAbs(pos.PriceOpen() - initialSLList.GetInitialSLbyTicket(pos.Ticket()));
            } else {
                breakEvenPips = InpBEValue * _Point;
            }
         
            // If ready to BE.
            entryDistance  = pos.PositionType() == POSITION_TYPE_BUY ? currPrice - pos.PriceOpen() : pos.PriceOpen() - currPrice;
            if (entryDistance  > breakEvenPips) {
         
                // Execute BE.
                if (trade.PositionModify(pos.Ticket(), pos.PriceOpen(), pos.TakeProfit())) {
            
                    // Update pos object.
                    pos.SelectByTicket(pos.Ticket());
                    Print("Break Even executed. " 
                            + "PriceOpen: " + string(pos.PriceOpen())
                            + " CurrentPrice: " + string(currPrice)
                            + " SL: " + string(pos.StopLoss())
                            + " SLDistance: " + string(MathAbs(currPrice - pos.StopLoss())));
                } else {
                    Print("Error on break even. ", GetLastError());
                }
            }
        }
    }   
}

void CRiskManagement::TrailingStop()
{
    double trailingStopPips;
    double slDistance;
    double currPrice;
    int mul;
    bool alreadyBE = false;   
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);

    // Loop all positions.
    for (int i = 0; i < PositionsTotal(); i++) {
    
        // Select pos.
        pos.SelectByIndex(i);
          
        // Ignore other expert and symbols positions.   
        if ((pos.Magic() != ExpertMagic && ExpertMagic != NULL) || (pos.Symbol() != ExpertSymbol && ExpertSymbol != "")) {
            continue;
        }
      
        // Define alreadyBEorTSL.
        if (pos.PositionType() == POSITION_TYPE_BUY) {
            alreadyBE = pos.StopLoss() - pos.PriceOpen() >= 0;
        } else if (pos.PositionType() == POSITION_TYPE_SELL) {
            alreadyBE = pos.PriceOpen() - pos.StopLoss() >= 0;
        }
      
        // If sl exists but is not BE or TSL yet.
        if (pos.StopLoss() != 0 && (!InpTSLAfterBE || alreadyBE)) {
        
            currPrice = pos.PositionType() == POSITION_TYPE_BUY ? priceBid : priceAsk;
            mul = pos.PositionType() == POSITION_TYPE_BUY ? -1 : 1;
         
            // Calc TSL pips.
            if (InpTSLMethod == BETSLFixedBalance) {
                // TODO:
                trailingStopPips = 0;
            } else if (InpTSLMethod == BETSLFixedPercentage) {
                trailingStopPips = InpTSLValue * MathAbs(pos.PriceOpen() - initialSLList.GetInitialSLbyTicket(pos.Ticket()));
            } else {
                trailingStopPips = InpTSLValue * _Point;
            }
        
            // If ready to TSL.
            slDistance = MathAbs(currPrice - pos.StopLoss());
            if (slDistance > trailingStopPips) {
            
                // Execute TSL.
                double sl = currPrice + (trailingStopPips * mul);
                if (sl != pos.StopLoss()) {
                    if (trade.PositionModify(pos.Ticket(), sl, pos.TakeProfit())) {
                    
                        // Update pos object.
                        pos.SelectByTicket(pos.Ticket());
                        Print("Trailing SL executed. " 
                                + "PriceOpen: " + string(pos.PriceOpen())
                                + " CurrentPrice: " + string(currPrice)
                                + " SL: " + string(pos.StopLoss())
                                + " SLDistance: " + string(MathAbs(currPrice - pos.StopLoss())));
                    } else {
                        Print("Error on trailing SL. ", GetLastError());
                    }
                }
            }
        }
    }   
}

bool CRiskManagement::CheckParams()
{
    if (InpEnableBE && InpBEValue <= 0) {
        Print("Break even params are incorrect.");
        return false;
    }
        
    if (InpEnableTSL && InpTSLValue <= 0) {
        Print("Trailing SL params are incorrect.");
        return false;
    }    
    return true;
}

bool CRiskManagement::Init(ulong pExpertMagic, string pExpertSymbol)
{
    // Set inputs.
    ExpertMagic = pExpertMagic;
    ExpertSymbol = pExpertSymbol;
    
    // Init initialSLList.
    initialSLList.Init(ExpertMagic, ExpertSymbol);
    
    if (!CheckParams()) {
        Print("CRiskManagement input params are wrong.");
        return false;
    }    
    return true;
}

/**
 * CSLList METHODS
 */
CSLList::CSLList(void)
{
    // Loop all elements of slList array.
    for (int i = 0; i < (int) initialSL.Size(); i++) {
    
        // Set to 0.
        initialSL[i].ticket = 0;
        initialSL[i].sl = 0;
    }
}

void CSLList::Add(ulong pTicket,double pInitSl)
{
    // Loop all elements of slList array.
    for (int i = 0; i < (int) initialSL.Size(); i++) {
    
        // Add.
        if (initialSL[i].ticket == 0) {
            initialSL[i].ticket = pTicket;
            initialSL[i].sl = pInitSl;
            return;
        }
    }
}

void CSLList::Init(ulong pExpertMagic, string pExpertSymbol = "")
{   
    ExpertMagic = pExpertMagic;    
    ExpertSymbol = pExpertSymbol;
    
    Refresh();
}

void CSLList::Refresh()
{  
    // Loop all positions.
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        
        // Select pos.
        pos.SelectByIndex(i);
        
        // Ignore other expert and symbols positions.   
        if ((pos.Magic() != ExpertMagic && ExpertMagic != NULL) || (pos.Symbol() != ExpertSymbol && ExpertSymbol != "")) {
            continue;
        }
        
        // If not in the list || in the list but no sl.
        if (!Exists(pos.Ticket()) || GetInitialSLbyTicket(pos.Ticket()) == 0) {
        
            // Add to list.
            Add(pos.Ticket(), pos.StopLoss());
        }
    }
    
    // Loop all elements of slList array.
    for (int i = 0; i < (int) initialSL.Size(); i++) {
        
        // If position does not exist.
        if (!pos.SelectByTicket(initialSL[i].ticket)) {
        
            // Delete from list.       
            initialSL[i].ticket = 0;
            initialSL[i].sl = 0;
        }
    }
}

bool CSLList::Exists(ulong pTicket)
{
    // Loop all elements of slList array.
    for (int i = 0; i < (int) initialSL.Size(); i++) {
        
        if (initialSL[i].ticket == pTicket) {
            return true;
        }
    }
    return false;
}

double CSLList::GetInitialSLbyTicket(double pTicket)
{   
    // Loop all positions.
    for (int i = 0; i < PositionsTotal(); i++) {
    
        // Select pos.
        pos.SelectByIndex(i);
        
        // Ignore other expert and symbols positions.   
        if ((pos.Magic() != ExpertMagic && ExpertMagic != NULL) || (pos.Symbol() != ExpertSymbol && ExpertSymbol != "")) {
            continue;
        }
      
        // Ticket found.
        if (pos.Ticket() == pTicket) {
            for (int k = 0; k < (int) initialSL.Size(); k++) { 
            
                // Initial sl found.           
                if (pos.Ticket() == initialSL[k].ticket) {
                    return initialSL[k].sl;
                }
            }
        }
    }
    return 0;
}

/**
 * CSL METHODS
 */
CSL::CSL(void) {}