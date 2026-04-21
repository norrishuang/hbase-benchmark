#!/bin/bash
set -o pipefail

THREADS=${THREADS:-100}
TABLE=${TABLE:-usertable_r8g}
POD_INDEX=${POD_INDEX:-0}
ROWS_PER_POD=${ROWS_PER_POD:-100000000}
TOTAL_PODS=${TOTAL_PODS:-10}

# YCSB insertstart 分片：每个 Pod 写不同范围，key 不重叠
# uniform 分布下 recordcount 决定 key 的上限，设为本 Pod 分片终点
# 这样 uniform 只在 [INSERT_START, INSERT_START+ROWS_PER_POD) 范围内随机，实现真正隔离
INSERT_START=$((POD_INDEX * ROWS_PER_POD))
TOTAL_ROWS=$((INSERT_START + ROWS_PER_POD))

echo "================================================"
echo "YCSB HBase Write Benchmark"
echo "================================================"
echo "Pod Index     : ${POD_INDEX}"
echo "Table         : ${TABLE}"
echo "Threads       : ${THREADS}"
echo "Rows per Pod  : ${ROWS_PER_POD}"
echo "Insert Start  : ${INSERT_START}"
echo "Total Rows    : ${TOTAL_ROWS}"
echo "Start Time    : $(date)"
echo "================================================"

cd /opt/ycsb

./bin/ycsb load hbase20 \
  -P workloads/workload_10tb_write \
  -p table=${TABLE} \
  -p columnfamily=cf \
  -p recordcount=${TOTAL_ROWS} \
  -p insertstart=${INSERT_START} \
  -p operationcount=${ROWS_PER_POD} \
  -p insertcount=${ROWS_PER_POD} \
  -p fieldcount=1 \
  -p fieldlength=1024 \
  -p insertproportion=1 \
  -p zeropadding=20 \
  -p core_workload_insertion_retry_limit=100 \
  -p hbase.config=/opt/ycsb/conf/hbase-site.xml \
  -threads ${THREADS} \
  -s 2>&1 || echo "[WARN] YCSB exited with errors, continuing..."

echo "================================================"
echo "End Time: $(date)"
echo "Pod ${POD_INDEX} DONE"
echo "================================================"
