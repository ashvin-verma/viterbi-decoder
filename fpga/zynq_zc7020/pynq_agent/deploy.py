#!/usr/bin/env python3
"""
Copy the agent + bitstreams to a PYNQ-Z2 (PYNQ Linux, SD boot) and (re)start it.

    python deploy.py [--host 192.168.2.99] [--user xilinx] [--password xilinx]
                     [--program 7] [--no-bits]

The agent runs as root (needed for /dev/mem + FPGA manager) via nohup; it is
not installed as a service, so it stops on reboot. Rerun this to restart it.
"""
import argparse
import os
import sys
import time

import paramiko

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(HERE, "..", "vivado_project_ps7")
REMOTE_DIR = "/home/xilinx/viterbi_agent"
VENV_ENV = "source /etc/profile.d/pynq_venv.sh 2>/dev/null; source /etc/profile.d/xrt_setup.sh 2>/dev/null"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.2.99")
    ap.add_argument("--user", default="xilinx")
    ap.add_argument("--password", default=os.environ.get("PYNQ_PASSWORD", "xilinx"))
    ap.add_argument("--program", type=int, default=7, help="K to load at startup (0 = none)")
    ap.add_argument("--no-bits", action="store_true", help="only copy agent.py")
    args = ap.parse_args()

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(args.host, username=args.user, password=args.password, timeout=10,
              look_for_keys=False, allow_agent=False)

    def run(cmd, sudo=False, timeout=60):
        if sudo:
            cmd = f"sudo -S -p '' bash -c {sh_quote(cmd)}"
        i, o, e = c.exec_command(cmd, timeout=timeout)
        if sudo:
            i.write(args.password + "\n")
            i.flush()
        out = (o.read() + e.read()).decode(errors="replace").strip()
        return out

    run(f"mkdir -p {REMOTE_DIR}; rm -f {REMOTE_DIR}/*.hwh")
    sftp = c.open_sftp()
    files = [(os.path.join(HERE, "agent.py"), "agent.py")]
    if not args.no_bits:
        for k in (3, 5, 7, 9):
            bit = os.path.join(PROJ, f"viterbi_ps7_k{k}.bit")
            if os.path.exists(bit):
                files.append((bit, f"viterbi_ps7_k{k}.bit"))
            else:
                print(f"  (no bitstream for K={k})")
    for src, name in files:
        sftp.put(src, f"{REMOTE_DIR}/{name}")
        print(f"  copied {name} ({os.path.getsize(src) // 1024} KB)")
    sftp.close()

    # Stop any previous agent, then start a new one in the background.
    run("pkill -f 'viterbi_agent/agent.py' || true", sudo=True)
    time.sleep(1)
    prog = f"--program {args.program}" if args.program else ""
    run(f"{VENV_ENV}; cd {REMOTE_DIR}; "
        f"nohup python3 {REMOTE_DIR}/agent.py --host {args.host} {prog} "
        f"> {REMOTE_DIR}/agent.log 2>&1 &", sudo=True)
    for _ in range(40):
        time.sleep(1)
        log = run(f"cat {REMOTE_DIR}/agent.log 2>/dev/null")
        if "viterbi agent on" in log or "Error" in log or "Traceback" in log:
            break
    print(log[-2000:])
    c.close()
    sys.exit(0 if "viterbi agent on" in log else 1)


def sh_quote(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"


if __name__ == "__main__":
    main()
