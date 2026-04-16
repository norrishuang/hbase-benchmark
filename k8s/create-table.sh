#!/bin/bash
# 创建 HBase 表脚本（在 EMR Master 执行，或通过 hbase shell）
# 40 个预分裂 Region，对应 4 个 RegionServer，每个 RS 10 个 Region

cat << 'HBASE_SCRIPT'
n_splits = 40
create 'usertable_r8g', \
  {NAME => 'cf', COMPRESSION => 'Snappy'}, \
  {SPLITS => (1..n_splits).map {|i| "user#{1000+i*(9999-1000)/n_splits}"}}
list_regions 'usertable_r8g'
HBASE_SCRIPT
