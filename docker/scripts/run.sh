#!/bin/bash
set -e

THREADS=${THREADS:-100}
TABLE=${TABLE:-usertable_r8g}
POD_INDEX=${POD_INDEX:-0}
ROWS_PER_POD=${ROWS_PER_POD:-2000000000}

# 每个 Pod 用不同的 key 前缀，避免 key 冲突
# YCSB key 格式: user<zero-padded-number>，加 Pod 前缀区分
# 通过 keyprefix 参数设置不同前缀
KEY_PREFIX="pod${POD_INDEX}_user"

echo "================================================"
echo "YCSB HBase Write Benchmark - 10TB"
echo "================================================"
echo "Pod Index     : ${POD_INDEX}"
echo "Table         : ${TABLE}"
echo "Threads       : ${THREADS}"
echo "Rows per Pod  : ${ROWS_PER_POD}"
echo "Key Prefix    : ${KEY_PREFIX}"
echo "Start Time    : $(date)"
echo "================================================"

cd /opt/ycsb

./bin/ycsb load hbase20 \
  -P workloads/workload_10tb_write \
  -p table=${TABLE} \
  -p columnfamily=cf \
  -p recordcount=${ROWS_PER_POD} \
  -p operationcount=${ROWS_PER_POD} \
  -p insertcount=${ROWS_PER_POD} \
  -p fieldcount=1 \
  -p fieldlength=1024 \
  -p insertproportion=1 \
  -p keyprefix=${KEY_PREFIX} \
  -p hbase.config=/opt/ycsb/conf/hbase-site.xml \
  -threads ${THREADS} \
  -s 2>&1

echo "================================================"
echo "End Time: $(date)"
echo "Pod ${POD_INDEX} DONE"
echo "================================================"
