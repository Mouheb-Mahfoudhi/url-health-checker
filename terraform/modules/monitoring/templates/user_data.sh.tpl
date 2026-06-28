#!/bin/bash
set -euo pipefail

dnf update -y
# If this fails on a future AL2023 release, check AWS's current Docker
# install docs - package names occasionally move between AL2023 versions.
dnf install -y docker
systemctl enable docker
systemctl start docker

curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /opt/monitoring/yace
mkdir -p /opt/monitoring/prometheus
mkdir -p /opt/monitoring/grafana/provisioning/datasources
cd /opt/monitoring

# --- docker-compose.yml ---------------------------------------------------
cat > docker-compose.yml <<'COMPOSE'
version: "3.8"
services:
  yace:
    # Check ghcr.io/prometheus-community/yet-another-cloudwatch-exporter for
    # the current latest tag before relying on this version long-term.
    image: prometheuscommunity/yet-another-cloudwatch-exporter:v0.61.0
    container_name: yace
    command: ["--config.file=/config/yace-config.yml"]
    volumes:
      - ./yace/yace-config.yml:/config/yace-config.yml:ro
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

volumes:
  prometheus-data:
  grafana-data:
COMPOSE

# --- YACE config -----------------------------------------------------------
# Tag-based discovery: YACE calls the Resource Groups Tagging API to find
# anything tagged discovery_tag_key=discovery_tag_value, then pulls the
# listed CloudWatch metrics for whatever it finds. No ARNs hardcoded here -
# if you ever add a second ECS service with the same Project tag, YACE picks
# it up automatically on its next discovery cycle.
#
# Verify this schema against YACE's current README - the discovery config
# format has changed between major versions before.
cat > yace/yace-config.yml <<'YACECFG'
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

# --- Prometheus --------------------------------------------------------------
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

# Starter alert rules - the metric names below match YACE's typical naming
# convention but ARE NOT GUARANTEED for your version. After first boot, open
# http://localhost:9090/graph (via the SSM port-forward below) and confirm
# the real metric names before trusting these to fire correctly.
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

# --- Grafana datasources -----------------------------------------------------
# Both datasources use the instance's IAM role - no API keys stored anywhere.
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

cd /opt/monitoring
docker-compose up -d
