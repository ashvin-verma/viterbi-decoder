// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_traceback.h for the primary calling header

#ifndef VERILATED_VTB_TRACEBACK___024ROOT_H_
#define VERILATED_VTB_TRACEBACK___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_traceback__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_traceback___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ tb_traceback__DOT__clk;
    CData/*0:0*/ tb_traceback__DOT__rst;
    CData/*1:0*/ tb_traceback__DOT__s_end;
    CData/*2:0*/ tb_traceback__DOT__tb_time;
    CData/*1:0*/ tb_traceback__DOT__tb_state;
    CData/*0:0*/ tb_traceback__DOT__dec_bit_valid;
    CData/*0:0*/ tb_traceback__DOT__dec_bit;
    CData/*0:0*/ tb_traceback__DOT__wr_en;
    CData/*3:0*/ tb_traceback__DOT__surv_row_drive;
    CData/*2:0*/ tb_traceback__DOT__wr_ptr_reg;
    CData/*3:0*/ tb_traceback__DOT____Vlvbound_h5f23bce4__0;
    CData/*0:0*/ tb_traceback__DOT____Vlvbound_hf4889e7f__0;
    CData/*0:0*/ tb_traceback__DOT____Vlvbound_h85a958a0__0;
    CData/*1:0*/ tb_traceback__DOT__dut__DOT__tb_fsm;
    CData/*2:0*/ tb_traceback__DOT__dut__DOT__wr_ptr_q;
    CData/*2:0*/ tb_traceback__DOT__dut__DOT__tb_count;
    CData/*0:0*/ tb_traceback__DOT__dut__DOT__tb_surv_bit_d;
    CData/*2:0*/ __Vdly__tb_traceback__DOT__wr_ptr_reg;
    CData/*1:0*/ __Vdly__tb_traceback__DOT__dut__DOT__tb_fsm;
    CData/*2:0*/ __Vdly__tb_traceback__DOT__tb_time;
    CData/*1:0*/ __Vdly__tb_traceback__DOT__tb_state;
    CData/*2:0*/ __Vdly__tb_traceback__DOT__dut__DOT__tb_count;
    CData/*0:0*/ __VdlySet__tb_traceback__DOT__mem__v0;
    CData/*3:0*/ __VdlyVal__tb_traceback__DOT__mem__v6;
    CData/*2:0*/ __VdlyDim0__tb_traceback__DOT__mem__v6;
    CData/*0:0*/ __VdlySet__tb_traceback__DOT__mem__v6;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_traceback__DOT__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_traceback__DOT__rst__0;
    CData/*0:0*/ __VactContinue;
    IData/*31:0*/ tb_traceback__DOT__expected_idx;
    IData/*31:0*/ tb_traceback__DOT__bits_seen;
    IData/*31:0*/ tb_traceback__DOT__mismatch_count;
    IData/*31:0*/ tb_traceback__DOT__extra_outputs;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<CData/*3:0*/, 6> tb_traceback__DOT__mem;
    VlUnpacked<CData/*0:0*/, 48> tb_traceback__DOT__bit_hist;
    VlUnpacked<CData/*1:0*/, 49> tb_traceback__DOT__state_hist;
    VlUnpacked<CData/*0:0*/, 43> tb_traceback__DOT__actual_log;
    VlUnpacked<CData/*0:0*/, 43> tb_traceback__DOT__expected_log;
    VlDelayScheduler __VdlySched;
    VlTriggerScheduler __VtrigSched_ha72e8cd6__0;
    VlTriggerScheduler __VtrigSched_ha72e8c97__0;
    VlTriggerVec<4> __VactTriggered;
    VlTriggerVec<4> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vtb_traceback__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_traceback___024root(Vtb_traceback__Syms* symsp, const char* v__name);
    ~Vtb_traceback___024root();
    VL_UNCOPYABLE(Vtb_traceback___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
