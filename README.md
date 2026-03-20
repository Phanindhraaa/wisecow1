# Wisecow – Containerised Kubernetes Deployment

> AccuKnox DevOps Trainee Practical Assessment — complete solution

---

## Repository Structure

```
wisecow-k8s/
├── Dockerfile                         # PS1 – containerises the wisecow app
├── wisecow.sh                         # Wisecow application (copy from upstream)
├── k8s/
│   ├── namespace.yaml                 # Dedicated namespace
│   ├── deployment.yaml                # 2-replica deployment with TLS volume mount
│   ├── service.yaml                   # LoadBalancer service (port 443)
│   ├── ingress.yaml                   # NGINX ingress with TLS termination
│   └── hpa.yaml                       # HorizontalPodAutoscaler (2–5 replicas)
├── .github/
│   └── workflows/
│       └── ci-cd.yaml                 # GitHub Actions – build, push & deploy
├── scripts/
│   ├── generate-tls-secret.sh         # Generates self-signed cert → k8s Secret
│   ├── system_health_monitor.sh       # PS2 – Linux system health monitor (Bash)
│   └── app_health_checker.py          # PS2 – HTTP app health checker (Python)
├── kubearmor/
│   └── wisecow-zero-trust-policy.yaml # PS3 – KubeArmor zero-trust policies
└── README.md
```

---

## Problem Statement 1 – Containerisation & Kubernetes Deployment

### Prerequisites

| Tool | Version |
|------|---------|
| Docker | ≥ 24 |
| kubectl | ≥ 1.28 |
| Kind / Minikube | any recent |
| (optional) cert-manager | for automated TLS |

### Quick Start

#### 1 – Clone & copy the app

```bash
git clone https://github.com/<YOUR_USERNAME>/wisecow-k8s.git
cd wisecow-k8s

# Copy wisecow.sh from the upstream repo
curl -sL https://raw.githubusercontent.com/nyrahul/wisecow/main/wisecow.sh -o wisecow.sh
chmod +x wisecow.sh
```

#### 2 – Build the Docker image locally

```bash
docker build -t wisecow:local .
docker run --rm -p 4499:4499 wisecow:local
# browse to http://localhost:4499
```

#### 3 – Create a local cluster (Kind)

```bash
kind create cluster --name wisecow
```

#### 4 – Generate TLS certificates & Kubernetes secret

```bash
chmod +x scripts/generate-tls-secret.sh
./scripts/generate-tls-secret.sh wisecow.example.com
```

#### 5 – Deploy to Kubernetes

```bash
# Replace the image placeholder first
sed -i 's|ghcr.io/<YOUR_GITHUB_USERNAME>|ghcr.io/YOUR_USERNAME|g' k8s/deployment.yaml

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml

kubectl rollout status deployment/wisecow -n wisecow
kubectl get pods,svc -n wisecow
```

### CI/CD Pipeline

The `.github/workflows/ci-cd.yaml` workflow:

| Trigger | Action |
|---------|--------|
| Push to `main` | Lint → Build & push multi-arch image to GHCR → Deploy to K8s |
| Pull Request | Lint → Build (no push) |
| Manual | Full pipeline via `workflow_dispatch` |

#### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `KUBECONFIG_B64` | Base64-encoded kubeconfig for target cluster |
| `TLS_CERT` | Base64-encoded TLS certificate (`tls.crt`) |
| `TLS_KEY` | Base64-encoded TLS private key (`tls.key`) |

Encode secrets like this:
```bash
base64 -w0 ~/.kube/config    # → KUBECONFIG_B64
base64 -w0 tls/tls.crt       # → TLS_CERT
base64 -w0 tls/tls.key       # → TLS_KEY
```

### TLS Implementation

* Self-signed certs: use `scripts/generate-tls-secret.sh` (dev / testing)
* Production: install [cert-manager](https://cert-manager.io/) and uncomment the `cert-manager.io/cluster-issuer` annotation in `k8s/ingress.yaml`

---

## Problem Statement 2 – Automation Scripts

### Script 1: System Health Monitor (Bash)

Monitors CPU, memory, disk space, and process count. Alerts when thresholds are exceeded.

```bash
chmod +x scripts/system_health_monitor.sh

# Run once
./scripts/system_health_monitor.sh --interval 0

# Run every 60 seconds, log to custom file
./scripts/system_health_monitor.sh \
    --interval 60 \
    --log /tmp/health.log \
    --cpu 80 --mem 80 --disk 80

# All options
./scripts/system_health_monitor.sh --help
```

**Sample output:**
```
[OK]     CPU usage is 12%
[OK]     Memory usage is 45% (3600MB / 8000MB)
[ALERT]  Disk / is 87% full (threshold: 80%)
[OK]     Running process count is 142
```

---

### Script 2: Application Health Checker (Python)

Checks HTTP(S) endpoints and reports UP / DOWN / DEGRADED.

```bash
# Check a single URL
python3 scripts/app_health_checker.py https://example.com

# Check multiple endpoints with a keyword check
python3 scripts/app_health_checker.py \
    --timeout 5 \
    --keyword "wisecow" \
    https://wisecow.example.com

# Continuous monitoring (every 30 s) + JSON report
python3 scripts/app_health_checker.py \
    --interval 30 \
    --output report.json \
    https://wisecow.example.com

# Load URLs from a file
python3 scripts/app_health_checker.py --file urls.txt
```

**Sample output:**
```
Health Check @ 2024-07-01 12:00:00
────────────────────────────────────────────────────────────
  [UP]      https://wisecow.example.com
           ↳ HTTP 200  •  142ms
  [DOWN]    https://unreachable.example.com
           ↳ No response  •  10003ms  ⚠  [Errno -2] Name or service not known

────────── Summary ──────────
  Total   : 2
  UP      : 1
  DEGRADED: 0
  DOWN    : 1
```

---

## Problem Statement 3 – KubeArmor Zero-Trust Policy

### Install KubeArmor

```bash
# Using karmor CLI
curl -sfL https://raw.githubusercontent.com/kubearmor/KubeArmor/main/getting-started/install.sh | bash

# Or via Helm
helm repo add kubearmor https://kubearmor.github.io/charts
helm install kubearmor kubearmor/kubearmor -n kubearmor --create-namespace
```

### Apply the Policy

```bash
kubectl apply -f kubearmor/wisecow-zero-trust-policy.yaml
```

### What the Policy Enforces

| Policy | Effect |
|--------|--------|
| `wisecow-restrict-processes` | Allow only `bash`, `fortune`, `cowsay`, `nc`, `openssl`; block everything else |
| `wisecow-restrict-file-access` | Read-only access to app, TLS, and lib directories; block writes to `/etc`, `/bin`, etc. |
| `wisecow-restrict-network` | Block raw sockets; allow only TCP |
| `wisecow-block-privilege-escalation` | Block `sudo`, `su`, `curl`, `wget`, `python`, `apt`, etc. |

### Monitor Violations

```bash
# Stream policy violation logs
karmor log --namespace wisecow

# Or check KubeArmor telemetry
kubectl logs -n kubearmor -l app=kubearmor -f
```

Capture a screenshot of the `karmor log` output showing blocked events and commit it to `kubearmor/policy-violation-screenshot.png`.

---

## License

Apache 2.0 — same as the upstream Wisecow project.
# Wisecow - AccuKnox DevOps Assessment
