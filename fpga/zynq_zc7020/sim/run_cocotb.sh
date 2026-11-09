#!/bin/bash
# Run the cocotb system test in WSL.  Usage: bash run_cocotb.sh [K] [timeout_s]
K=${1:-7}
TO=${2:-1500}
cd /mnt/c/Users/ashvi/Documents/viterbi-decoder && source .venv/bin/activate
cd fpga/zynq_zc7020/sim
timeout "$TO" make SIM=icarus TB_K="$K" > "cocotb_k$K.log" 2>&1
echo "make exit: $?"
grep -v sorry "cocotb_k$K.log" | grep -E "INFO|Error|error|FAIL|PASS|assert|TESTS" | grep -v -E "gpi|Initialized|Seeding|Running on" | tail -n 40
