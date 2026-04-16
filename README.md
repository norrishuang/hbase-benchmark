# HBase Write Benchmark on EMR + EKS

使用 YCSB 对 Amazon EMR HBase (on S3) 进行大规模写入压测。

---

## 架构

- **HBase 集群**：Amazon EMR（HBase on S3 / EMRFS）
- **压测客户端**：Amazon EKS Kubernetes Job（YCSB hbase20 binding）
- **存储**：S3（`s3://emr-hive-us-east-1-812046859005/hbase`）

---

## 集群配置

### EMR 集群

| 参数 | 值 |
|---|---|
| 集群 ID | j-AASHQTBAAITI |
| EMR 版本 | emr-7.12.0 |
| Master | m8g.xlarge × 1 |
| Core | r8g.4xlarge × 4 |
| HBase 存储模式 | S3 (EMRFS) |
| WAL | 启用 (`hbase.emr.wal.enabled=true`) |

### EKS 压测节点

| 参数 | 值 |
|---|---|
| 集群 | emr-on-eks-cluster |
| NodeGroup | mng-mytest-m7i-xl |
| 实例类型 | m7i.xlarge |
| 节点数 | 5 |

---

## HBase 配置（EMR Reconfiguration）

通过 `modify_instance_groups` API（`ReconfigurationType: OVERWRITE`）下发，**不要手动修改配置文件**。

### hbase

| 参数 | 值 | 说明 |
|---|---|---|
| `hbase.emr.storageMode` | `s3` | 使用 S3 存储 |
| `hbase.emr.wal.enabled` | `true` | 启用 WAL |

### hbase-site

| 参数 | 值 | 默认值 | 说明 |
|---|---|---|---|
| `hbase.rootdir` | `s3://emr-hive-us-east-1-812046859005/hbase` | — | HBase 数据目录 |
| `emr.wal.workspace` | `defaultWALworkspace` | — | WAL 工作空间 |
| `hbase.hregion.majorcompaction` | `0` | 604800000 | **关闭** Major Compaction，压测期间避免 I/O 干扰 |
| `hbase.regionserver.global.memstore.size` | `0.6` | 0.4 | MemStore 占 RS 堆内存 60%，提升写入缓冲 |
| `hbase.hregion.memstore.flush.size` | `536870912` | 268435456 | MemStore flush 阈值 512MB（原 256MB），减少 flush 频率 |
| `hfile.block.cache.size` | `0.1` | 0.4 | BlockCache 降到 10%，纯写入不需要大缓存（memstore+blockcache ≤ 0.8）|
| `hbase.hstore.compactionThreshold` | `10` | 8 | 触发 Minor Compaction 的 StoreFile 数量阈值 |
| `hbase.hstore.blockingStoreFiles` | `200` | 20 | 超过此数量才阻塞写入，避免压测被限流 |
| `hbase.regionserver.maxlogs` | `200` | 32 | RS 最大 WAL 数量，防止 WAL 过多触发 flush |
| `hbase.regionserver.handler.count` | `150` | 30 | RPC 处理线程数（EMR 默认值） |
| `hbase.ipc.server.callqueue.write.ratio` | `0.6` | 0.5 | 写入队列占比 60%（EMR 默认值） |
| `hbase.client.write.buffer` | `16777216` | 2097152 | 客户端写缓冲 16MB |

> ⚠️ `hbase.regionserver.global.memstore.size` + `hfile.block.cache.size` 之和不能超过 **0.8**，否则 RegionServer 启动失败。

### 重新应用配置

```python
import boto3

client = boto3.client('emr', region_name='us-east-1')

configurations = [
    {"Classification": "hbase", "Properties": {
        "hbase.emr.storageMode": "s3",
        "hbase.emr.wal.enabled": "true"
    }},
    {"Classification": "hbase-site", "Properties": {
        "emr.wal.workspace": "defaultWALworkspace",
        "hbase.rootdir": "s3://emr-hive-us-east-1-812046859005/hbase",
        "hbase.client.write.buffer": "16777216",
        "hbase.hregion.majorcompaction": "0",
        "hbase.hregion.memstore.flush.size": "536870912",
        "hbase.hstore.blockingStoreFiles": "200",
        "hbase.hstore.compactionThreshold": "10",
        "hbase.ipc.server.callqueue.write.ratio": "0.6",
        "hbase.regionserver.global.memstore.size": "0.6",
        "hbase.regionserver.handler.count": "150",
        "hbase.regionserver.maxlogs": "200",
        "hfile.block.cache.size": "0.1",
    }}
]

client.modify_instance_groups(
    ClusterId='j-AASHQTBAAITI',
    InstanceGroups=[
        {"InstanceGroupId": "ig-2JF8O3PRD0LIC", "ReconfigurationType": "OVERWRITE", "Configurations": configurations},
        {"InstanceGroupId": "ig-2AVNZF4OW3PDQ", "ReconfigurationType": "OVERWRITE", "Configurations": configurations},
    ]
)
```

---

## HBase 表结构

```ruby
n_splits = 40
create 'usertable_r8g',
  {NAME => 'cf', COMPRESSION => 'SNAPPY', BLOOMFILTER => 'NONE'},
  {SPLITS => (1..n_splits).map {|i| "user#{1000+i*(9999-1000)/n_splits}"}}
```

| 参数 | 值 | 说明 |
|---|---|---|
| 表名 | `usertable_r8g` | — |
| Column Family | `cf` | — |
| 压缩 | SNAPPY | — |
| BLOOMFILTER | NONE | 纯写入压测，不需要 Bloom Filter |
| 预分裂 Region 数 | 40 | 对应 4 个 RegionServer，每个 RS 10 个 Region |

---

## 压测参数（YCSB）

| 参数 | 值 | 说明 |
|---|---|---|
| Pod 数量 | 10 | 并行写入 |
| Threads/Pod | 100 | 每 Pod 并发线程 |
| 每 Pod 行数 | 100,503,804 | 总计约 10 亿行 |
| fieldcount | 1 | 每行 1 个字段 |
| fieldlength | 1024 | 每字段 1KB |
| 总数据量 | ~10TB | — |

### 启动压测

```bash
# 1. 确认 RegionServer 全部在线
echo 'status\nexit' | hbase shell

# 2. 提交 Job
kubectl apply -f k8s/job-10tb.yaml

# 3. 查看进度
kubectl logs -l app=hbase-benchmark --prefix --tail=2 | grep "sec:"
```

---

## 踩坑记录

### 1. memstore + block cache 超过 0.8 导致 RS 启动失败

```
RuntimeException: Current heap configuration for MemStore and BlockCache exceeds the threshold...
hbase.regionserver.global.memstore.size=0.6, hfile.block.cache.size=0.4
```

**解决**：将 `hfile.block.cache.size` 降到 `0.1`，合计 0.7。

### 2. 不要手动修改 `/etc/hbase/conf/hbase-site.xml`

EMR 管理的配置文件，手动修改会被 EMR 覆盖，且 RegionServer 重启行为由 systemd 管理，直接 restart 可能导致循环重启。**应使用 `modify_instance_groups` API 提交 Reconfiguration**。

### 3. EMR Master → Core Node SSH

EMR hadoop 用户没有默认 SSH key，需要通过外部 pem key 中转（先 scp 到 master，再从 master 跳转）。**推荐用 EMR Reconfiguration API 替代直接 SSH 操作配置**。
