#!/usr/bin/env python3
"""
分析 perf.riscv perf_logs，输出表格：一行一个 benchmark，列为 IPC + 各组 ready%/util%。

ready% = 操作数就绪（0 busy）的 uop 在该 FU 组中的占比
util% = Issue Queue 非 stall 周期占比（至少 1 条指令 ready）

用法:
  ./analyze_counters.py perf_logs/                        # 单个目录
  ./analyze_counters.py perf_logs/ perf_logs_age/         # 并排对比
"""

import os, sys, json, glob
from collections import defaultdict

# ── 列定义: (组名, [事件ID], 就绪事件ID或'util', 列标题) ──
COLUMNS = [
    ("Dispatch", [2,3,4],       4,       "Disp.ready%"),
    ("ALU",      [5,6,7],       7,       "ALU.ready%"),
    ("Branch",   [8,9,10],      10,      "Br.ready%"),
    ("JMP",      [11,12,13],    13,      "JMP.ready%"),
    ("MEM",      [14,15,16],    16,      "MEM.ready%"),
    ("MUL",      [17,18,19],    19,      "MUL.ready%"),
    ("DIV",      [20,21,22],    22,      "DIV.ready%"),
    ("FPU",      [23,24,25],    25,      "FPU.ready%"),
    ("FDIV",     [26,27,28],    28,      "FDIV.ready%"),
    ("I2F",      [29,30,31],    31,      "I2F.ready%"),
    ("F2I",      [32,33,34],    34,      "F2I.ready%"),
    ("F2IMEM",   [35,36,37],    37,      "F2IM.ready%"),
    ("FMA",      [38,39,40,41], 41,      "FMA.ready%"),
    ("IQ0",      list(range(42,63)), 'util', "IQ0.util%"),
    ("IQ1",      list(range(63,76)), 'util', "IQ1.util%"),
    ("FPQ",      list(range(76,93)), 'util', "FPQ.util%"),
]


def parse_log(filepath):
    events = defaultdict(int)
    tc = ti = ns = 0
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: d = json.loads(line)
            except: continue
            if d.get("type") == "max_inst":
                tc += d["cycles"]; ti += d["inst"]; ns += 1
            elif d.get("type", "").startswith("event"):
                events[int(d["type"].split()[-1])] += d["value"]
    ipc = ti / tc if tc > 0 else 0
    return ns, ipc, events


def analyze_dir(log_dir):
    results = {}
    for f in sorted(glob.glob(f"{log_dir}/*_counter.log")):
        if os.path.getsize(f) == 0: continue
        name = os.path.basename(f).replace("_counter.log", "")
        results[name] = parse_log(f)
    return results


def print_table(all_results):
    labels = list(all_results.keys())
    benchmarks = sorted(set().union(*[set(d.keys()) for d in all_results.values()]))

    headers = ["Benchmark", "S"]
    for lbl in labels:
        headers.append(f"[{lbl}] IPC")
    for _, _, _, col_name in COLUMNS:
        for lbl in labels:
            headers.append(f"[{lbl}] {col_name}")

    rows = []
    for bm in benchmarks:
        row = [bm]
        d0 = all_results[labels[0]].get(bm, (0, 0, {}))
        row.append(str(d0[0]))

        for lbl in labels:
            ns, ipc, _ = all_results[lbl].get(bm, (0, 0, {}))
            row.append(f"{ipc:.4f}")

        for _, ev_ids, ready_id, _ in COLUMNS:
            for lbl in labels:
                _, _, ev = all_results[lbl].get(bm, (0, 0, {}))
                total = sum(ev.get(i, 0) for i in ev_ids)
                if total == 0:
                    row.append("-")
                elif ready_id == 'util':
                    stall = ev.get(ev_ids[0], 0)
                    row.append(f"{(1 - stall/total)*100:.1f}")
                else:
                    r = ev.get(ready_id, 0)
                    row.append(f"{r/total*100:.1f}")
        rows.append(row)

    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))

    header_line = "  ".join(h.ljust(widths[i]) for i, h in enumerate(headers))
    print(header_line)
    print("-" * len(header_line))
    for row in rows:
        print("  ".join(str(c).ljust(widths[i]) for i, c in enumerate(row)))
    print(f"\n({len(benchmarks)} benchmarks)")


if __name__ == "__main__":
    log_dirs = sys.argv[1:] if len(sys.argv) > 1 else ["perf_logs"]
    for d in log_dirs:
        if not os.path.isdir(d):
            print(f"ERROR: {d} not found", file=sys.stderr); sys.exit(1)
    labels = [os.path.basename(d.rstrip("/")) for d in log_dirs]
    all_results = {lbl: analyze_dir(d) for lbl, d in zip(labels, log_dirs)}
    print_table(all_results)
