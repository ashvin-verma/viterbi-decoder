// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_traceback.h for the primary calling header

#include "Vtb_traceback__pch.h"
#include "Vtb_traceback___024root.h"

VL_ATTR_COLD void Vtb_traceback___024root___eval_initial__TOP(Vtb_traceback___024root* vlSelf);
VlCoroutine Vtb_traceback___024root___eval_initial__TOP__Vtiming__0(Vtb_traceback___024root* vlSelf);
VlCoroutine Vtb_traceback___024root___eval_initial__TOP__Vtiming__1(Vtb_traceback___024root* vlSelf);

void Vtb_traceback___024root___eval_initial(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_initial\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtb_traceback___024root___eval_initial__TOP(vlSelf);
    Vtb_traceback___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    Vtb_traceback___024root___eval_initial__TOP__Vtiming__1(vlSelf);
}

VL_INLINE_OPT VlCoroutine Vtb_traceback___024root___eval_initial__TOP__Vtiming__1(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_initial__TOP__Vtiming__1\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    while (1U) {
        co_await vlSelfRef.__VdlySched.delay(0x1388ULL, 
                                             nullptr, 
                                             "tb_traceback.sv", 
                                             51);
        vlSelfRef.tb_traceback__DOT__clk = (1U & (~ (IData)(vlSelfRef.tb_traceback__DOT__clk)));
    }
}

void Vtb_traceback___024root___eval_act(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_act\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

void Vtb_traceback___024root___nba_sequent__TOP__0(Vtb_traceback___024root* vlSelf);
void Vtb_traceback___024root___nba_sequent__TOP__1(Vtb_traceback___024root* vlSelf);
void Vtb_traceback___024root___nba_sequent__TOP__2(Vtb_traceback___024root* vlSelf);

void Vtb_traceback___024root___eval_nba(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_nba\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        Vtb_traceback___024root___nba_sequent__TOP__0(vlSelf);
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        Vtb_traceback___024root___nba_sequent__TOP__1(vlSelf);
    }
    if ((3ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        Vtb_traceback___024root___nba_sequent__TOP__2(vlSelf);
    }
}

VL_INLINE_OPT void Vtb_traceback___024root___nba_sequent__TOP__0(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___nba_sequent__TOP__0\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vdly__tb_traceback__DOT__wr_ptr_reg 
        = vlSelfRef.tb_traceback__DOT__wr_ptr_reg;
    vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v0 = 0U;
    vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v6 = 0U;
    vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm 
        = vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm;
    vlSelfRef.__Vdly__tb_traceback__DOT__tb_time = vlSelfRef.tb_traceback__DOT__tb_time;
    vlSelfRef.__Vdly__tb_traceback__DOT__tb_state = vlSelfRef.tb_traceback__DOT__tb_state;
    vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_count 
        = vlSelfRef.tb_traceback__DOT__dut__DOT__tb_count;
    if (vlSelfRef.tb_traceback__DOT__rst) {
        vlSelfRef.__Vdly__tb_traceback__DOT__wr_ptr_reg = 0U;
        vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v0 = 1U;
    } else if (vlSelfRef.tb_traceback__DOT__wr_en) {
        vlSelfRef.tb_traceback__DOT____Vlvbound_h5f23bce4__0 
            = vlSelfRef.tb_traceback__DOT__surv_row_drive;
        if ((5U >= (IData)(vlSelfRef.tb_traceback__DOT__wr_ptr_reg))) {
            vlSelfRef.__VdlyVal__tb_traceback__DOT__mem__v6 
                = vlSelfRef.tb_traceback__DOT____Vlvbound_h5f23bce4__0;
            vlSelfRef.__VdlyDim0__tb_traceback__DOT__mem__v6 
                = vlSelfRef.tb_traceback__DOT__wr_ptr_reg;
            vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v6 = 1U;
        }
        vlSelfRef.__Vdly__tb_traceback__DOT__wr_ptr_reg 
            = ((5U == (IData)(vlSelfRef.tb_traceback__DOT__wr_ptr_reg))
                ? 0U : (7U & ((IData)(1U) + (IData)(vlSelfRef.tb_traceback__DOT__wr_ptr_reg))));
    }
}

VL_INLINE_OPT void Vtb_traceback___024root___nba_sequent__TOP__1(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___nba_sequent__TOP__1\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    VL_WRITEF_NX("%0t : wr_en=%0b wr_ptr=%0# tb_fsm=%0# tb_time=%0# tb_state=%0# count=%0# dec_valid=%0b dec_bit=%0b\n",0,
                 64,VL_TIME_UNITED_Q(1000),-9,1,(IData)(vlSelfRef.tb_traceback__DOT__wr_en),
                 3,vlSelfRef.tb_traceback__DOT__wr_ptr_reg,
                 2,(IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm),
                 3,vlSelfRef.tb_traceback__DOT__tb_time,
                 2,(IData)(vlSelfRef.tb_traceback__DOT__tb_state),
                 3,vlSelfRef.tb_traceback__DOT__dut__DOT__tb_count,
                 1,(IData)(vlSelfRef.tb_traceback__DOT__dec_bit_valid),
                 1,vlSelfRef.tb_traceback__DOT__dec_bit);
    if (vlSelfRef.tb_traceback__DOT__rst) {
        vlSelfRef.tb_traceback__DOT__bits_seen = 0U;
        vlSelfRef.tb_traceback__DOT__expected_idx = 0U;
        vlSelfRef.tb_traceback__DOT__mismatch_count = 0U;
        vlSelfRef.tb_traceback__DOT__extra_outputs = 0U;
    } else if (vlSelfRef.tb_traceback__DOT__dec_bit_valid) {
        vlSelfRef.tb_traceback__DOT__bits_seen = ((IData)(1U) 
                                                  + vlSelfRef.tb_traceback__DOT__bits_seen);
        if (VL_GTS_III(32, 0x2bU, vlSelfRef.tb_traceback__DOT__expected_idx)) {
            vlSelfRef.tb_traceback__DOT____Vlvbound_hf4889e7f__0 
                = vlSelfRef.tb_traceback__DOT__dec_bit;
            vlSelfRef.tb_traceback__DOT____Vlvbound_h85a958a0__0 
                = ((0x2fU >= (0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx)) 
                   && vlSelfRef.tb_traceback__DOT__bit_hist
                   [(0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx)]);
            if ((0x2aU >= (0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx))) {
                vlSelfRef.tb_traceback__DOT__actual_log[(0x3fU 
                                                         & vlSelfRef.tb_traceback__DOT__expected_idx)] 
                    = vlSelfRef.tb_traceback__DOT____Vlvbound_hf4889e7f__0;
            }
            if ((0x2aU >= (0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx))) {
                vlSelfRef.tb_traceback__DOT__expected_log[(0x3fU 
                                                           & vlSelfRef.tb_traceback__DOT__expected_idx)] 
                    = vlSelfRef.tb_traceback__DOT____Vlvbound_h85a958a0__0;
            }
            if (((IData)(vlSelfRef.tb_traceback__DOT__dec_bit) 
                 != ((0x2fU >= (0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx)) 
                     && vlSelfRef.tb_traceback__DOT__bit_hist
                     [(0x3fU & vlSelfRef.tb_traceback__DOT__expected_idx)]))) {
                vlSelfRef.tb_traceback__DOT__mismatch_count 
                    = ((IData)(1U) + vlSelfRef.tb_traceback__DOT__mismatch_count);
            }
            vlSelfRef.tb_traceback__DOT__expected_idx 
                = ((IData)(1U) + vlSelfRef.tb_traceback__DOT__expected_idx);
        } else {
            vlSelfRef.tb_traceback__DOT__extra_outputs 
                = ((IData)(1U) + vlSelfRef.tb_traceback__DOT__extra_outputs);
        }
    }
}

VL_INLINE_OPT void Vtb_traceback___024root___nba_sequent__TOP__2(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___nba_sequent__TOP__2\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (vlSelfRef.tb_traceback__DOT__rst) {
        vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = 0U;
        vlSelfRef.__Vdly__tb_traceback__DOT__tb_time = 0U;
        vlSelfRef.__Vdly__tb_traceback__DOT__tb_state = 0U;
        vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_count = 0U;
        vlSelfRef.tb_traceback__DOT__dec_bit_valid = 0U;
        vlSelfRef.tb_traceback__DOT__dec_bit = 0U;
        vlSelfRef.tb_traceback__DOT__dut__DOT__wr_ptr_q = 0U;
    } else {
        vlSelfRef.tb_traceback__DOT__dec_bit_valid = 0U;
        if ((0U == (IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm))) {
            vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_count = 0U;
            if (((IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__wr_ptr_q) 
                 != (IData)(vlSelfRef.tb_traceback__DOT__wr_ptr_reg))) {
                vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = 1U;
                vlSelfRef.__Vdly__tb_traceback__DOT__tb_time 
                    = vlSelfRef.tb_traceback__DOT__wr_ptr_reg;
                vlSelfRef.__Vdly__tb_traceback__DOT__tb_state 
                    = vlSelfRef.tb_traceback__DOT__s_end;
            }
        } else if ((1U == (IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm))) {
            vlSelfRef.__Vdly__tb_traceback__DOT__tb_time 
                = ((0U == (IData)(vlSelfRef.tb_traceback__DOT__tb_time))
                    ? 5U : (7U & ((IData)(vlSelfRef.tb_traceback__DOT__tb_time) 
                                  - (IData)(1U))));
            vlSelfRef.__Vdly__tb_traceback__DOT__tb_state 
                = (((IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_surv_bit_d) 
                    << 1U) | (1U & ((IData)(vlSelfRef.tb_traceback__DOT__tb_state) 
                                    >> 1U)));
            vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_count 
                = (7U & ((IData)(1U) + (IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_count)));
            if ((5U == (IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_count))) {
                vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = 2U;
            }
        } else if ((2U == (IData)(vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm))) {
            vlSelfRef.tb_traceback__DOT__dec_bit = vlSelfRef.tb_traceback__DOT__dut__DOT__tb_surv_bit_d;
            vlSelfRef.tb_traceback__DOT__dec_bit_valid = 1U;
            vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = 0U;
        } else {
            vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = 0U;
        }
        vlSelfRef.tb_traceback__DOT__dut__DOT__wr_ptr_q 
            = vlSelfRef.tb_traceback__DOT__wr_ptr_reg;
    }
    vlSelfRef.tb_traceback__DOT__dut__DOT__tb_fsm = vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm;
    vlSelfRef.tb_traceback__DOT__dut__DOT__tb_count 
        = vlSelfRef.__Vdly__tb_traceback__DOT__dut__DOT__tb_count;
    vlSelfRef.tb_traceback__DOT__dut__DOT__tb_surv_bit_d 
        = ((1U & (~ (IData)(vlSelfRef.tb_traceback__DOT__rst))) 
           && (1U & (((5U >= (IData)(vlSelfRef.tb_traceback__DOT__tb_time))
                       ? vlSelfRef.tb_traceback__DOT__mem
                      [vlSelfRef.tb_traceback__DOT__tb_time]
                       : 0U) >> (IData)(vlSelfRef.tb_traceback__DOT__tb_state))));
    vlSelfRef.tb_traceback__DOT__wr_ptr_reg = vlSelfRef.__Vdly__tb_traceback__DOT__wr_ptr_reg;
    vlSelfRef.tb_traceback__DOT__tb_time = vlSelfRef.__Vdly__tb_traceback__DOT__tb_time;
    vlSelfRef.tb_traceback__DOT__tb_state = vlSelfRef.__Vdly__tb_traceback__DOT__tb_state;
    if (vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v0) {
        vlSelfRef.tb_traceback__DOT__mem[0U] = 0U;
        vlSelfRef.tb_traceback__DOT__mem[1U] = 0U;
        vlSelfRef.tb_traceback__DOT__mem[2U] = 0U;
        vlSelfRef.tb_traceback__DOT__mem[3U] = 0U;
        vlSelfRef.tb_traceback__DOT__mem[4U] = 0U;
        vlSelfRef.tb_traceback__DOT__mem[5U] = 0U;
    }
    if (vlSelfRef.__VdlySet__tb_traceback__DOT__mem__v6) {
        vlSelfRef.tb_traceback__DOT__mem[vlSelfRef.__VdlyDim0__tb_traceback__DOT__mem__v6] 
            = vlSelfRef.__VdlyVal__tb_traceback__DOT__mem__v6;
    }
}

void Vtb_traceback___024root___timing_resume(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___timing_resume\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VactTriggered.word(0U))) {
        vlSelfRef.__VtrigSched_ha72e8cd6__0.resume(
                                                   "@(posedge tb_traceback.clk)");
    }
    if ((4ULL & vlSelfRef.__VactTriggered.word(0U))) {
        vlSelfRef.__VtrigSched_ha72e8c97__0.resume(
                                                   "@(negedge tb_traceback.clk)");
    }
    if ((8ULL & vlSelfRef.__VactTriggered.word(0U))) {
        vlSelfRef.__VdlySched.resume();
    }
}

void Vtb_traceback___024root___timing_commit(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___timing_commit\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((! (1ULL & vlSelfRef.__VactTriggered.word(0U)))) {
        vlSelfRef.__VtrigSched_ha72e8cd6__0.commit(
                                                   "@(posedge tb_traceback.clk)");
    }
    if ((! (4ULL & vlSelfRef.__VactTriggered.word(0U)))) {
        vlSelfRef.__VtrigSched_ha72e8c97__0.commit(
                                                   "@(negedge tb_traceback.clk)");
    }
}

void Vtb_traceback___024root___eval_triggers__act(Vtb_traceback___024root* vlSelf);

bool Vtb_traceback___024root___eval_phase__act(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_phase__act\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    VlTriggerVec<4> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vtb_traceback___024root___eval_triggers__act(vlSelf);
    Vtb_traceback___024root___timing_commit(vlSelf);
    __VactExecute = vlSelfRef.__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelfRef.__VactTriggered, vlSelfRef.__VnbaTriggered);
        vlSelfRef.__VnbaTriggered.thisOr(vlSelfRef.__VactTriggered);
        Vtb_traceback___024root___timing_resume(vlSelf);
        Vtb_traceback___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vtb_traceback___024root___eval_phase__nba(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_phase__nba\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelfRef.__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vtb_traceback___024root___eval_nba(vlSelf);
        vlSelfRef.__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_traceback___024root___dump_triggers__nba(Vtb_traceback___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_traceback___024root___dump_triggers__act(Vtb_traceback___024root* vlSelf);
#endif  // VL_DEBUG

void Vtb_traceback___024root___eval(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY(((0x64U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vtb_traceback___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("tb_traceback.sv", 4, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelfRef.__VactIterCount = 0U;
        vlSelfRef.__VactContinue = 1U;
        while (vlSelfRef.__VactContinue) {
            if (VL_UNLIKELY(((0x64U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vtb_traceback___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("tb_traceback.sv", 4, "", "Active region did not converge.");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactContinue = 0U;
            if (Vtb_traceback___024root___eval_phase__act(vlSelf)) {
                vlSelfRef.__VactContinue = 1U;
            }
        }
        if (Vtb_traceback___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vtb_traceback___024root___eval_debug_assertions(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_debug_assertions\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}
#endif  // VL_DEBUG
