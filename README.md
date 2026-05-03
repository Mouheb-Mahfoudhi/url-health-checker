# URL Health Checker

A cloud-native URL health check service built with FastAPI, containerized with Docker, deployed to AWS ECS via Terraform, and hardened with a multi-layer DevSecOps pipeline on GitHub Actions.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure](#2-repository-structure)
3. [Application](#3-application)
4. [Container Dockerfile](#4-container-dockerfile)
5. [Infrastructure as Code (Terraform)](#5-infrastructure-as-code-terraform)
6. [CI/CD Pipeline](#6-cicd-pipeline)
   - 6.1 [CI : Continuous Integration & Security Scanning](#61-ci--continuous-integration--security-scanning)
   - 6.2 [Infra : Infrastructure Provisioning](#62-infra--infrastructure-provisioning)
   - 6.3 [Deploy : Image Build & ECS Deployment](#63-deploy--image-build--ecs-deployment)
7. [Security Controls Summary](#7-security-controls-summary)
8. [Required GitHub Secrets](#8-required-github-secrets)
9. [End-to-End Flow](#9-end-to-end-flow)
10. [Demo](#10-demo)

---

## 1. Project Overview

**url-health-checker** is a showcase project demonstrating a production-grade DevOps workflow on AWS. The application is a FastAPI service that checks the reachability and HTTP status of URLs. The focus is on the surrounding DevOps and DevSecOps infrastructure:

- **Automated security gates** baked into every CI run (SAST, SCA, container scanning, code analysis)
- **Infrastructure as Code**: all AWS resources provisioned via Terraform
- **OIDC-based, keyless AWS authentication**: no long-lived IAM credentials stored as secrets
- **Separate workflow responsibilities**: CI, infrastructure provisioning, and application deployment are three independent, chained pipelines

---

## 2. Repository Structure

```
url-health-checker/
├── .github/
│   └── workflows/
│       ├── ci.yml          # Linting, testing, and all security scans
│       ├── infra.yml       # Terraform infrastructure provisioning
│       └── deploy.yml      # Docker image build/push + ECS deployment
├── app/                    # FastAPI application source
├── static/                 # Static assets served by the app
├── templates/              # Jinja2 HTML templates
├── tests/                  # pytest test suite
├── terraform/              # All AWS infrastructure definitions (HCL)
├── Dockerfile              # Multi-stage container build
├── requirements.txt        # Python dependencies
└── pytest.ini              # pytest configuration
```

---

## 3. Application

The service is built with **FastAPI** (Python 3.11) and served by **Uvicorn** on port `8000`. It exposes a `/ping` health check endpoint used by both the Docker `HEALTHCHECK` directive and the AWS ECS target group health check.

---

## 4. Container (Dockerfile)

**Key security and operational decisions:**

The image is based on `python:3.11-slim-bookworm` (minimal Debian Bookworm, reduced attack surface). Build tooling (`pip`, `setuptools`, `wheel`) is upgraded to patched versions before installing app dependencies. The `apt` cache and pip cache are both discarded to keep layers lean.

---

## 5. Infrastructure as Code (Terraform)

All AWS resources are defined in the `terraform/` directory using HCL. Terraform state is managed remotely (S3 backend with the new use_lockfile = true enabled).

### AWS Resources Provisioned

| Resource | Purpose |
|---|---|
| **ECR Repository** | Stores Docker images tagged by commit SHA |
| **ECS Cluster** | Fargate compute cluster -> no EC2 instances to manage |
| **ECS Task Definition** | Container spec: image URI, CPU/memory, port mappings, environment variables |
| **ECS Service** | Maintains desired task count, handles rolling deployments |
| **VPC + Subnets** | Isolated network; public subnets for the ALB, private subnets for ECS tasks |
| **Application Load Balancer** | Internet-facing entry point; forwards to ECS service target group |
| **Security Groups** | Restrict inbound traffic; ALB accepts port 80, ECS tasks accept only from ALB |
| **IAM Roles** | ECS task execution role (pull from ECR), OIDC role for GitHub Actions |

### Terraform Outputs

The `ecr_repository_url` output is consumed directly by the Deploy workflow to dynamically resolve the ECR endpoint. No hardcoded AWS account IDs anywhere in the pipeline.

### Infrastructure Workflow Integration

The Terraform code is split across two pipeline interactions:

- **`infra.yml`** runs `terraform init → plan → apply` for the full infrastructure layer (VPC, ECS cluster, ECR, ALB, IAM)
- **`deploy.yml`** runs a **targeted** `terraform apply` scoped to only `aws_ecs_task_definition.app` and `aws_ecs_service.app`, injecting the new image tag. This is the hot-path deployment, leaving stable infrastructure untouched

---

## 6. CI/CD Pipeline

The pipeline is composed of **three independent, chained workflows**. This separation is intentional: infrastructure changes, security gates, and application deployments have different triggers, durations, and failure domains.

```
┌───────────┐     on: push/PR      ┌─────────────────────────────────────┐
│           │ ──────────────────▶  │  CI (ci.yml)                        │
│ Developer │                      │  lint · tests · bandit · pip-audit  │
│           │                      └──────────────────┬──────────────────┘
└───────────┘                                         │ on: workflow_run (completed)
                                                      ▼                                                                                                                    
                                   ┌─────────────────────────────────────┐
                                   │  Infra (infra.yml)                  │
                                   │  terraform init · plan · apply      │
                                   └─────────────────┬───────────────────┘
                                                     │ on: workflow_run (completed)
                                                     ▼
                                   ┌─────────────────────────────────────┐
                                   │  Deploy (deploy.yml)                │
                                   │  docker build · ECR push · tf apply │
                                   └─────────────────────────────────────┘
```

---

### 6.1 CI : Continuous Integration & Security Scanning

**File:** `.github/workflows/ci.yml`  
**Triggers:** `pull_request`, `workflow_dispatch`  
**Permissions:** `contents: read`, `security-events: write`

The CI workflow runs **four parallel jobs**, each scoped to a specific concern. All four must pass before a pull request is mergeable.

---

#### Job 1 : `tests` (Quality Gate)

```yaml
- name: Lint (ruff)
  run: ruff check app tests

- name: Run tests with coverage
  run: pytest tests/ -v --cov=app --cov-report=term-missing --cov-report=xml

- name: Upload coverage report
  uses: actions/upload-artifact@v4
```

| Step | Tool | Purpose |
|---|---|---|
| Lint | **ruff** | Fast Python linter enforcing code style and catching obvious errors before they reach review |
| Test | **pytest** | Runs the full test suite with verbose output |
| Coverage | **pytest-cov** | Generates an XML coverage report and a terminal summary showing uncovered lines |
| Artifact | **upload-artifact** | Persists `coverage.xml` for downstream inspection or integration with coverage tracking services |

---

#### Job 2 : `security-python` (SAST + SCA)

```yaml
- name: Bandit (SAST)
  run: bandit -r app -x tests -ll

- name: pip-audit (dependencies)
  run: pip-audit -r requirements.txt
```

| Step | Tool | Type | What it catches |
|---|---|---|---|
| Bandit | **bandit** | SAST | Statically scans Python source for known insecure patterns: hardcoded passwords, use of weak cryptographic primitives, subprocess injection, insecure SSL/TLS usage, etc. The `-ll` flag reports only medium and above severity findings. |
| pip-audit | **pip-audit** | SCA | Checks every package in `requirements.txt` against the Python Vulnerability Database (PyPA advisory DB). Fails the build if any dependency has a known CVE. |

> **Real example from this repo's history:** A CodeQL scan flagged use of an insecure TLS version in the application code. The fix was committed as a dedicated PR (`alert-autofix-1`) and the CI pipeline validated the remediation before it was merged to main. The Bandit job similarly went through a `sast fail → Sast success` iteration cycle visible in the Actions history.

---

#### Job 3 : `security-container` (Container Vulnerability Scanning)

```yaml
- name: Build container image
  run: docker build -t health-checker:ci .

- name: Trivy (container scan)
  uses: aquasecurity/trivy-action@v0.4.0
  with:
    image-ref: health-checker:ci
    format: table
    exit-code: "1"
    ignore-unfixed: true
    vuln-type: os,library
    severity: CRITICAL,HIGH
```

**Trivy** scans both the OS packages (Debian Bookworm) and the Python libraries installed in the image. Key configuration decisions:

| Option | Value | Rationale |
|---|---|---|
| `exit-code` | `"1"` | **Hard failure** a container with unpatched CRITICAL/HIGH CVEs cannot be merged or deployed |
| `ignore-unfixed` | `true` | Suppresses noise from vulnerabilities that have no available fix yet, keeping the signal actionable |
| `vuln-type` | `os,library` | Scans both the base OS layer and the Python package layer |
| `severity` | `CRITICAL,HIGH` | Balances signal-to-noise; MEDIUM/LOW findings are surfaced in the report but don't block the pipeline |

The image is built fresh on every CI run. This means any dependency or base image update is scanned before it ever reaches ECR.

---

#### Job 4 : `codeql` (Semantic Code Analysis)

```yaml
- name: Initialize CodeQL
  uses: github/codeql-action/init@v3
  with:
    languages: python

- name: Perform CodeQL Analysis
  uses: github/codeql-action/analyze@v3
  with:
    category: "/language:python"
```

**CodeQL** performs deep semantic analysis of the Python codebase. Going beyond pattern matching to understand data flow and taint tracking. It can detect vulnerabilities that simpler tools miss, such as SQL injection through multi-step data transformations, path traversal, or unsafe deserialization.

Results are uploaded to **GitHub Security** (via the `security-events: write` permission) and appear in the repository's Security tab as code scanning alerts. GitHub's auto-fix feature was used in this project to generate and merge a fix PR directly from a CodeQL alert.

---

### 6.2 Infra : Infrastructure Provisioning

**File:** `.github/workflows/infra.yml`  
**Triggers:** push to `main`, `workflow_dispatch`

This workflow is responsible for the stable infrastructure layer. It runs `terraform init`, `terraform plan`, and `terraform apply` against the full Terraform configuration. Because infrastructure changes are relatively infrequent compared to application code changes, separating this into its own workflow prevents every code commit from running a full Terraform apply unnecessarily.

AWS authentication uses **OIDC (`id-token: write`)** GitHub's OIDC provider is configured as a trusted identity provider in AWS IAM. This means no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` are stored as GitHub secrets; the workflow receives a short-lived, scoped credential at runtime via `aws-actions/configure-aws-credentials`.

---

### 6.3 Deploy : Image Build & ECS Deployment

**File:** `.github/workflows/deploy.yml`  
**Triggers:** `workflow_run` (when Infra completes successfully on `main`), `workflow_dispatch`  
**Permissions:** `contents: read`, `id-token: write`

```yaml
on:
  workflow_run:
    workflows: [Infra]
    types: [completed]

jobs:
  deploy:
    if: ${{ github.event.workflow_run.conclusion == 'success' &&
            github.event.workflow_run.head_branch == 'main' }}
```

The deployment only proceeds if the Infra workflow succeeded **and** the branch is `main`, preventing accidental deploys from feature branches.

#### Deployment Steps

```
1. Checkout @ the exact commit SHA that triggered Infra
2. OIDC auth → assume AWS IAM role (no stored credentials)
3. terraform init + validate
4. Read ECR repo URL from terraform output
5. docker login to ECR
6. docker build + push (tagged with commit SHA)
7. terraform apply -target=aws_ecs_task_definition.app
                   -target=aws_ecs_service.app
                   -var="image_tag=<commit_sha>"
```

**Why targeted Terraform apply for deploy?**  
Running `terraform apply` on the full configuration on every deployment risks accidentally touching stable resources (VPC, security groups, ALB) due to configuration drift or provider updates. The targeted apply scopes the change to exactly the two resources that need to change: the task definition (new image) and the service (trigger rolling update). Everything else is left untouched.

**Image tagging with commit SHA:**  
Images are tagged with `${{ github.event.workflow_run.head_sha }}`, the exact Git commit that produced the image. This gives full traceability: any running ECS task can be traced back to a specific line of source code.

---

## 7. Security Controls Summary

| Layer | Control | Tool | Enforcement |
|---|---|---|---|
| Source code | Linting | ruff | CI : blocks merge |
| Source code | SAST | Bandit | CI : blocks merge |
| Source code | Semantic analysis | CodeQL | CI : blocks merge + Security tab alerts |
| Dependencies | SCA | pip-audit | CI : blocks merge |
| Container | CVE scanning | Trivy | CI : blocks merge (CRITICAL/HIGH) |
| AWS auth | Keyless OIDC | GitHub OIDC + IAM | Infra + Deploy : no static credentials |
| Permissions | Least-privilege | GitHub workflow `permissions:` | All workflows declare minimal scopes |
| Image integrity | Immutable tags | Commit SHA tagging | Deploy : no `latest` tag usage |
| Infrastructure | Drift prevention | Targeted tf apply | Deploy : stable infra untouched on deploy |

---

## 8. Required GitHub Secrets

| Secret | Used by | Description |
|---|---|---|
| `AWS_ROLE_ARN` | `deploy.yml`, `infra.yml` | ARN of the IAM role trusted by the GitHub OIDC provider |

No other secrets are required. ECR credentials are obtained dynamically via `aws ecr get-login-password` after assuming the OIDC role.

---

## 9. End-to-End Flow

```
Developer opens PR
  └──▶ CI runs in parallel:
        ├── tests (ruff lint + pytest + coverage)
        ├── security-python (Bandit SAST + pip-audit SCA)
        ├── security-container (docker build + Trivy scan)
        └── codeql (semantic Python analysis)

All CI jobs pass → PR approved → merged to main
  └──▶ Infra workflow triggers:
        └── terraform init → plan → apply (full infra)
              └── Infra succeeds on main
                    └──▶ Deploy workflow triggers:
                          ├── OIDC → assume AWS role
                          ├── Read ECR URL from terraform output
                          ├── docker build + push (tagged: <commit-sha>)
                          └── terraform apply (targeted: task def + service)
                                └── ECS performs rolling update
                                      └── New tasks start, health check (/ping) passes
                                            └── Old tasks drained and stopped ✓
```
## 10. Demo
Note : The application is also served over HTTPS via a manually configured SSL/TLS pipeline. A public certificate was provisioned through AWS Certificate Manager (ACM) using DNS validation, with the validation CNAME record added to Cloudflare DNS. The domain urlhealthchecker.tech is managed through Cloudflare, which handles DNS resolution via CNAME flattening on the apex domain. The ACM certificate (covering urlhealthchecker.tech and *.urlhealthchecker.tech) is attached to the ALB's HTTPS listener on port 443, and the HTTP listener on port 80 is configured to permanently redirect all traffic to HTTPS.
<br>
[url-health-checker-demo](https://urlhealthchecker.tech)
