// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_traceback.h for the primary calling header

#include "Vtb_traceback__pch.h"
#include "Vtb_traceback__Syms.h"
#include "Vtb_traceback___024root.h"

void Vtb_traceback___024root___ctor_var_reset(Vtb_traceback___024root* vlSelf);

Vtb_traceback___024root::Vtb_traceback___024root(Vtb_traceback__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vtb_traceback___024root___ctor_var_reset(this);
}

void Vtb_traceback___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vtb_traceback___024root::~Vtb_traceback___024root() {
}
