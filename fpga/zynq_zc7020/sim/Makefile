# cocotb system sim for the FPGA frame buffer + trellis capture + BER tester
# Usage (WSL): make SIM=icarus            (K=7)
#              TB_K=3 make SIM=icarus
SIM ?= icarus
TOPLEVEL_LANG = verilog
TB_K ?= 7
export TB_K

ROOT = ../../..
RTL  = $(ROOT)/src
FSRC = ../src

VERILOG_SOURCES = $(RTL)/project.v $(RTL)/viterbi_core.v $(RTL)/acs_core.v \
  $(RTL)/branch_metric.v $(RTL)/expected_bits.v $(RTL)/pm_bank.v \
  $(RTL)/survivor_mem.v $(RTL)/traceback_v2.v $(RTL)/sym_unpacker_4x.v \
  $(RTL)/sym_unpacker_2x3.v $(RTL)/bit_packer_8x.v $(RTL)/ham2.v $(RTL)/ham3.v \
  $(FSRC)/viterbi_axi_framebuf.v $(FSRC)/ber_tester.v tb_fb_system.v

ifeq ($(TB_K),3)
  KP = -Ptb_fb_system.K=3 -Ptb_fb_system.D=12 -Ptb_fb_system.G0=7 -Ptb_fb_system.G1=5
else ifeq ($(TB_K),5)
  KP = -Ptb_fb_system.K=5 -Ptb_fb_system.D=24 -Ptb_fb_system.G0=19 -Ptb_fb_system.G1=29
else ifeq ($(TB_K),9)
  KP = -Ptb_fb_system.K=9 -Ptb_fb_system.D=60 -Ptb_fb_system.G0=369 -Ptb_fb_system.G1=491
else
  KP = -Ptb_fb_system.K=7 -Ptb_fb_system.D=42 -Ptb_fb_system.G0=121 -Ptb_fb_system.G1=91
endif

COMPILE_ARGS += -g2012 -DVITERBI_DBG $(KP)
COCOTB_TOPLEVEL = tb_fb_system
COCOTB_TEST_MODULES = test_fb_system
SIM_BUILD = sim_build_k$(TB_K)

include $(shell cocotb-config --makefiles)/Makefile.sim
