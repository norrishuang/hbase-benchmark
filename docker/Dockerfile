FROM eclipse-temurin:11-jre-focal

ENV YCSB_VERSION=0.17.0
ENV YCSB_HOME=/opt/ycsb

# 安装必要工具
RUN apt-get update && apt-get install -y \
    wget curl python3 python3-pip python2 \
    && ln -sf /usr/bin/python2 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# 下载 YCSB HBase20 binding
RUN mkdir -p ${YCSB_HOME} && \
    wget -q https://github.com/brianfrankcooper/YCSB/releases/download/${YCSB_VERSION}/ycsb-hbase20-binding-${YCSB_VERSION}.tar.gz \
         -O /tmp/ycsb.tar.gz && \
    tar -zxf /tmp/ycsb.tar.gz -C ${YCSB_HOME} --strip-components=1 && \
    rm /tmp/ycsb.tar.gz

# 创建目录
RUN mkdir -p ${YCSB_HOME}/conf ${YCSB_HOME}/logs

WORKDIR ${YCSB_HOME}

# 复制 hbase-site.xml
COPY conf/hbase-site.xml ${YCSB_HOME}/conf/hbase-site.xml

# 复制 workload 文件
COPY workloads/ ${YCSB_HOME}/workloads/

# 复制启动脚本
COPY scripts/run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]
