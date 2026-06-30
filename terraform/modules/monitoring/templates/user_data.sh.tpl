#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /opt/monitoring/prometheus
cd /opt/monitoring

cat > prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 30s

scrape_configs:
  - job_name: 'yace'
    static_configs:
      - targets: ['yace:5000']
EOF

cat > yace-config.yml <<EOF
apiVersion: v1alpha1
discovery:
  jobs:
    - type: AWS/ECS
      regions:
        - ${aws_region}
      searchTags:
        - key: ${discovery_tag_key}
          value: ${discovery_tag_value}
      metrics:
        - name: CPUUtilization
          statistics: [Average]
          period: 300
          length: 300
EOF

cat > docker-compose.yml <<EOF
version: "3.8"
services:
  yace:
    image: prometheuscommunity/yet-another-cloudwatch-exporter:latest
    restart: unless-stopped
    environment:
      - AWS_REGION=${aws_region}
    volumes:
      - ./yace-config.yml:/tmp/config.yml
    command: ["--config.file=/tmp/config.yml"]

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus:/etc/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=changeme
EOF

docker-compose up -d