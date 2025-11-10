// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vtb_traceback__pch.h"
#include "Vtb_traceback.h"
#include "Vtb_traceback___024root.h"

// FUNCTIONS
Vtb_traceback__Syms::~Vtb_traceback__Syms()
{
}

Vtb_traceback__Syms::Vtb_traceback__Syms(VerilatedContext* contextp, const char* namep, Vtb_traceback* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup module instances
    , TOP{this, namep}
{
        // Check resources
        Verilated::stackCheck(13);
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-9);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
}
