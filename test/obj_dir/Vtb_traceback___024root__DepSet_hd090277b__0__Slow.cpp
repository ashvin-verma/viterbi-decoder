// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_traceback.h for the primary calling header

#include "Vtb_traceback__pch.h"
#include "Vtb_traceback___024root.h"

VL_ATTR_COLD void Vtb_traceback___024root___eval_static__TOP(Vtb_traceback___024root* vlSelf);

VL_ATTR_COLD void Vtb_traceback___024root___eval_static(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_static\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtb_traceback___024root___eval_static__TOP(vlSelf);
    vlSelfRef.__Vtrigprevexpr___TOP__tb_traceback__DOT__clk__0 = 0U;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_traceback__DOT__rst__0 = 1U;
}

VL_ATTR_COLD void Vtb_traceback___024root___eval_static__TOP(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_static__TOP\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.tb_traceback__DOT__clk = 0U;
    vlSelfRef.tb_traceback__DOT__rst = 1U;
    vlSelfRef.tb_traceback__DOT__expected_idx = 0U;
    vlSelfRef.tb_traceback__DOT__bits_seen = 0U;
    vlSelfRef.tb_traceback__DOT__mismatch_count = 0U;
    vlSelfRef.tb_traceback__DOT__extra_outputs = 0U;
}

VL_ATTR_COLD void Vtb_traceback___024root___eval_initial__TOP(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_initial__TOP\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*1:0*/ tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state = 0;
    CData/*1:0*/ tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT____Vlvbound_h90de925f__0 = 0;
    // Body
    vlSelfRef.tb_traceback__DOT__mem[0U] = 0U;
    vlSelfRef.tb_traceback__DOT__mem[1U] = 0U;
    vlSelfRef.tb_traceback__DOT__mem[2U] = 0U;
    vlSelfRef.tb_traceback__DOT__mem[3U] = 0U;
    vlSelfRef.tb_traceback__DOT__mem[4U] = 0U;
    vlSelfRef.tb_traceback__DOT__mem[5U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[1U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[2U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[3U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[4U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[5U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[6U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[7U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[8U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[9U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xaU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xbU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xcU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xdU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xeU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0xfU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x10U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x11U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x12U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x13U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x14U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x15U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x16U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x17U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x18U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x19U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1aU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1bU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1cU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1dU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1eU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x1fU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x20U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x21U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x22U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x23U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x24U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x25U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x26U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x27U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x28U] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x29U] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2aU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2bU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2cU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2dU] = 0U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2eU] = 1U;
    vlSelfRef.tb_traceback__DOT__bit_hist[0x2fU] = 0U;
    vlSelfRef.tb_traceback__DOT__state_hist[0U] = 0U;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[1U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [1U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [1U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[2U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [2U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [2U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[3U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [3U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [3U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[4U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [4U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [4U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[5U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [5U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [5U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[6U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [6U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [6U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[7U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [7U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [7U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[8U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [8U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [8U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[9U] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [9U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [9U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xaU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xaU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xaU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xbU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xbU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xbU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xcU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xcU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xcU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xdU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xdU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xdU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xeU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xeU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xeU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0xfU] = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0xfU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0xfU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x10U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x10U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x10U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x11U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x11U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x11U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x12U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x12U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x12U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x13U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x13U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x13U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x14U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x14U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x14U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x15U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x15U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x15U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x16U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x16U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x16U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x17U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x17U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x17U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x18U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x18U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x18U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x19U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x19U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x19U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1aU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1aU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1aU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1bU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1bU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1bU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1cU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1cU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1cU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1dU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1dU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1dU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1eU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1eU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1eU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x1fU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x1fU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x1fU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x20U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x20U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x20U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x21U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x21U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x21U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x22U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x22U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x22U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x23U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x23U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x23U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x24U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x24U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x24U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x25U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x25U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x25U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x26U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x26U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x26U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x27U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x27U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x27U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x28U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x28U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x28U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x29U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x29U], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x29U] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2aU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2aU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2aU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2bU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2bU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2bU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2cU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2cU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2cU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2dU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2dU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2dU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2eU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2eU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2eU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x2fU] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = (3U & VL_SHIFTR_III(2,2,32, vlSelfRef.tb_traceback__DOT__state_hist
                              [0x2fU], 1U));
    tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state 
        = ((1U & (IData)(tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state)) 
           | (vlSelfRef.tb_traceback__DOT__bit_hist
              [0x2fU] << 1U));
    tb_traceback__DOT____Vlvbound_h90de925f__0 = tb_traceback__DOT__unnamedblk4__DOT__unnamedblk5__DOT__next_state;
    vlSelfRef.tb_traceback__DOT__state_hist[0x30U] 
        = tb_traceback__DOT____Vlvbound_h90de925f__0;
}

VL_ATTR_COLD void Vtb_traceback___024root___eval_final(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_final\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vtb_traceback___024root___eval_settle(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___eval_settle\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_traceback___024root___dump_triggers__act(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___dump_triggers__act\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VactTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge tb_traceback.clk)\n");
    }
    if ((2ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @(posedge tb_traceback.rst)\n");
    }
    if ((4ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 2 is active: @(negedge tb_traceback.clk)\n");
    }
    if ((8ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 3 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_traceback___024root___dump_triggers__nba(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___dump_triggers__nba\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VnbaTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge tb_traceback.clk)\n");
    }
    if ((2ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @(posedge tb_traceback.rst)\n");
    }
    if ((4ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 2 is active: @(negedge tb_traceback.clk)\n");
    }
    if ((8ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 3 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtb_traceback___024root___ctor_var_reset(Vtb_traceback___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_traceback___024root___ctor_var_reset\n"); );
    Vtb_traceback__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelf->tb_traceback__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->tb_traceback__DOT__rst = VL_RAND_RESET_I(1);
    vlSelf->tb_traceback__DOT__s_end = VL_RAND_RESET_I(2);
    vlSelf->tb_traceback__DOT__tb_time = VL_RAND_RESET_I(3);
    vlSelf->tb_traceback__DOT__tb_state = VL_RAND_RESET_I(2);
    vlSelf->tb_traceback__DOT__dec_bit_valid = VL_RAND_RESET_I(1);
    vlSelf->tb_traceback__DOT__dec_bit = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 6; ++__Vi0) {
        vlSelf->tb_traceback__DOT__mem[__Vi0] = VL_RAND_RESET_I(4);
    }
    vlSelf->tb_traceback__DOT__wr_en = VL_RAND_RESET_I(1);
    vlSelf->tb_traceback__DOT__surv_row_drive = VL_RAND_RESET_I(4);
    vlSelf->tb_traceback__DOT__wr_ptr_reg = VL_RAND_RESET_I(3);
    for (int __Vi0 = 0; __Vi0 < 48; ++__Vi0) {
        vlSelf->tb_traceback__DOT__bit_hist[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 49; ++__Vi0) {
        vlSelf->tb_traceback__DOT__state_hist[__Vi0] = VL_RAND_RESET_I(2);
    }
    vlSelf->tb_traceback__DOT__expected_idx = 0;
    vlSelf->tb_traceback__DOT__bits_seen = 0;
    for (int __Vi0 = 0; __Vi0 < 43; ++__Vi0) {
        vlSelf->tb_traceback__DOT__actual_log[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 43; ++__Vi0) {
        vlSelf->tb_traceback__DOT__expected_log[__Vi0] = 0;
    }
    vlSelf->tb_traceback__DOT__mismatch_count = 0;
    vlSelf->tb_traceback__DOT__extra_outputs = 0;
    vlSelf->tb_traceback__DOT____Vlvbound_h5f23bce4__0 = VL_RAND_RESET_I(4);
    vlSelf->tb_traceback__DOT____Vlvbound_hf4889e7f__0 = 0;
    vlSelf->tb_traceback__DOT____Vlvbound_h85a958a0__0 = 0;
    vlSelf->tb_traceback__DOT__dut__DOT__tb_fsm = VL_RAND_RESET_I(2);
    vlSelf->tb_traceback__DOT__dut__DOT__wr_ptr_q = VL_RAND_RESET_I(3);
    vlSelf->tb_traceback__DOT__dut__DOT__tb_count = VL_RAND_RESET_I(3);
    vlSelf->tb_traceback__DOT__dut__DOT__tb_surv_bit_d = VL_RAND_RESET_I(1);
    vlSelf->__Vdly__tb_traceback__DOT__wr_ptr_reg = VL_RAND_RESET_I(3);
    vlSelf->__Vdly__tb_traceback__DOT__dut__DOT__tb_fsm = VL_RAND_RESET_I(2);
    vlSelf->__Vdly__tb_traceback__DOT__tb_time = VL_RAND_RESET_I(3);
    vlSelf->__Vdly__tb_traceback__DOT__tb_state = VL_RAND_RESET_I(2);
    vlSelf->__Vdly__tb_traceback__DOT__dut__DOT__tb_count = VL_RAND_RESET_I(3);
    vlSelf->__VdlySet__tb_traceback__DOT__mem__v0 = 0;
    vlSelf->__VdlyVal__tb_traceback__DOT__mem__v6 = VL_RAND_RESET_I(4);
    vlSelf->__VdlyDim0__tb_traceback__DOT__mem__v6 = VL_RAND_RESET_I(3);
    vlSelf->__VdlySet__tb_traceback__DOT__mem__v6 = 0;
    vlSelf->__Vtrigprevexpr___TOP__tb_traceback__DOT__clk__0 = VL_RAND_RESET_I(1);
    vlSelf->__Vtrigprevexpr___TOP__tb_traceback__DOT__rst__0 = VL_RAND_RESET_I(1);
}
