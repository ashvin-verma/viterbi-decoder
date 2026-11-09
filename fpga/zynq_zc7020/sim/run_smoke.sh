#!/bin/bash
# Plain-iverilog smoke/BER sims (no cocotb). Usage: bash run_smoke.sh [tb_top]
set -e
cd "$(dirname "$0")/../../.."
S=src
F=fpga/zynq_zc7020
TOP=${1:-tb_smoke}
RTL="$S/project.v $S/viterbi_core.v $S/acs_core.v $S/branch_metric.v $S/expected_bits.v \
 $S/pm_bank.v $S/survivor_mem.v $S/traceback_v2.v $S/sym_unpacker_4x.v $S/sym_unpacker_2x3.v \
 $S/bit_packer_8x.v $S/ham2.v $S/ham3.v $F/src/viterbi_axi_framebuf.v $F/src/ber_tester.v \
 $F/sim/tb_fb_system.v"
iverilog -g2012 -DVITERBI_DBG -s $TOP -o /tmp/$TOP $RTL $F/sim/$TOP.v 2>&1 | grep -v sorry || true
timeout ${SIM_TIMEOUT:-120} vvp -n /tmp/$TOP | tail -${TAIL:-20}
