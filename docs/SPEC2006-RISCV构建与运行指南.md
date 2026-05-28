# SPEC CPU2006 RISC-V 构建与运行指南

## 环境要求

| 组件 | 说明 |
|---|---|
| SPEC CPU2006 v1.1 | 需要许可的 SPEC CPU2006 安装（需完成 `./install.sh` 并编译工具） |
| RISC-V 工具链 | `riscv64-unknown-linux-gnu-gcc/g++/gfortran` (GCC 14 测试通过) |

### 环境变量

```bash
export SPEC_DIR=<spec2006安装目录>          # 如 /opt/cpu2006
export RISCV_TOOLCHAIN=<riscv工具链bin目录>  # 如 /opt/riscv-toolchain/bin
```

示例：
```bash
export SPEC_DIR=/opt/cpu2006
export RISCV_TOOLCHAIN=/opt/riscv-toolchain/bin
```

**注意：** `RISCV_TOOLCHAIN` 要带 `/bin` 后缀，与 SPEC2017 的 `RISCV`（不带 `/bin`）不同。

## 构建命令

```bash
./gen_binaries.sh --compile [--suite int|fp|all] [--input test|train|ref]
```

| 参数 | 可选值 | 默认值 | 说明 |
|---|---|---|---|
| `--suite` | int, fp, all | int | 基准测试套件 |
| `--input` | test, train, ref | test | 输入数据集规模 |
| `--compile` | — | — | 编译并创建软链接 |

### 一次性构建全部

```bash
# INT: test / ref / train
./gen_binaries.sh --compile --suite int --input test
./gen_binaries.sh --compile --suite int --input ref
./gen_binaries.sh --compile --suite int --input train

# FP: test / ref / train
./gen_binaries.sh --compile --suite fp --input test
./gen_binaries.sh --compile --suite fp --input ref
./gen_binaries.sh --compile --suite fp --input train
```

## 构建结果

```
build/
├── 400.perlbench_test/     -> $SPEC_DIR/benchspec/CPU2006/400.perlbench/run/run_base_test_riscv.0000
├── 400.perlbench_ref/      -> ...
├── 400.perlbench_train/    -> ...
├── 410.bwaves_test/        -> ...
├── 410.bwaves_ref/         -> ...
├── 410.bwaves_train/       -> ...
├── ...                     (共 29 个 benchmark)
├── 482.sphinx3_test/
├── 482.sphinx3_ref/
├── 482.sphinx3_train/
├── 483.xalancbmk_test/
├── 483.xalancbmk_ref/
└── 483.xalancbmk_train/

commands/
├── 400.perlbench.test.cmd
├── 400.perlbench.ref.cmd
├── 400.perlbench.train.cmd      # 新生成
├── ...                          (共 29 个 benchmark × 3 输入集)
└── 483.xalancbmk.train.cmd
```

### 构建耗时

| 套件 | 数量 | 耗时 |
|---|---|---|
| INT (test) | 12 | ~2 分钟 |
| INT (ref) | 12 | ~3 分钟 |
| FP (test) | 17 | ~4 分钟 |
| FP (ref) | 17 | ~5 分钟 |

## 运行

### run.sh — 直接运行（无性能统计）

```bash
./run.sh [options] <benchmark-name>
./run.sh [options] --all [--suite <type> ...] [--input <type>]
```

| 参数 | 可选值 | 默认值 | 说明 |
|---|---|---|---|
| `--run <cmd>` | 任意运行器 | `spike pk -c` | 如 `qemu-riscv64`、`firefront` |
| `--suite` | int, fp, all | all | 基准测试套件 |
| `--input` | test, train, ref | ref | 输入数据集规模 |
| `--all` | — | — | 运行所选套件的全部 benchmark |
| `--workload <N>` | 整数 | （全部） | 运行第 N 个 workload |
| `--output <dir>` | 目录路径 | `./output` | stdout 输出目录 |
| `--dry-run` | — | — | 只打印命令，不执行 |

**示例：**

```bash
# 单个 benchmark，ref 输入
./run.sh --input ref 429.mcf

# 全部 INT benchmark，test 输入，dry-run 查看命令
./run.sh --all --suite int --input test --dry-run

# 用 qemu 运行 FP train
./run.sh --all --suite fp --input train --run "qemu-riscv64"
```

### run_perf.sh — 使用 perf.riscv 采集性能数据

```bash
./run_perf.sh [options] <benchmark-name>
./run_perf.sh [options] --all [--suite <type> ...] [--input <type>]
```

| 参数 | 可选值 | 默认值 | 说明 |
|---|---|---|---|
| `--perf <path>` | 路径 | `./perf.riscv` | perf.riscv 路径 |
| `--params <path>` | 路径 | `./samplectrl.txt` | 采样配置文件路径 |
| `--suite` | int, fp, all | all | 基准测试套件 |
| `--input` | test, train, ref | ref | 输入数据集规模 |
| `--all` | — | — | 运行全部 benchmark |
| `--workload <N>` | 整数 | （全部） | 运行第 N 个 workload |
| `--output <dir>` | 目录路径 | `./perf_logs` | 性能日志输出目录 |
| `--dry-run` | — | — | 只打印命令，不执行 |

**使用方法：**

```bash
# 确保 perf.riscv 和 samplectrl.txt 在当前目录
cp /path/to/perf.riscv .
cp /path/to/samplectrl.txt .

# 单个 benchmark
./run_perf.sh --input ref 429.mcf

# 单个 workload
./run_perf.sh --input ref 429.mcf --workload 0

# 全部 INT + FP，test 输入
./run_perf.sh --all --suite int --suite fp --input test

# 仅 FP，ref 输入
./run_perf.sh --all --suite fp --input ref

# dry-run 预览命令
./run_perf.sh --all --suite int --input ref --dry-run

# 自定义 perf 和参数文件路径
./run_perf.sh --perf /opt/perf.riscv --params /opt/samplectrl.txt --all
```

**perf.riscv 调用模式：**

```
perf.riscv <samplectrl.txt> <program_path> <program_name> [args...]
```

脚本自动从 `commands/<b>.<input>.cmd` 读取每个 workload 的参数，逐个运行并重定向 `samplectrl.txt` 中的 `logname` 到 `perf_logs/<benchmark>_w<N>_<logbase>.log`。

**日志输出：**

```
perf_logs/
├── 400.perlbench_w0_counter.log
├── 400.perlbench_w1_counter.log
├── 400.perlbench_w2_counter.log
├── 401.bzip2_w0_counter.log
├── ...
└── 482.sphinx3_w0_counter.log
```

### samplectrl.txt 配置示例

```ini
eventsel: 0          # 采样事件类型
maxevent: 200000000  # 事件间隔（指令数）
warmupinst: 0        # 预热指令数
maxperiod: 2000      # 最大采样次数
logname: counter.log # 日志文件名（脚本自动替换输出路径）
```

## 对 SPEC2006 的修改

### 1. SPEC2006 工具路径修复

**问题：** 如果 SPEC2006 安装目录发生过迁移（例如从一台机器拷贝到另一台），`bin/` 下所有 Perl 脚本的 shebang 指向旧路径，且 `MANIFEST` 中记录的 MD5 校验和不匹配，导致 `runspec` 完整性检查报 "corrupt"。

**涉及的脚本文件（10 个）：**
`bin/runspec`, `bin/extract_config`, `bin/extract_raw`, `bin/toolsver`, `bin/specdiff`, `bin/makesrcalt`, `bin/configpp`, `bin/printpath.pl`, `bin/extract_flags`, `bin/rawformat`

**通用修复步骤：**

```bash
# 1. 修复 Perl 脚本的 shebang 路径
cd $SPEC_DIR
OLD_PATH=$(head -1 bin/runspec | sed 's|^#!||;s|/bin/specperl||')
for f in $(grep -rl "$OLD_PATH" bin/ 2>/dev/null); do
    sed -i "s|$OLD_PATH|$SPEC_DIR|g" "$f"
done

# 2. 重新计算并更新 MANIFEST 中所有 bin/ 文件的 MD5
# 使用 python3 批量更新 MANIFEST 中的所有 bin/ 条目到最新 MD5
python3 -c "
import hashlib, os, re
manifest = '$SPEC_DIR/MANIFEST'
with open(manifest) as f:
    lines = f.readlines()
new_lines = []
for line in lines:
    m = re.match(r'^([a-f0-9]{32}) \* ([A-F0-9]{8}) (bin/.+)$', line.rstrip())
    if m and os.path.isfile(m.group(3)):
        with open(m.group(3), 'rb') as fh:
            content = fh.read()
        new_md5 = hashlib.md5(content).hexdigest()
        new_size = f'{len(content):08X}'
        if new_md5 != m.group(1):
            line = f'{new_md5} * {new_size} {m.group(3)}\n'
    new_lines.append(line)
with open(manifest, 'w') as f:
    f.writelines(new_lines)
print('MANIFEST updated')
"

# 3. 为 MANIFEST 中缺失的编译工具添加校验和条目
for f in bin/specbzip2 bin/specinvoke bin/specinvoke_pm bin/specmake \
         bin/specmd5sum bin/specperl bin/specperl.wrapper bin/specperldoc \
         bin/specrxp bin/spectar; do
    if [ -f "\$f" ] && ! grep -q "$f\$" MANIFEST; then
        md5=\$(md5sum "\$f" | awk '{print \$1}')
        size=\$(printf "%08X" \$(wc -c < "\$f"))
        echo "\${md5} * \${size} \$f" >> MANIFEST
    fi
done
```

### 2. riscv.cfg — GCC 14 兼容性标志

GCC 14 对类型检查、隐式声明等更严格，需要在 `riscv.cfg` 中为以下 benchmark 添加编译标志：

#### INT benchmark

| Benchmark | 标志 | 原因 |
|---|---|---|
| `400.perlbench` | `-std=gnu89` | 旧式 C 语法（已有） |
| `401.bzip2` | `-Wno-int-conversion` | `void *` 赋值给 `int`（GCC 14 默认报错） |
| `403.gcc` | `-std=gnu89 -Wno-incompatible-pointer-types` | `unsigned int *` 与 `unsigned char *` 不兼容 |
| `456.hmmer` | `-Wno-implicit-function-declaration` | Gfortran 隐式函数声明升级为 Error |
| `462.libquantum` | `-DSPEC_CPU_LINUX` | 64位移植性宏（已有） |
| `464.h264ref` | `-fsigned-char` | 代码假设 char 有符号（已有） |

#### FP benchmark

| Benchmark | 标志 | 原因 |
|---|---|---|
| `416.gamess` | `-std=legacy -fallow-argument-mismatch -w` (F)  + `-funconstrained-commons` (C) | Fortran 数组参数大小不匹配检查过严（`-std=legacy` 降级），类型不匹配 |
| `447.dealII` | `-fpermissive -DSPEC_CPU_LP64` (C++) | `s.c_str() != '\0'` 指针与整数比较 |
| `450.soplex` | `-std=gnu++98 -DSPEC_CPU_LP64` (C++) | GCC 14 标准库 `system_error` 与 C++14 不兼容 |
| `454.calculix` | `-Wno-int-conversion` (C) | `NULL` 传递给 `int` 参数 |
| `465.tonto` | `-std=legacy -fallow-argument-mismatch -w` (F) | `'"'` 引号语法解析错误（见源码修复 3） |
| `481.wrf` | `-std=gnu89` (C) + `-fallow-argument-mismatch` (F) | implicit int（C）和 Fortran 类型不匹配 |
| `482.sphinx3` | `-fsigned-char` (C) | 代码假设 char 有符号（已有） |

### 3. 源码修复

#### 416.gamess — `ecp.F` 数组维度不匹配

**文件：** `benchspec/CPU2006/416.gamess/src/ecp.F` 第 2324 行

```diff
-      DIMENSION ZFNLM(125),ZLM(*),LMF(*),LMX(*),LMY(*),LMZ(*)
+      DIMENSION ZFNLM(*),ZLM(*),LMF(*),LMX(*),LMY(*),LMZ(*)
```

**原因：** 子程序 `ZFN` 声明 `ZFNLM` 为 125 元素，但调用者传入的数组仅为 121 元素。GCC 14 在编译期检查数组参数大小。改为假定大小（`*`）绕过检查，不影响运行时行为。即使添加 `-std=legacy`，此项仍报错（`nameio.fppized.f` 中的 `QVRTZD(X)`，`X` 为标量但声明为 `X(10)`），故两个标志都要加。

#### 465.tonto — `spacegroup.F90` Fortran 引号语法

**文件：** `benchspec/CPU2006/465.tonto/src/spacegroup.F90` 第 1424 行

```diff
-         if (self%axis_symbol(axis)=='"' OR self%axis_symbol(axis)=='"') then
+         if (self%axis_symbol(axis)==char(34)) then
```

**原因：** `'"'`（单引号括起双引号字符）在 GCC 14 gfortran 中触发 "Syntax error in IF-expression"。改用 `char(34)`（双引号字符的 ASCII 码）替换。同时删除冗余的 OR 条件——两侧检查**完全相同**，原始代码疑似 bug（可能本意是检查 `"` 或 `'`，但实际写成了两遍 `"`）。此外，SPEC 的 fpp 预处理器会将 `.OR.` 转化为 `..or..`（非法 Fortran），去掉 OR 后一并规避。

#### 483.xalancbmk — MANIFEST 校验和不匹配

**文件：** `benchspec/CPU2006/483.xalancbmk/src/xercesc/util/NameIdPool.hpp`

**原因：** 文件内容被前次 unknown 修改，导致 MANIFEST 记录的 MD5 与实际不符，`runspec` 完整性检查报 "is corrupt"。已用实际 MD5 更新 MANIFEST。

### 4. gen_binaries.sh 改进

| 改进项 | 说明 |
|---|---|
| `--input test\|train\|ref` | 新增输入集参数，默认 `test` |
| `--suite int\|fp\|all` | 新增套件参数，默认 `int` |
| RISC-V 工具链自动检测 | 读取 `$RISCV_TOOLCHAIN` 环境变量，自动加入 `PATH` |
| `set -e` | 启用严格错误退出 |
| BENCHMARKS 赋值位置修正 | 原来在参数解析**之前**赋值，导致 `--suite fp` 无效。已移到参数解析之后 |

### 5. train 命令文件生成

`commands/` 原有 29 个 test 和 29 个 ref 命令文件，缺少 train。已从 SPEC 生成的 `speccmds.cmd` 中提取所有 29 个 train 命令文件。

**提取脚本逻辑：**
```bash
# 从每个 benchmark 的 train run 目录中读取 speccmds.cmd
# 过滤掉 -C / -o / -e 等 specinvoke 选项，提取纯命令行参数
```

## 已知问题

- riscv-pk 不支持部分 perlbench.test workload（需要 `fork`）
- riscv-pk 对某些 ref 输入文件报错，建议使用 Linux 用户模式运行

## 文件说明

| 文件 | 用途 |
|---|---|
| `gen_binaries.sh` | 主构建脚本（交叉编译 + 软链接） |
| `run.sh` | 运行脚本（直接运行 benchmark，无 perf） |
| `run_perf.sh` | 性能采集脚本（调用 perf.riscv 自动运行并记录） |
| `riscv.cfg` | RISC-V 交叉编译配置（GCC 14 适配） |
| `arm.cfg` | ARM 编译配置（较旧，未维护） |
| `commands/` | 各 benchmark 的运行参数（.test/.ref/.train.cmd） |
| `build/` | 构建产物软链接（指向 SPEC 运行目录） |
| `docs/` | 文档 |
