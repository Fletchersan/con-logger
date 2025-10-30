#!/usr/bin/env bash

set -euo pipefail

# Benchmark Python ingestor vs grep and awk.
# Note:
#   again this is ai generated, because this isn't the point of the project
# Usage:
#   ./scripts/benchmark.sh \
#     --input testdata/logs_100M.txt \
#     --pattern 'ERROR' \
#     --runs 5 \
#     --python-cmd 'python python_logger/src/main.py'
#
# Optional:
#   --mode lines|count   # output mode fed to python tool (default: lines)
#   --warmup 1           # warmup runs not counted (default: 1)
#   --output <prefix>    # write summary to <prefix>.txt and <prefix>.csv

INPUT=""
PATTERN=""
RUNS=5
WARMUP=1
MODE="lines"
PYTHON_CMD="python python_logger/src/main.py"
OUT_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="$2"; shift 2;;
    --pattern)
      PATTERN="$2"; shift 2;;
    --runs)
      RUNS="$2"; shift 2;;
    --warmup)
      WARMUP="$2"; shift 2;;
    --mode)
      MODE="$2"; shift 2;;
    --python-cmd)
      PYTHON_CMD="$2"; shift 2;;
    --output)
      OUT_PREFIX="$2"; shift 2;;
    -h|--help)
      sed -n '1,80p' "$0"; exit 0;;
    *)
      echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$INPUT" || -z "$PATTERN" ]]; then
  echo "ERROR: --input and --pattern are required" >&2
  exit 2
fi

if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: input file not found: $INPUT" >&2
  exit 2
fi

# Detect stat and time variants (macOS vs Linux)
STAT_BYTES_CMD=""
if stat -c%s "$INPUT" >/dev/null 2>&1; then
  STAT_BYTES_CMD=(stat -c%s)
elif stat -f%z "$INPUT" >/dev/null 2>&1; then
  STAT_BYTES_CMD=(stat -f%z)
else
  echo "ERROR: could not determine a working stat command" >&2
  exit 2
fi

TIME_CMD="/usr/bin/time"
TIME_FMT_GNU="%e %U %S %M"  # real user sys maxrss
TIME_FMT_BSD="%e %U %S %M"  # fallback, but BSD time lacks -f; prefer gtime

if command -v gtime >/dev/null 2>&1; then
  TIME_CMD="gtime"
fi

TIME_FLAG="-f"
if ! $TIME_CMD -f "%e" true >/dev/null 2>&1; then
  # BSD time does not support -f; degrade to shell time with only wall clock
  TIME_FLAG=""
fi

BYTES=$(${STAT_BYTES_CMD[@]} "$INPUT")
LINES=$(wc -l < "$INPUT" | tr -d ' ')

echo "Benchmarking on: $INPUT" >&2
echo "Size: $BYTES bytes | Lines: $LINES" >&2
echo "Pattern: $PATTERN" >&2
echo "Runs: $RUNS (warmup: $WARMUP)" >&2

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'bench')
trap 'rm -rf "$tmpdir"' EXIT

RESULTS_CSV="$tmpdir/results.csv"
echo "tool,run,real_s,user_s,sys_s,maxrss_kb,mbps,lines_per_s" > "$RESULTS_CSV"

run_one() {
  local tool="$1"; shift
  local cmd=("$@")

  local time_real=0 time_user=0 time_sys=0 max_rss=0

  if [[ -n "$TIME_FLAG" ]]; then
    # Capture: real user sys maxrss (GNU time -f "%e %U %S %M")
    local stats
    stats=$($TIME_CMD -f "%e %U %S %M" bash -c "${cmd[*]}" 2>&1 >/dev/null)
    time_real=$(echo "$stats" | awk '{print $1}')
    time_user=$(echo "$stats" | awk '{print $2}')
    time_sys=$(echo   "$stats" | awk '{print $3}')
    max_rss=$(echo    "$stats" | awk '{print $4}')
  else
    # Fallback: measure wall clock only
    local start end
    start=$(date +%s.%N)
    bash -c "${cmd[*]}" >/dev/null 2>&1 || true
    end=$(date +%s.%N)
    time_real=$(awk -v s="$start" -v e="$end" 'BEGIN{print e-s}')
    time_user=0; time_sys=0; max_rss=0
  fi

  # Compute MB/s and lines/s
  local mbps=0
  local lps=0
  if awk "BEGIN{exit !($time_real>0)}"; then
    mbps=$(awk -v b="$BYTES" -v t="$time_real" 'BEGIN{print (b/1e6)/t}')
    lps=$(awk -v l="$LINES" -v t="$time_real" 'BEGIN{print l/t}')
  fi

  echo "$tool,$RUN_IDX,$time_real,$time_user,$time_sys,$max_rss,$mbps,$lps"
}

RUN_IDX=0
total_runs=$((WARMUP + RUNS))
for tool in python grep awk; do
  for ((i=1;i<=total_runs;i++)); do
    RUN_IDX=$i
    case "$tool" in
      python)
        # Adjust this invocation to match your CLI for the Python ingestor
        # Assumes: --input, --filter-pattern, --output-format
        cmd=(
          $PYTHON_CMD \
          --input "$INPUT" \
          --filter-pattern "$PATTERN" \
          --output-format "$MODE"
        )
        ;;
      grep)
        cmd=(grep -E "$PATTERN" "$INPUT")
        ;;
      awk)
        # Simple regex match; adapts to basic awk
        cmd=(awk -v p="$PATTERN" 'BEGIN{IGNORECASE=0} $0 ~ p {print}' "$INPUT")
        ;;
    esac

    if (( i <= WARMUP )); then
      # Warmup run (discarded)
      if [[ "$tool" == "python" ]]; then
        : # allow JIT caches, imports, etc.
      fi
      run_one "$tool" "${cmd[@]}" >/dev/null || true
      continue
    fi

    run_one "$tool" "${cmd[@]}" >> "$RESULTS_CSV" || true
  done
done

# Summarize
summary_txt="$tmpdir/summary.txt"
{
  echo "Tool         Runs  real_s(avg)  MB/s(avg)  lines/s(avg)"
  echo "-------------------------------------------------------"
  for tool in python grep awk; do
    awk -F, -v t="$tool" 'NR>1 && $1==t {n++; r+=$3; m+=$7; l+=$8}
      END{ if(n>0) printf("%-12s %4d  %11.3f  %9.2f  %12.0f\n", \
      t, n, r/n, m/n, l/n); }' "$RESULTS_CSV"
  done
} > "$summary_txt"

cat "$summary_txt"

if [[ -n "$OUT_PREFIX" ]]; then
  mkdir -p "$(dirname "$OUT_PREFIX")"
  cp "$summary_txt" "${OUT_PREFIX}.txt"
  cp "$RESULTS_CSV" "${OUT_PREFIX}.csv"
  echo "Saved: ${OUT_PREFIX}.txt and ${OUT_PREFIX}.csv" >&2
fi


