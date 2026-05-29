#!/usr/bin/env python3
"""
分析 perf.riscv perf_logs，输出 CSV 表格：
每行一个 benchmark，列为 IPC + 各组内每个计数器的占比(%)。

用法:
  ./analyze_counters.py perf_logs/ > counters.csv
  ./analyze_counters.py perf_logs/ perf_logs_age/ > compare.csv
"""

import os, sys, json, glob
from collections import defaultdict

# (组名, [(event_id, 标签), ...])
GROUPS = [
    ("Dispatch",  [(2,"2busy"), (3,"1busy"), (4,"ready")]),
    ("ALU",       [(5,"2busy"), (6,"1busy"), (7,"ready")]),
    ("Branch",    [(8,"2busy"), (9,"1busy"), (10,"ready")]),
    ("JMP",       [(11,"2busy"), (12,"1busy"), (13,"ready")]),
    ("MEM",       [(14,"2busy"), (15,"1busy"), (16,"ready")]),
    ("MUL",       [(17,"2busy"), (18,"1busy"), (19,"ready")]),
    ("DIV",       [(20,"2busy"), (21,"1busy"), (22,"ready")]),
    ("FPU",       [(23,"2busy"), (24,"1busy"), (25,"ready")]),
    ("FDIV",      [(26,"2busy"), (27,"1busy"), (28,"ready")]),
    ("I2F",       [(29,"2busy"), (30,"1busy"), (31,"ready")]),
    ("F2I",       [(32,"2busy"), (33,"1busy"), (34,"ready")]),
    ("F2IMEM",    [(35,"2busy"), (36,"1busy"), (37,"ready")]),
    ("FMA",       [(38,"3busy"), (39,"2busy"), (40,"1busy"), (41,"ready")]),
    ("IQ0",       [(42,"stall"),(43,"=1"),(44,"=2"),(45,"=3"),(46,"=4"),
                   (47,"=5"),(48,"=6"),(49,"=7"),(50,"=8"),(51,"=9"),
                   (52,"=10"),(53,"=11"),(54,"=12"),(55,"=13"),(56,"=14"),
                   (57,"=15"),(58,"=16"),(59,"=17"),(60,"=18"),(61,"=19"),(62,"=20")]),
    ("IQ1",       [(63,"stall"),(64,"=1"),(65,"=2"),(66,"=3"),(67,"=4"),
                   (68,"=5"),(69,"=6"),(70,"=7"),(71,"=8"),(72,"=9"),
                   (73,"=10"),(74,"=11"),(75,"=12")]),
    ("FPQ",       [(76,"stall"),(77,"=1"),(78,"=2"),(79,"=3"),(80,"=4"),
                   (81,"=5"),(82,"=6"),(83,"=7"),(84,"=8"),(85,"=9"),
                   (86,"=10"),(87,"=11"),(88,"=12"),(89,"=13"),(90,"=14"),
                   (91,"=15"),(92,"=16")]),
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


def build_csv(all_results):
    labels = list(all_results.keys())
    benchmarks = sorted(set().union(*[set(d.keys()) for d in all_results.values()]))

    # 表头 — 单目录模式不加前缀
    multi = len(labels) > 1
    header = ["Benchmark", "S"]
    for lbl in labels:
        prefix = f"{lbl}." if multi else ""
        header.append(f"{prefix}IPC")
    for gname, events in GROUPS:
        gshort = gname.replace("Dispatch","Disp").replace("Branch","Br").replace("IMEM","IM")
        for lbl in labels:
            prefix = f"{lbl}." if multi else ""
            for eid, tag in events:
                t = tag.replace("ready","rdy").replace("busy","bsy").replace("stall","stl")
                header.append(f"{prefix}{gshort}.{t}%")

    rows = [",".join(header)]

    for bm in benchmarks:
        row = [bm]
        d0 = all_results[labels[0]].get(bm, (0, 0, {}))
        row.append(str(d0[0]))

        for lbl in labels:
            ns, ipc, _ = all_results[lbl].get(bm, (0, 0, {}))
            row.append(f"{ipc:.4f}")

        for gname, events in GROUPS:
            for lbl in labels:
                _, _, ev = all_results[lbl].get(bm, (0, 0, {}))
                total = sum(ev.get(eid, 0) for eid, _ in events)
                for eid, tag in events:
                    if total == 0:
                        row.append("")
                    else:
                        val = ev.get(eid, 0)
                        row.append(f"{val/total*100:.1f}")
        rows.append(",".join(row))

    # 平均行
    if len(rows) > 1:
        avg_row = ["AVERAGE", ""]
        n_bench = len(rows) - 1
        # IPC: 直接对各 benchmark 的 IPC 取算数平均
        ipc_cols = []
        for i, h in enumerate(header):
            if h.endswith("IPC") or h == "IPC":
                ipc_cols.append(i)
        # 收集所有数值列
        for i, h in enumerate(header):
            if i < 2: continue  # skip Benchmark, S
            vals = []
            for r in rows[1:]:
                cols = r.split(",")
                v = cols[i] if i < len(cols) else ""
                if v and v != "-":
                    try: vals.append(float(v))
                    except: pass
            if vals and h.endswith("IPC"):
                avg_row.append(f"{sum(vals)/len(vals):.4f}")
            elif vals:
                avg_row.append(f"{sum(vals)/len(vals):.1f}")
            else:
                avg_row.append("")
        rows.append(",".join(avg_row))

    return rows


if __name__ == "__main__":
    log_dirs = sys.argv[1:] if len(sys.argv) > 1 else ["perf_logs"]
    for d in log_dirs:
        if not os.path.isdir(d):
            print(f"ERROR: {d} not found", file=sys.stderr); sys.exit(1)

    labels = [os.path.basename(d.rstrip("/")) for d in log_dirs]
    all_results = {lbl: analyze_dir(d) for lbl, d in zip(labels, log_dirs)}
    rows = build_csv(all_results)

    for row in rows:
        print(row)
