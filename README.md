# HBase Write Benchmark on EMR + EKS

使用 YCSB 对 Amazon EMR HBase（on S3）进行大规模写入压测，验证不同集群规格、WAL 配置下的写入性能。

测试结果保存在 [results/](results/) 目录。

---

## 测试场景

| 场景 | 说明 |
|---|---|
| 单节点写入基准 | 1 Pod × 100 线程，验证单客户端极限 |
| 多 Pod 并行写入 | 3~20 Pod × 100 线程，模拟高并发写入 |
| EMR WAL vs HDFS WAL | 对比两种 WAL 模式下的吞吐和稳定性 |
| RS 扩容验证 | 4 RS → 8 RS，验证写入性能是否线性扩展 |
| WAL 并行化优化 | `numgroups=1 → 4`，验证多 WAL 分组的提升效果 |

---

## 工具

### 压测工具：YCSB

Yahoo! Cloud Serving Benchmark (YCSB) 0.17.0，使用 `hbase20` binding。

```bash
wget https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-hbase20-binding-0.17.0.tar.gz
tar -zxvf ycsb-hbase20-binding-0.17.0.tar.gz
cd ycsb-hbase20-binding-0.17.0
mkdir conf
cp /etc/hbase/conf/hbase-site.xml ./conf
```

Workload 配置（100% 写入，1KB/行）：

```properties
workload=site.ycsb.workloads.CoreWorkload
readproportion=0
updateproportion=0
scanproportion=0
insertproportion=1
fieldcount=1
fieldlength=1024
requestdistribution=uniform
```

### 运行平台：EKS Kubernetes Job

YCSB 客户端容器化运行于 Amazon EKS，通过 Kubernetes Job 管理多 Pod 并发压测：

- **EKS 集群**：emr-on-eks-cluster
- **NodeGroup**：mng-mytest-m7i-xl（m7i.xlarge）
- **Job 配置**：见 [k8s/](k8s/) 目录

多 Pod 按 key range 分片，每 Pod 分配独立的 `insertstart` 区间，避免 key 冲突：

| Pod | insertstart | recordcount |
|---|---|---|
| pod0 | 0 | 1,073,741,824 |
| pod1 | 1,073,741,824 | 2,147,483,648 |
| pod2 | 2,147,483,648 | 3,221,225,472 |
| pod3 | 3,221,225,472 | 4,294,967,296 |

---

## 基础架构

- **HBase 集群**：Amazon EMR（HBase on S3 / EMRFS）
- **数据存储**：S3（`s3://emr-hive-us-east-1-812046859005/hbase`）
- **WAL**：支持 EMR WAL（写 S3）和 HDFS WAL（写本地 HDFS）两种模式

---

## HBase 表结构

预分裂 Region 数 = `10 × RegionServer 数`：

```ruby
# 4 RS → 40 Region
n_splits = 40
create 'usertable_r8g',
  {NAME => 'cf', COMPRESSION => 'SNAPPY', BLOOMFILTER => 'NONE'},
  {SPLITS => (1..n_splits).map {|i| "user#{1000+i*(9999-1000)/n_splits}"}}

# 8 RS → 77 Region（含 1 个默认 Region）
n_splits = 76
create 'usertable_8rs_uniform',
  {NAME => 'cf', COMPRESSION => 'SNAPPY', BLOOMFILTER => 'NONE'},
  {SPLITS => (1..n_splits).map {|i| "user#{1000+i*(9999-1000)/n_splits}"}}
```

---

## HBase 关键配置参数

通过 EMR Reconfiguration API（`modify_instance_groups`，`ReconfigurationType: OVERWRITE`）下发，**不要手动修改配置文件**。

### hbase（Classification）

| 参数 | 推荐值 | 说明 |
|---|---|---|
| `hbase.emr.storageMode` | `s3` | 数据写 S3 |
| `hbase.emr.wal.enabled` | `true` / 不配置 | 开启 EMR WAL（写 S3）；不配置则使用默认 HDFS WAL。⚠️ 只能在集群创建时设定 |

### hbase-site（Classification）

| 参数 | 推荐值 | 默认值 | 说明 |
|---|---|---|---|
| `hbase.regionserver.handler.count` | `200` | 30 | RPC 处理线程数 |
| `hbase.ipc.server.callqueue.write.ratio` | `0.6` | 0.5 | 写入队列占比 |
| `hbase.regionserver.global.memstore.size` | `0.6` | 0.4 | MemStore 占 RS 堆内存比例 |
| `hfile.block.cache.size` | `0.1` | 0.4 | BlockCache 占比（纯写场景降低）⚠️ memstore + blockcache ≤ 0.8 |
| `hbase.hregion.memstore.flush.size` | `536870912` | 268435456 | 单 Region MemStore flush 阈值（512MB） |
| `hbase.hstore.blockingStoreFiles` | `200` | 20 | HFile 数超过此值才阻塞写入 |
| `hbase.hstore.compactionThreshold` | `10` | 8 | 触发 Minor Compaction 的 HFile 数量 |
| `hbase.regionserver.maxlogs` | `200` | 32 | RS 最大 WAL 文件数 |
| `hbase.client.write.buffer` | `16777216` | 2097152 | 客户端写缓冲（16MB） |
| `hbase.wal.regiongrouping.numgroups` | `4` | 1 | 并行 WAL 分组数（EMR WAL 模式下有效）|
| `hbase.hregion.majorcompaction` | `0` | 604800000 | 关闭 Major Compaction（压测期间避免 I/O 干扰）|

> ⚠️ `hbase.emr.wal.enabled` 不能在运行中集群上修改。
> ⚠️ 开启 EMR WAL 后不能配置 `hbase.wal.provider`，否则 Reconfiguration 报错。

### 应用配置示例

```python
import boto3

client = boto3.client('emr', region_name='us-east-1')

configurations = [
    {
        "Classification": "hbase",
        "Properties": {
            "hbase.emr.storageMode": "s3",
        }
    },
    {
        "Classification": "hbase-site",
        "Properties": {
            "hbase.regionserver.handler.count": "200",
            "hbase.ipc.server.callqueue.write.ratio": "0.6",
            "hbase.regionserver.global.memstore.size": "0.6",
            "hfile.block.cache.size": "0.1",
            "hbase.hregion.memstore.flush.size": "536870912",
            "hbase.hstore.blockingStoreFiles": "200",
            "hbase.hstore.compactionThreshold": "10",
            "hbase.regionserver.maxlogs": "200",
            "hbase.client.write.buffer": "16777216",
            "hbase.wal.regiongrouping.numgroups": "4",
            "hbase.hregion.majorcompaction": "0",
        }
    }
]

client.modify_instance_groups(
    ClusterId='<cluster-id>',
    InstanceGroups=[
        {
            "InstanceGroupId": "<core-ig-id>",
            "ReconfigurationType": "OVERWRITE",
            "Configurations": configurations
        }
    ]
)
```

---

## 注意事项

1. **memstore + block cache 之和不能超过 0.8**，否则 RegionServer 启动失败。
2. **EMR WAL 只能在集群创建时开启**，运行中不可修改 `hbase.emr.wal.enabled`。
3. **开启 EMR WAL 后不能配置 `hbase.wal.provider`**，使用 `numgroups` 代替实现并行 WAL。
4. **不要手动修改 `/etc/hbase/conf/hbase-site.xml`**，EMR 管理的文件会被覆盖。
5. **提交 Job 前确认所有 EKS 节点 Ready**，NotReady 节点会导致 Pod 调度后立即失败。
