#!/bin/bash

# run_perf.sh — 使用 perf.riscv 运行 SPEC2006 benchmark 并采集性能数据
#
# 用法:
#   ./run_perf.sh [options] <benchmark-name>
#   ./run_perf.sh [options] --all
#
# 选项:
#   --perf <path>        perf.riscv 的路径 (默认: ./perf.riscv)
#   --params <path>      samplectrl.txt 的路径 (默认: ./samplectrl.txt)
#   --output <dir>       输出目录 (默认: ./perf_logs)
#   --workload <N>       只运行第 N 个 workload (默认: 全部)
#   --all                运行所有 benchmark
#   --suite <type>       套件: int | fp | all (默认: all)
#   --input <type>       输入集: test | train | ref (默认: ref)
#   --dry-run            只打印要执行的命令，不实际运行

set -e

BUILD_DIR="${PWD}/build"
COMMANDS_DIR="${PWD}/commands"
DEFAULT_RUN="${TARGET_RUN:-spike pk -c}"

PERF="${PWD}/perf.riscv"
PARAMS="${PWD}/samplectrl.txt"
OUTPUT_DIR="${PWD}/perf_logs"
WORKLOAD_NUM=""
BENCHMARK=""
ALL_MODE=false
SUITE_TYPES=()
INPUT_TYPE="ref"
DRY_RUN=false

INT_BENCHMARKS=(400.perlbench 401.bzip2 403.gcc 429.mcf 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 473.astar 483.xalancbmk)
FP_BENCHMARKS=(410.bwaves 416.gamess 433.milc 434.zeusmp 435.gromacs 436.cactusADM 437.leslie3d 444.namd 447.dealII 450.soplex 453.povray 454.calculix 459.GemsFDTD 465.tonto 470.lbm 481.wrf 482.sphinx3)

function usage {
    echo "usage: run_perf.sh [options] <benchmark-name>"
    echo "       run_perf.sh [options] --all [--suite <type> ...] [--input <type>]"
    echo ""
    echo "   --perf <path>        perf.riscv 路径 (默认: ./perf.riscv)"
    echo "   --params <path>      samplectrl.txt 路径 (默认: ./samplectrl.txt)"
    echo "   --output <dir>       输出目录 (默认: ./perf_logs)"
    echo "   --workload <N>       只运行第 N 个 workload (默认: 全部)"
    echo "   --all                运行所有 benchmark"
    echo "   --suite <type>       套件: int | fp | all (默认: all)"
    echo "                        可多次指定: --suite int --suite fp"
    echo "   --input <type>       输入集: test | train | ref (默认: ref)"
    echo "   --dry-run            只打印命令，不实际执行"
}

while test $# -gt 0; do
    case "$1" in
        --perf)
            shift; PERF="$1" ;;
        --params)
            shift; PARAMS="$1" ;;
        --output)
            shift; OUTPUT_DIR="$1" ;;
        --workload)
            shift; WORKLOAD_NUM="$1" ;;
        --all)
            ALL_MODE=true ;;
        --dry-run)
            DRY_RUN=true ;;
        --suite)
            shift
            if [ "$1" = "all" ]; then
                SUITE_TYPES=(int fp)
            elif [ "$1" = "int" ] || [ "$1" = "fp" ]; then
                SUITE_TYPES+=("$1")
            else
                echo "ERROR: unknown suite '$1' (use int, fp, or all)"
                exit 1
            fi ;;
        --input)
            shift; INPUT_TYPE="$1" ;;
        -h | -H | --help)
            usage; exit 0 ;;
        --*)
            echo "ERROR: bad option $1"; usage; exit 1 ;;
        *)
            if [ -z "$BENCHMARK" ]; then
                BENCHMARK="$1"
            else
                echo "ERROR: unexpected argument $1"; usage; exit 1
            fi ;;
    esac
    shift
done

# 默认所有套件
if [ ${#SUITE_TYPES[@]} -eq 0 ]; then
    SUITE_TYPES=(int fp)
fi

# 确定要运行的 benchmark 列表
if [ "$ALL_MODE" = true ] || [ -n "$BENCHMARK" ]; then
    BENCHMARKS=()
    if [ -n "$BENCHMARK" ]; then
        BENCHMARKS=("$BENCHMARK")
    else
        for suite in "${SUITE_TYPES[@]}"; do
            if [ "$suite" = "int" ]; then
                BENCHMARKS+=("${INT_BENCHMARKS[@]}")
            elif [ "$suite" = "fp" ]; then
                BENCHMARKS+=("${FP_BENCHMARKS[@]}")
            fi
        done
    fi
else
    echo "ERROR: specify a benchmark name or --all"
    usage; exit 1
fi

# 检查 perf.riscv 和参数文件（dry-run 模式不检查）
if [ "$DRY_RUN" = false ]; then
    if [ ! -x "$PERF" ]; then
        echo "ERROR: perf.riscv not found or not executable: $PERF"
        exit 1
    fi
    if [ ! -f "$PARAMS" ]; then
        echo "ERROR: params file not found: $PARAMS"
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR"

# 从 params 提取日志基名
if [ -f "$PARAMS" ]; then
    LOGBASE=$(grep -E "^logname:" "$PARAMS" | awk '{print $2}' | sed 's/\.log$//')
fi
LOGBASE="${LOGBASE:-counter}"

function get_short_exe {
    local b="$1"
    local short=${b##*.}
    if [ "$b" = "482.sphinx3" ]; then
        short="sphinx_livepretend"
    elif [ "$b" = "483.xalancbmk" ]; then
        short="Xalan"
    fi
    echo "${short}"
}

function run_workload {
    local bmark_dir="$1"
    local bmark_name="$2"
    local short_exe="$3"
    local args="$4"
    local widx="$5"

    local binary="${bmark_dir}/${short_exe}_base.riscv"
    if [ ! -f "$binary" ]; then
        binary="${bmark_dir}/${short_exe}"
    fi
    if [ ! -f "$binary" ]; then
        echo "ERROR: binary not found for $bmark_name"
        return 1
    fi

    local log_file="${OUTPUT_DIR}/${bmark_name}_w${widx}_${LOGBASE}.log"
    echo "  [${bmark_name}] workload ${widx}: $(basename "$binary") $(echo "$args" | cut -c1-80)"

    if [ "$DRY_RUN" = true ]; then
        echo "    -> perf.riscv <params> ${binary} $(basename "$binary") $args"
        return 0
    fi

    local tmp_params="${OUTPUT_DIR}/.tmp_samplectrl_$$.txt"
    sed "s|^logname:.*|logname: ${log_file}|" "$PARAMS" > "$tmp_params"

    (
        cd "$bmark_dir" || exit 1
        "$PERF" "$tmp_params" "./$(basename "$binary")" "$(basename "$binary")" $args
    )
    local rc=$?

    rm -f "$tmp_params"

    if [ $rc -ne 0 ]; then
        echo "  WARNING: perf.riscv exited with code $rc"
    fi
    return 0
}

function run_benchmark {
    local bmark_name="$1"
    local bmark_dir="${BUILD_DIR}/${bmark_name}_${INPUT_TYPE}"
    local cmd_file="${COMMANDS_DIR}/${bmark_name}.${INPUT_TYPE}.cmd"

    if [ ! -d "$bmark_dir" ]; then
        echo "WARNING: build dir not found: $bmark_dir, skipping"
        return 0
    fi
    if [ ! -f "$cmd_file" ]; then
        echo "WARNING: cmd file not found: $cmd_file, skipping"
        return 0
    fi

    echo "=== Benchmark: ${bmark_name} (${INPUT_TYPE}) ==="

    local short_exe=$(get_short_exe "$bmark_name")

    IFS=$'\n' read -d '' -r -a commands < "$cmd_file" || true

    local widx=0
    for input in "${commands[@]}"; do
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"
        if [[ -z "$input" || "${input:0:1}" == '#' ]]; then
            continue
        fi
        if [ -n "$WORKLOAD_NUM" ] && [ "$widx" -ne "$WORKLOAD_NUM" ]; then
            widx=$((widx + 1))
            continue
        fi
        run_workload "$bmark_dir" "$bmark_name" "$short_exe" "$input" "$widx"
        widx=$((widx + 1))
    done
    echo ""
}

echo "== SPEC2006 run_perf =="
echo "  perf    : $PERF"
echo "  params  : $PARAMS"
echo "  output  : $OUTPUT_DIR"
echo "  suites  : ${SUITE_TYPES[*]}"
echo "  input   : $INPUT_TYPE"
echo "  dry-run : $DRY_RUN"
echo ""

total=0
for b in "${BENCHMARKS[@]}"; do
    run_benchmark "$b"
    total=$((total + 1))
done

echo "Done! Ran $total benchmarks. Logs in: $OUTPUT_DIR"
