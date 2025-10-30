# Concurrent Logger

Concurrent Logger implementations in multiple languages, bench marked against standards
like grep and awk.

## Quick Usage

```
python scripts/generate_logs.py \
--output testdata/log_1000M.log \ 
--size 1000M \
  --pattern "ERROR|WARN" \
  --pattern-ratio 0.3  # 30% matching lines

# followed by

./scripts/benchmark.sh \
  --input testdata/log_1000M.log \
  --pattern 'ERROR'
```
## BENCHMARK RESULTS

### Multi threaded python
```
Benchmarking on: testdata/log_1000M.log
Size: 1048576083 bytes | Lines: 11894546
Pattern: ERROR
Runs: 5 (warmup: 1)
Tool         Runs  real_s(avg)  MB/s(avg)  lines/s(avg)
-------------------------------------------------------
python          5        0.128    8179.87      92788520
grep            5        3.776     277.73       3150412
awk             5        0.007  155913.60    1768608000
```

### Single threaded python 
```
Benchmarking on: testdata/log_1000M.log
Size: 1048576083 bytes | Lines: 11894546
Pattern: ERROR
Runs: 5 (warmup: 1)
Tool         Runs  real_s(avg)  MB/s(avg)  lines/s(avg)
-------------------------------------------------------
python          5        0.135    7763.77      88068520
grep            5        3.716     282.16       3200662
awk             5        0.007  159906.80    1813908000
```


## Generate log data

Use the generator script to create synthetic logs for testing and benchmarks.

```bash
# By number of lines
python scripts/generate_logs.py \
  --output dummy_data.log \
  --lines 1000000 \
  --pattern "ERROR|WARN" \
  --pattern-ratio 0.1

# Or by target size (overrides --lines)
python scripts/generate_logs.py \
  --output testdata/logs_100M.txt \
  --size 100M \
  --pattern "ERROR" \
  --pattern-ratio 0.05
```

Environment variables from `.env` (e.g., `LOG_FILE`, `NUM_LINES`) are supported
and can be overridden by CLI flags.