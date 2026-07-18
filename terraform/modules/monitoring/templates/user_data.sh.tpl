#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /opt/monitoring/prometheus
mkdir -p /opt/monitoring/mongo
mkdir -p /opt/monitoring/opensearch
mkdir -p /opt/monitoring/grafana/provisioning/datasources
cd /opt/monitoring

# --- YACE config -------------------------------------------------------------
cat > yace-config.yml <<'YACECFG'
apiVersion: v1alpha1
discovery:
  jobs:
    - type: AWS/ECS
      regions: ["${aws_region}"]
      searchTags:
        - key: ${discovery_tag_key}
          value: ${discovery_tag_value}
      metrics:
        - name: CPUUtilization
          statistics: [Average, Maximum]
          period: 60
          length: 300
        - name: MemoryUtilization
          statistics: [Average, Maximum]
          period: 60
          length: 300
    - type: AWS/ApplicationELB
      regions: ["${aws_region}"]
      searchTags:
        - key: ${discovery_tag_key}
          value: ${discovery_tag_value}
      metrics:
        - name: RequestCount
          statistics: [Sum]
          period: 60
          length: 300
        - name: TargetResponseTime
          statistics: [Average]
          period: 60
          length: 300
        - name: HTTPCode_Target_5XX_Count
          statistics: [Sum]
          period: 60
          length: 300
YACECFG

# --- Prometheus config --------------------------------------------------------
cat > prometheus/prometheus.yml <<'PROMCFG'
global:
  scrape_interval: 30s

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "yace"
    static_configs:
      - targets: ["yace:5000"]
PROMCFG

cat > prometheus/alerts.yml <<'ALERTCFG'
groups:
  - name: ecs-alb
    rules:
      - alert: ECSHighCPU
        expr: aws_ecs_cpuutilization_average > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "ECS service CPU above 80% for 5m"
      - alert: ALB5xxErrors
        expr: increase(aws_applicationelb_httpcode_target_5_xx_count_sum[5m]) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "ALB target returned more than 5 5XXs in 5m"
ALERTCFG

# --- Grafana datasources -------------------------------------------------------
cat > grafana/provisioning/datasources/datasources.yml <<'DSCFG'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  - name: CloudWatch
    type: cloudwatch
    jsonData:
      authType: default
      defaultRegion: ${aws_region}
DSCFG

# --- docker-compose.yml ---------------------------------------------------------
cat > docker-compose.yml <<'COMPOSE'
version: "3.8"
services:
  yace:
    image: prometheuscommunity/yet-another-cloudwatch-exporter:v0.64.0
    container_name: yace
    command: ["--config.file=/config/yace-config.yml"]
    volumes:
      - ./yace-config.yml:/config/yace-config.yml:ro
    ports:
      - "5000:5000"
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v2.55.1
    container_name: prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    depends_on:
      - yace
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:11.3.0
    container_name: grafana
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped

  mongodb:
    image: mongo:6.0
    container_name: mongodb
    volumes:
      - mongo-data:/data/db
    restart: unless-stopped

  opensearch:
    image: opensearchproject/opensearch:2.15.0
    container_name: opensearch
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
      - "discovery.type=single-node"
      - "DISABLE_SECURITY_PLUGIN=true"
      - "bootstrap.memory_lock=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-data:/usr/share/opensearch/data
    restart: unless-stopped

  graylog:
    image: graylog/graylog:6.1
    container_name: graylog
    environment:
      - GRAYLOG_PASSWORD_SECRET=${graylog_password_secret}
      - GRAYLOG_ROOT_PASSWORD_SHA2=${graylog_root_password_sha2}
      - GRAYLOG_HTTP_EXTERNAL_URI=http://${alb_dns_name}:9000/
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://opensearch:9200
      - GRAYLOG_MONGODB_URI=mongodb://mongodb:27017/graylog
      - GRAYLOG_TRANSPORT_EMAIL_ENABLED=true
      - GRAYLOG_TRANSPORT_EMAIL_HOSTNAME=smtp.gmail.com
      - GRAYLOG_TRANSPORT_EMAIL_PORT=587
      - GRAYLOG_TRANSPORT_EMAIL_USE_AUTH=true
      - GRAYLOG_TRANSPORT_EMAIL_AUTH_USERNAME=${graylog_smtp_username}
      - GRAYLOG_TRANSPORT_EMAIL_AUTH_PASSWORD=${graylog_smtp_password}
      - GRAYLOG_TRANSPORT_EMAIL_USE_TLS=true
      - GRAYLOG_TRANSPORT_EMAIL_USE_SSL=false
      - GRAYLOG_TRANSPORT_EMAIL_FROM_EMAIL=${graylog_smtp_username}
    ports:
      - "9000:9000"
      - "12201:12201/udp"
    depends_on:
      - mongodb
      - opensearch
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
  mongo-data:
  opensearch-data:
COMPOSE

cd /opt/monitoring
docker-compose up -d
