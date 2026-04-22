# 2026-04-22 测试结果：4 RS HDFS WAL 模式 3 Pod 压测（第二轮）

## 测试目标

在 **4 RS + HDFS WAL** 配置下，使用 3 Pod 并发写入，测试基准写入性能，
与上午同配置集群（j-24K0KIL582W3C）及历史 EMR WAL 结果进行对比。

---

## 测试配置

| 项目 | 值 |
|---|---|
| 日期 | 2026-04-22 |
| EMR 集群 | j-2WLPDLYJVOLUA |
| Core Node 数量 | **4** |
| Core Node 实例类型 | 待确认（同系列） |
| 存储模式 | HBase on S3（EMRFS） |
| WAL 模式 | **HDFS WAL**（`hbase.emr.wal.enabled` 未开启，默认 HDFS） |
| hbase.rootdir | s3://emr-hive-us-east-1-812046859005/hbase |
| 压测工具 | YCSB 0.17.0（hbase20 binding），Docker on EKS（m7i.xlarge） |
| 并发配置 | **3 Pod × 100 线程** |
| Key 分布 | uniform |
| HBase 表 | `usertable_bench`，82 个预分裂 Region，Snappy 压缩 |
| Field | 1 列，1024 bytes/行 |
| 每 Pod 写入量 | 360,000,000 行 |
| 总写入量目标 | **1,080,000,000 行（10.8 亿行）** |

### HBase 配置

| 参数 | 值 | 说明 |
|---|---|---|
| `hbase.emr.storageMode` | `s3` | 数据写 S3 |
| `hbase.emr.wal.enabled` | **未配置** | HDFS WAL |
| `hbase.regionserver.global.memstore.size` | `0.6` | MemStore 占堆内存 60% |
| `hbase.hregion.memstore.flush.size` | `512MB` | 单 Region flush 阈值 |
| `hfile.block.cache.size` | `0.1` | BlockCache 占 10% |
| `hbase.hstore.blockingStoreFiles` | `200` | HFile 超 200 才 block |
| `hbase.hstore.compactionThreshold` | `10` | 10 个 HFile 触发 minor compaction |
| `hbase.hstore.flusher.count` | `4` | flush 线程数（运行中动态调整，原默认 2）|
| `hbase.hregion.memstore.block.multiplier` | `8` | blocking 触发倍数（运行中动态调整，原默认 4）|

> ⚠️ `hbase.hstore.flusher.count` 和 `hbase.hregion.memstore.block.multiplier` 在测试运行约 55 分钟后（UTC 09:32）通过 `update_config` 动态调整，调整后速率提升约 10~16%。

---

## 测试过程记录

| 时间（UTC） | 事件 |
|---|---|
| 08:41 | 集群 j-2WLPDLYJVOLUA 就绪，提交 3 Pod Job |
| 08:45 | 3 Pod 全部 Running，写入开始 |
| 09:00 | 平均速率约 34,178 ops/sec（含停顿） |
| 09:32 | 动态调整 `flusher.count=4`、`block.multiplier=8` |
| 09:37 | 调整生效，速率提升至 pod0: 54,752 / pod1: 41,554 / pod2: 47,958 |
| 进行中 | 预计明天凌晨 03:30（北京时间）完成 |

---

## 中期测试结果（截至 UTC 12:05，运行约 204 分钟）

### 各 Pod 进度

| Pod | 已写入行数 | 进度 | 平均 TPS |
|---|---|---|---|
| pod0 | 158,845,339 | 44.1% | **12,978 ops/sec** |
| pod1 | 121,525,250 | 33.8% | **9,929 ops/sec** |
| pod2 | 144,973,646 | 40.3% | **11,844 ops/sec** |
| **3 Pod 合计** | **425,344,235（4.25 亿行）** | **39.4%** | **34,750 ops/sec** |

### 吞吐数据

| 指标 | 数值 |
|---|---|
| **全程平均 Throughput（3 Pod 合计）** | **~34,750 ops/sec** |
| 数据写入速率（1KB/行） | **~33.9 MB/s** |
| 含 WAL+HFile 写放大（约 2x） | 实际 I/O 约 **~68 MB/s** |
| 调参后峰值 TPS（3 Pod 合计） | ~144,264 ops/sec |
| 调参后单 Pod 峰值 TPS | ~41,554~54,752 ops/sec |

### 写入模式特征

| 特征 | 描述 |
|---|---|
| flush 停顿持续时长 | **~20~30 秒/次**（调参后较之前有所改善） |
| flush 停顿占比 | 约 50~60% 的时间处于停顿/恢复状态 |
| 恢复后瞬时峰值 | 单 Pod ~40,000~60,000 ops/sec |
| INSERT-FAILED 特征 | flush 期间出现 99 条/次 ~19ms 延迟失败，flush 后立即清零 |

---

## 与历史测试对比

| 对比维度 | EMR WAL（4月16日，4RS） | **HDFS WAL 第一轮（4月22日上午，8RS）** | **HDFS WAL 第二轮（本轮，4RS）** |
|---|---|---|---|
| WAL 模式 | EMR WAL（写 S3） | HDFS WAL | **HDFS WAL** |
| RS 数量 | 4 | 8 | **4** |
| 压测 Pod 数 | 10 | 3 | **3** |
| 全程平均 TPS（合计） | ~67,800（10 Pod） | ~47,530（3 Pod） | **~34,750（3 Pod，含停顿）** |
| 单 Pod 平均 TPS | ~6,780 | ~15,844 | **~11,584** |
| 调参后峰值单 Pod TPS | — | — | **~41,554~54,752** |
| 停顿持续时长 | ~30~60 秒/次 | ~60~90 秒/次 | **~20~30 秒/次（调参后）** |
| 停顿占比 | ~30% | ~60~70% | **~50~60%** |

---

## 动态调参效果

在测试运行 55 分钟后动态调整了两个参数：

| 参数 | 调整前 | 调整后 | 效果 |
|---|---|---|---|
| `hbase.hstore.flusher.count` | 2 | **4** | flush 更快，停顿时长缩短 |
| `hbase.hregion.memstore.block.multiplier` | 4 | **8** | blocking 触发门槛翻倍，停顿频率降低 |

**调参前后 TPS 对比：**

| Pod | 调参前 TPS | 调参后 TPS | 提升幅度 |
|---|---|---|---|
| pod0 | ~48,802 | ~54,752 | **↑ 12%** |
| pod1 | ~35,671 | ~41,554 | **↑ 16%** |
| pod2 | ~44,125 | ~47,958 | **↑ 9%** |
| 合计 | ~128,598 | **~144,264** | **↑ 12%** |

---

## 关键结论（中期）

1. **4 RS HDFS WAL 单 Pod 平均 TPS ~11,584 ops/sec**，低于 8 RS 版本（~15,844），符合预期（RS 减半）。

2. **动态调参有效**：`flusher.count=4` + `block.multiplier=8` 使峰值 TPS 提升 9~16%，停顿时长也有所缩短。

3. **HDFS WAL flush 停顿仍是主要瓶颈**：停顿期 TPS 归零，有效写入时间约 40~50%，全程平均 TPS 仅为峰值的 25~35%。

4. **下一步建议**：用同规格集群开启 EMR WAL 进行对比，验证 EMR WAL 在 4 RS 下的停顿改善效果；同时准备 Replication 双集群测试。

---

> 📌 测试仍在进行中，结果为截至 UTC 12:05 的中期数据，完整结果待测试完成后更新。
