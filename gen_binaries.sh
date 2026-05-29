#!/bin/bash
set -e

if [ -z "$SPEC_DIR" ]; then
   echo "  Please set the SPEC_DIR environment variable to point to your copy of SPEC CPU2006."
   exit 1
fi

# RISC-V toolchain
RISCV_TOOLCHAIN="${RISCV_TOOLCHAIN:-/home/sxz/rv-toolchain/install/rv64g/bin}"
if [ -d "$RISCV_TOOLCHAIN" ]; then
   export PATH="${RISCV_TOOLCHAIN}:${PATH}"
   echo "  Using RISC-V toolchain: ${RISCV_TOOLCHAIN}"
fi

CONFIG=riscv
CONFIGFILE=${CONFIG}.cfg
RUN="spike pk -c "
INPUT_TYPE=test
SUITE_TYPE=int

INT_BENCHMARKS=(400.perlbench 401.bzip2 403.gcc 429.mcf 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 473.astar 483.xalancbmk)
FP_BENCHMARKS=(410.bwaves 416.gamess 433.milc 434.zeusmp 435.gromacs 436.cactusADM 437.leslie3d 444.namd 447.dealII 450.soplex 453.povray 454.calculix 459.GemsFDTD 465.tonto 470.lbm 481.wrf 482.sphinx3)

compileFlag=false
runFlag=false
packageFlag=false

function usage {
    echo "usage: gen_binaries.sh [--compile | --run | --package] [--input test|train|ref] [--suite int|fp|all]"
    echo ""
    echo "  --compile     Build binaries and create build/ symlinks (one input type)"
    echo "  --run         Run previously built benchmarks"
    echo "  --package     Build all 3 input types and create FPGA-ready portable dir"
    echo "  --input       Input set: test | train | ref (default: test)"
    echo "  --suite       Benchmark suite: int | fp | all (default: int)"
}

while test $# -gt 0; do
   case "$1" in
        --compile) compileFlag=true ;;
        --run)     runFlag=true ;;
        --package) packageFlag=true ;;
        --input)   shift; INPUT_TYPE=$1 ;;
        --suite)   shift; SUITE_TYPE=$1 ;;
        -h|-H|--help) usage; exit 0 ;;
        --*) echo "ERROR: bad option $1"; usage; exit 1 ;;
        *)   echo "ERROR: bad argument $1"; usage; exit 2 ;;
    esac
    shift
done

# set BENCHMARKS
case "${SUITE_TYPE}" in
    fp)  BENCHMARKS=("${BENCHMARKS_FP[@]}") ;;
    all) BENCHMARKS=("${BENCHMARKS_INT[@]}" "${BENCHMARKS_FP[@]}") ;;
    *)   BENCHMARKS=("${BENCHMARKS_INT[@]}") ;;
esac

echo "== Speckle Options =="
echo "  Config  : ${CONFIG}"
echo "  Suite   : ${SUITE_TYPE}"
echo "  Input   : ${INPUT_TYPE}"
echo "  compile : $compileFlag"
echo "  run     : $runFlag"
echo "  package : $packageFlag"
echo ""

BUILD_DIR=$PWD/build
PACKAGE_DIR=$PWD/spec2006-portable
mkdir -p build

function get_short_exe {
    local b="$1"
    local short=${b##*.}
    [ "$b" = "482.sphinx3" ] && short="sphinx_livepretend"
    [ "$b" = "483.xalancbmk" ] && short="Xalan"
    echo "${short}"
}

# ── Compile ──────────────────────────────────────────────────────────
if [ "$compileFlag" = true ] || [ "$packageFlag" = true ]; then
   INPUTS_TO_BUILD=("$INPUT_TYPE")
   if [ "$packageFlag" = true ]; then
       INPUTS_TO_BUILD=(test train ref)
       rm -rf "$PACKAGE_DIR"
       mkdir -p "$PACKAGE_DIR"/{commands,output,perf_logs}
   fi

   cp "$(dirname "$0")/${CONFIGFILE}" "$SPEC_DIR/config/${CONFIGFILE}"

   for cur_input in "${INPUTS_TO_BUILD[@]}"; do
       echo "=== Building: suite=${SUITE_TYPE} input=${cur_input} ==="
       cd "$SPEC_DIR"
       . ./shrc
       time runspec --config ${CONFIG} --size ${cur_input} --action setup ${SUITE_TYPE} || true
       cd "$OLDPWD"
   done

   # Create build/ symlinks (local use)
   for b in "${BENCHMARKS[@]}"; do
       short_exe=$(get_short_exe "$b")
       BMK_DIR="$SPEC_DIR/benchspec/CPU2006/$b/run/run_base_${INPUT_TYPE}_${CONFIG}.0000"
       LINK="$BUILD_DIR/${b}_${INPUT_TYPE}"
       [ -L "$LINK" ] && unlink "$LINK" 2>/dev/null || true
       [ -d "$BMK_DIR" ] && ln -sf "$BMK_DIR" "$LINK"
   done
fi

# ── Package (FPGA-ready portable dir) ─────────────────────────────────
if [ "$packageFlag" = true ]; then
   echo ""
   echo "=== Packaging for FPGA ==="

   for b in "${BENCHMARKS[@]}"; do
       short_exe=$(get_short_exe "$b")
       mkdir -p "$PACKAGE_DIR/$b"

       # Copy binary (all 3 input types use the same binary — grab from ref if available)
       binary=""
       for cur_input in ref test train; do
           run_dir="$SPEC_DIR/benchspec/CPU2006/$b/run/run_base_${cur_input}_${CONFIG}.0000"
           [ ! -d "$run_dir" ] && continue
           bin_candidate="${run_dir}/${short_exe}_base.${CONFIG}"
           [ ! -f "$bin_candidate" ] && bin_candidate="${run_dir}/${short_exe}"
           if [ -f "$bin_candidate" ]; then
               binary="$bin_candidate"
               break
           fi
       done

       if [ -z "$binary" ]; then
           echo "  SKIP $b (no binary found)"
           continue
       fi
       cp "$binary" "$PACKAGE_DIR/$b/${short_exe}"

       # Copy input files per input type into subdirs
       for cur_input in test train ref; do
           run_dir="$SPEC_DIR/benchspec/CPU2006/$b/run/run_base_${cur_input}_${CONFIG}.0000"
           [ ! -d "$run_dir" ] && continue
           mkdir -p "$PACKAGE_DIR/$b/$cur_input"
           for f in "$run_dir"/*; do
               case "$(basename "$f")" in
                   *_base.*|*.o|*.a|Makefile*|*.deps|*.spec|speccmds.cmd|compare.cmd|compare.err|*.out|*.err|*.log)
                       continue ;;
               esac
               if [ -d "$f" ]; then
                   cp -r "$f" "$PACKAGE_DIR/$b/$cur_input/"
               else
                   cp "$f" "$PACKAGE_DIR/$b/$cur_input/"
               fi
           done
       done

       # 403.gcc: SPEC provides .i files, benchmark expects .in
       if [ "$b" = "403.gcc" ]; then
           for cur_input in test train ref; do
               for i in "$PACKAGE_DIR/$b/$cur_input"/*.i; do
                   [ -f "$i" ] && ln -sf "$(basename "$i")" "$PACKAGE_DIR/$b/$cur_input/$(basename "$i" .i).in"
               done
           done
       fi
       # 459.GemsFDTD: command uses test.in, file named by input type
       if [ "$b" = "459.GemsFDTD" ]; then
           for cur_input in test train ref; do
               local_dir="$PACKAGE_DIR/$b/$cur_input"
               [ -f "$local_dir/ref.in" ] && [ ! -f "$local_dir/test.in" ] && ln -sf ref.in "$local_dir/test.in"
               [ -f "$local_dir/train.in" ] && [ ! -f "$local_dir/test.in" ] && ln -sf train.in "$local_dir/test.in"
           done
       fi

       echo "  OK   $b ($(du -sh "$PACKAGE_DIR/$b" | cut -f1))"
   done

   # Copy command files
   for cur_input in test train ref; do
       cp commands/*."${cur_input}".cmd "$PACKAGE_DIR/commands/" 2>/dev/null || true
   done
   # Fix empty GemsFDTD train cmd
   [ -f "$PACKAGE_DIR/commands/459.GemsFDTD.train.cmd" ] && [ ! -s "$PACKAGE_DIR/commands/459.GemsFDTD.train.cmd" ] && \
       echo "< test.in" > "$PACKAGE_DIR/commands/459.GemsFDTD.train.cmd"

   # ── Generate run.sh ──
   cat > "$PACKAGE_DIR/run.sh" << 'RUNEOF'
#!/bin/bash
set -e
RUN="${TARGET_RUN:-spike pk -c}"
OUTPUT_DIR="${PWD}/output"
WORKLOAD_NUM=""
BENCHMARK=""
ALL_MODE=false
SUITE_TYPES=()
INPUT_TYPE="ref"
DRY_RUN=false
BASE_DIR="${PWD}"

INT_BENCHMARKS=(400.perlbench 401.bzip2 403.gcc 429.mcf 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 473.astar 483.xalancbmk)
FP_BENCHMARKS=(410.bwaves 416.gamess 433.milc 434.zeusmp 435.gromacs 436.cactusADM 437.leslie3d 444.namd 447.dealII 450.soplex 453.povray 454.calculix 459.GemsFDTD 465.tonto 470.lbm 481.wrf 482.sphinx3)

function usage {
    echo "usage: run.sh [options] <benchmark-name>"
    echo "       run.sh [options] --all"
    echo "  --run <cmd>      runner (default: spike pk -c)"
    echo "  --suite <type>   int | fp | all (default: all)"
    echo "  --input <type>   test | train | ref (default: ref)"
    echo "  --all            run all benchmarks"
    echo "  --workload <N>   run only workload N"
    echo "  --dry-run        print commands only"
}

while test $# -gt 0; do
    case "$1" in
        --run) shift; RUN="$1" ;;
        --output) shift; OUTPUT_DIR="$1" ;;
        --workload) shift; WORKLOAD_NUM="$1" ;;
        --all) ALL_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --suite) shift
            case "$1" in all) SUITE_TYPES=(int fp) ;; int|fp) SUITE_TYPES+=("$1") ;; *) echo "bad suite: $1"; exit 1 ;; esac ;;
        --input) shift; INPUT_TYPE="$1" ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "bad option: $1"; usage; exit 1 ;;
        *) [ -z "$BENCHMARK" ] && BENCHMARK="$1" || { echo "unexpected: $1"; usage; exit 1; } ;;
    esac
    shift
done

[ ${#SUITE_TYPES[@]} -eq 0 ] && SUITE_TYPES=(int fp)

if [ -n "$BENCHMARK" ]; then BENCHMARKS=("$BENCHMARK")
elif [ "$ALL_MODE" = true ]; then
    BENCHMARKS=()
    for s in "${SUITE_TYPES[@]}"; do
        [ "$s" = "int" ] && BENCHMARKS+=("${INT_BENCHMARKS[@]}")
        [ "$s" = "fp" ] && BENCHMARKS+=("${FP_BENCHMARKS[@]}")
    done
else echo "ERROR: specify benchmark or --all"; usage; exit 1; fi

mkdir -p "$OUTPUT_DIR"

function get_short_exe {
    local b="$1"; local short=${b##*.}
    [ "$b" = "482.sphinx3" ] && short="sphinx_livepretend"
    [ "$b" = "483.xalancbmk" ] && short="Xalan"
    echo "${short}"
}

function run_workload {
    local bmark_dir="$1" bmark_name="$2" short_exe="$3" args="$4" widx="$5" input_dir="$6"
    local binary="${bmark_dir}/${short_exe}"
    [ ! -f "$binary" ] && { echo "ERROR: binary not found: $binary"; return 1; }
    [ ! -x "$binary" ] && chmod +x "$binary" 2>/dev/null || true

    local stdin_file="" clean_args=() saw=false
    for arg in $args; do
        if [ "$saw" = true ]; then stdin_file="$arg"; saw=false
        elif [ "$arg" = "<" ]; then saw=true
        else clean_args+=("$arg"); fi
    done

    local out_file="${OUTPUT_DIR}/${bmark_name}.${widx}.out"
    echo "  [${bmark_name}] workload ${widx}"

    if [ "$DRY_RUN" = true ]; then
        local redir=""; [ -n "$stdin_file" ] && redir=" < ${input_dir}/${stdin_file}"
        echo "    -> cd ${input_dir} && ${RUN} ../${short_exe} ${clean_args[*]}${redir} > ${out_file}"
        return 0
    fi

    ( cd "$input_dir" || exit 1
      if [ -n "$stdin_file" ]; then
          eval "${RUN} ../${short_exe} ${clean_args[*]} < ${stdin_file} > ${out_file}" 2>&1 || true
      else
          eval "${RUN} ../${short_exe} ${clean_args[*]} > ${out_file}" 2>&1 || true
      fi
    )
}

for b in "${BENCHMARKS[@]}"; do
    bmark_dir="${BASE_DIR}/${b}"; input_dir="${bmark_dir}/${INPUT_TYPE}"
    cmd_file="${BASE_DIR}/commands/${b}.${INPUT_TYPE}.cmd"
    [ ! -d "$bmark_dir" ] && { echo "WARNING: $b not found, skipping"; continue; }
    [ ! -d "$input_dir" ] && { echo "WARNING: $b/$INPUT_TYPE not found, skipping"; continue; }
    [ ! -f "$cmd_file" ] && { echo "WARNING: no cmd file for $b/$INPUT_TYPE, skipping"; continue; }

    echo "=== Benchmark: ${b} (${INPUT_TYPE}) ==="
    short_exe=$(get_short_exe "$b")
    IFS=$'\n' read -d '' -r -a commands < "$cmd_file" || true
    widx=0
    for input in "${commands[@]}"; do
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"
        [ -z "$input" ] && continue
        [ "${input:0:1}" = "#" ] && continue
        [ -n "$WORKLOAD_NUM" ] && [ "$widx" -ne "$WORKLOAD_NUM" ] && { widx=$((widx+1)); continue; }
        run_workload "$bmark_dir" "$b" "$short_exe" "$input" "$widx" "$input_dir"
        widx=$((widx+1))
    done
    echo ""
done
echo "Done! Output in: $OUTPUT_DIR"
RUNEOF

   # ── Generate run_perf.sh ──
   cat > "$PACKAGE_DIR/run_perf.sh" << 'PERFEOF'
#!/bin/bash
set -e
PERF="${PWD}/perf.riscv"
PARAMS="${PWD}/samplectrl.txt"
OUTPUT_DIR="${PWD}/perf_logs"
WORKLOAD_NUM=""
BENCHMARK=""
ALL_MODE=false
SUITE_TYPES=()
INPUT_TYPE="ref"
DRY_RUN=false
BASE_DIR="${PWD}"

INT_BENCHMARKS=(400.perlbench 401.bzip2 403.gcc 429.mcf 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 473.astar 483.xalancbmk)
FP_BENCHMARKS=(410.bwaves 416.gamess 433.milc 434.zeusmp 435.gromacs 436.cactusADM 437.leslie3d 444.namd 447.dealII 450.soplex 453.povray 454.calculix 459.GemsFDTD 465.tonto 470.lbm 481.wrf 482.sphinx3)

function usage {
    echo "usage: run_perf.sh [options] <benchmark-name>"
    echo "       run_perf.sh [options] --all"
    echo "  --perf <path>     perf.riscv path (default: ./perf.riscv)"
    echo "  --params <path>   samplectrl.txt path (default: ./samplectrl.txt)"
    echo "  --suite <type>    int | fp | all (default: all)"
    echo "  --input <type>    test | train | ref (default: ref)"
    echo "  --all             run all benchmarks"
    echo "  --workload <N>    run only workload N"
    echo "  --dry-run         print commands only"
}

while test $# -gt 0; do
    case "$1" in
        --perf) shift; PERF="$1" ;;
        --params) shift; PARAMS="$1" ;;
        --output) shift; OUTPUT_DIR="$1" ;;
        --workload) shift; WORKLOAD_NUM="$1" ;;
        --all) ALL_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --suite) shift
            case "$1" in all) SUITE_TYPES=(int fp) ;; int|fp) SUITE_TYPES+=("$1") ;; *) echo "bad suite: $1"; exit 1 ;; esac ;;
        --input) shift; INPUT_TYPE="$1" ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "bad option: $1"; usage; exit 1 ;;
        *) [ -z "$BENCHMARK" ] && BENCHMARK="$1" || { echo "unexpected: $1"; usage; exit 1; } ;;
    esac
    shift
done

[ ${#SUITE_TYPES[@]} -eq 0 ] && SUITE_TYPES=(int fp)

if [ -n "$BENCHMARK" ]; then BENCHMARKS=("$BENCHMARK")
elif [ "$ALL_MODE" = true ]; then
    BENCHMARKS=()
    for s in "${SUITE_TYPES[@]}"; do
        [ "$s" = "int" ] && BENCHMARKS+=("${INT_BENCHMARKS[@]}")
        [ "$s" = "fp" ] && BENCHMARKS+=("${FP_BENCHMARKS[@]}")
    done
else echo "ERROR: specify benchmark or --all"; usage; exit 1; fi

if [ "$DRY_RUN" = false ]; then
    [ ! -x "$PERF" ] && { echo "ERROR: perf.riscv not found: $PERF"; exit 1; }
    [ ! -f "$PARAMS" ] && { echo "ERROR: params not found: $PARAMS"; exit 1; }
fi

mkdir -p "$OUTPUT_DIR"

LOGBASE="counter"
if [ -f "$PARAMS" ]; then
    LOGBASE=$(grep -E "^logname:" "$PARAMS" | awk '{print $2}' | sed 's/\.log$//')
    LOGBASE="${LOGBASE:-counter}"
fi

function get_short_exe {
    local b="$1"; local short=${b##*.}
    [ "$b" = "482.sphinx3" ] && short="sphinx_livepretend"
    [ "$b" = "483.xalancbmk" ] && short="Xalan"
    echo "${short}"
}

function run_workload {
    local bmark_dir="$1" bmark_name="$2" short_exe="$3" args="$4" widx="$5" input_dir="$6"
    local binary="${bmark_dir}/${short_exe}"
    [ ! -f "$binary" ] && { echo "ERROR: binary not found: $binary"; return 1; }
    [ ! -x "$binary" ] && chmod +x "$binary" 2>/dev/null || true

    local stdin_file="" clean_args=() saw=false
    for arg in $args; do
        if [ "$saw" = true ]; then stdin_file="$arg"; saw=false
        elif [ "$arg" = "<" ]; then saw=true
        else clean_args+=("$arg"); fi
    done

    local log_file="${OUTPUT_DIR}/${bmark_name}_w${widx}_${LOGBASE}.log"
    echo "  [${bmark_name}] workload ${widx}"

    if [ "$DRY_RUN" = true ]; then
        local redir=""; [ -n "$stdin_file" ] && redir=" < ${input_dir}/${stdin_file}"
        echo "    -> cd ${input_dir} && perf.riscv ... ../${short_exe} ${clean_args[*]}${redir}"
        return 0
    fi

    local tmp_params="${OUTPUT_DIR}/.tmp_samplectrl_$$.txt"
    sed "s|^logname:.*|logname: ${log_file}|" "$PARAMS" > "$tmp_params"

    ( cd "$input_dir" || exit 1
      if [ -n "$stdin_file" ]; then
          "$PERF" "$tmp_params" "../${short_exe}" "${short_exe}" "${clean_args[@]}" < "$stdin_file"
      else
          "$PERF" "$tmp_params" "../${short_exe}" "${short_exe}" "${clean_args[@]}"
      fi
    )
    local rc=$?
    rm -f "$tmp_params"
    [ $rc -ne 0 ] && echo "  WARNING: perf.riscv exited with code $rc"
    return 0
}

for b in "${BENCHMARKS[@]}"; do
    bmark_dir="${BASE_DIR}/${b}"; input_dir="${bmark_dir}/${INPUT_TYPE}"
    cmd_file="${BASE_DIR}/commands/${b}.${INPUT_TYPE}.cmd"
    [ ! -d "$bmark_dir" ] && { echo "WARNING: $b not found, skipping"; continue; }
    [ ! -d "$input_dir" ] && { echo "WARNING: $b/$INPUT_TYPE not found, skipping"; continue; }
    [ ! -f "$cmd_file" ] && { echo "WARNING: no cmd file for $b/$INPUT_TYPE, skipping"; continue; }

    echo "=== Benchmark: ${b} (${INPUT_TYPE}) ==="
    short_exe=$(get_short_exe "$b")
    IFS=$'\n' read -d '' -r -a commands < "$cmd_file" || true
    widx=0
    for input in "${commands[@]}"; do
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"
        [ -z "$input" ] && continue
        [ "${input:0:1}" = "#" ] && continue
        [ -n "$WORKLOAD_NUM" ] && [ "$widx" -ne "$WORKLOAD_NUM" ] && { widx=$((widx+1)); continue; }
        run_workload "$bmark_dir" "$b" "$short_exe" "$input" "$widx" "$input_dir"
        widx=$((widx+1))
    done
    echo ""
done
echo "Done! Logs in: $OUTPUT_DIR"
PERFEOF

   chmod +x "$PACKAGE_DIR/run.sh" "$PACKAGE_DIR/run_perf.sh"

   echo ""
   echo "=== Package ready: $PACKAGE_DIR ==="
   echo "Total size: $(du -sh "$PACKAGE_DIR" | cut -f1)"
   echo ""
   echo "Copy to FPGA:"
   echo "  rsync -av $PACKAGE_DIR/ root@<fpga>:/data/spec2006/"
   echo ""
   echo "On FPGA:"
   echo "  cd /data/spec2006"
   echo "  ./run.sh --all --input test         # test input set"
   echo "  ./run.sh --all --input train        # train input set"
   echo "  ./run.sh --all --input ref          # ref input set"
   echo "  ./run_perf.sh --all --input ref     # perf mode"
fi

# ── Run ──────────────────────────────────────────────────────────────
if [ "$runFlag" = true ]; then
   for b in "${BENCHMARKS[@]}"; do
      cd "$BUILD_DIR/${b}_${INPUT_TYPE}"
      SHORT_EXE=${b##*.}
      [ "$b" = "482.sphinx3" ] && SHORT_EXE=sphinx_livepretend
      [ "$b" = "483.xalancbmk" ] && SHORT_EXE=Xalan

      IFS=$'\n' read -d '' -r -a commands < "$(dirname "$0")/commands/${b}.${INPUT_TYPE}.cmd" || true
      for input in "${commands[@]}"; do
         if [[ ${input:0:1} != '#' ]]; then
            echo "~~~Running ${b}"
            echo "  ${RUN} ${SHORT_EXE}_base.${CONFIG} ${input}"
            eval ${RUN} ${SHORT_EXE}_base.${CONFIG} ${input}
         fi
      done
   done
fi

echo ""
echo "Done!"
