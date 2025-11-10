// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vtb_traceback__pch.h"

//============================================================
// Constructors

Vtb_traceback::Vtb_traceback(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vtb_traceback__Syms(contextp(), _vcname__, this)}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vtb_traceback::Vtb_traceback(const char* _vcname__)
    : Vtb_traceback(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vtb_traceback::~Vtb_traceback() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vtb_traceback___024root___eval_debug_assertions(Vtb_traceback___024root* vlSelf);
#endif  // VL_DEBUG
void Vtb_traceback___024root___eval_static(Vtb_traceback___024root* vlSelf);
void Vtb_traceback___024root___eval_initial(Vtb_traceback___024root* vlSelf);
void Vtb_traceback___024root___eval_settle(Vtb_traceback___024root* vlSelf);
void Vtb_traceback___024root___eval(Vtb_traceback___024root* vlSelf);

void Vtb_traceback::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vtb_traceback::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vtb_traceback___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vtb_traceback___024root___eval_static(&(vlSymsp->TOP));
        Vtb_traceback___024root___eval_initial(&(vlSymsp->TOP));
        Vtb_traceback___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vtb_traceback___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vtb_traceback::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty(); }

uint64_t Vtb_traceback::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* Vtb_traceback::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vtb_traceback___024root___eval_final(Vtb_traceback___024root* vlSelf);

VL_ATTR_COLD void Vtb_traceback::final() {
    Vtb_traceback___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vtb_traceback::hierName() const { return vlSymsp->name(); }
const char* Vtb_traceback::modelName() const { return "Vtb_traceback"; }
unsigned Vtb_traceback::threads() const { return 1; }
void Vtb_traceback::prepareClone() const { contextp()->prepareClone(); }
void Vtb_traceback::atClone() const {
    contextp()->threadPoolpOnClone();
}
