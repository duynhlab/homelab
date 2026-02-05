# 🚀 CI/CD Pipeline Documentation

This document outlines the **Trunk-Based Development** CI/CD pipeline implemented for all microservices (`auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`). The pipeline employs a **"Build Once, Analyze Everywhere"** strategy to optimize performance and eliminate redundant execution.

## 📊 Workflow Visualization

### 1. Orchestration Logic
This flowchart illustrates how jobs are connected and triggered based on events.

```mermaid
graph TD
    subgraph Trigger
        PR([Pull Request]) --> Common
        Push([Push to Main]) --> GoCheck
    end

    subgraph PRChecks ["PR Checks (ci-common)"]
        Common[PR Validation & Notify] --> GoCheck
    end

    subgraph Pipeline ["CI/CD Pipeline"]
        GoCheck[Go Check<br/>Test + Lint + Artifact] -->|Success| Sonar
        Sonar[SonarCloud<br/>Scan + Quality Gate] -->|Success| DockerGate{Branch?}
        
        DockerGate -- Main --> Docker[Docker Build & Push]
        DockerGate -- PR --> EndNode([End])
        
        Docker --> Notify
    end

    subgraph Notifications ["Notifications (status.yml)"]
        Notify[Final Status Report]
    end

    GoCheck -.->|Fail| Notify
    Sonar -.->|Fail| Notify
    Docker -.->|Fail| Notify
```

### 2. Execution Sequence
This diagram details the interaction between GitHub Actions, SonarCloud, and Slack.

```mermaid
sequenceDiagram
    autonumber
    participant Dev as 🧑‍💻 Developer
    participant GH as 🐙 GitHub Actions
    participant Common as 🛡️ Common/PR
    participant Test as 🧪 Go Check
    participant Sonar as 📡 SonarCloud
    participant Docker as 🐳 Docker
    participant Slack as 📣 Slack

    Dev->>GH: Open Pull Request
    GH->>Common: Trigger (ci-common)
    Common->>Common: Validate Branch Name
    Common-->>Slack: 💬 Notify "PR Opened"
    
    GH->>Test: Run Tests & Lint
    Test->>Test: go test -cover
    Test->>GH: 📦 Upload Artifact (coverage.out)
    
    GH->>Sonar: Trigger Analysis
    Sonar->>GH: 📥 Download Artifact
    Sonar->>Sonar: Run Scanner
    Sonar-->>Slack: 💬 Quality Gate Status
    
    alt is Main Branch
        GH->>Docker: Build & Push
        Docker->>Docker: Build Image
        Docker->>Docker: Push to Registry
    end
    
    GH->>Slack: 🏁 Final Pipeline Status (status.yml)
```

---

## 🔄 Detailed Process Flows

### 1️⃣ Flow: Pull Request (Validation)
**Trigger:** Developer opens or updates a Pull Request targeting `main`.
**Goal:** Verify code quality, security, and functionality **before** merging.

| Step | Job Name | Action & Responsibility |
|------|----------|-------------------------|
| **1** | `common` | **Gateway Check**: <br>• Validates branch naming (must match `feat/*`, `fix/*`, etc.).<br>• Notifies Slack that a PR has been opened/updated. |
| **2** | `go-check` | **Build & Test**: <br>• Runs `go test -race -cover`.<br>• Runs `golangci-lint`.<br>• **Uploads** the `coverage.out` file as an artifact for the next step. |
| **3** | `sonar` | **Quality Gate**: <br>• **Downloads** the `coverage.out` artifact.<br>• Runs SonarScanner to analyze code & coverage.<br>• Checks Quality Gate (Bugs, Vulnerabilities, Coverage %).<br>• **Blocks** the PR if Quality Gate fails. |
| **4** | `notify` | **Reporting**: <br>• Sends the final status (Success/Failure) to Slack. |

> 🚫 **Skipped:** `docker` job is NOT run on PRs to save resources and avoid polluting the registry with untagged images.

---

### 2️⃣ Flow: Push to Main (Delivery)
**Trigger:** PR is merged into `main` (or direct push).
**Goal:** Create a release candidate and publish the artifact.

| Step | Job Name | Action & Responsibility |
|------|----------|-------------------------|
| **1** | `go-check` | **Regression Check**: <br>• Re-runs tests and linting on the merged code to ensure stability.<br>• Uploads fresh coverage artifact. |
| **2** | `sonar` | **Analysis Update**: <br>• Updates the "Main Branch" dashboard on SonarCloud.<br>• Ensures the `main` branch stays "Green". |
| **3** | `docker` | **Deployment Artifact**: <br>• Builds the Docker image.<br>• Tags it (e.g., `latest` or sha).<br>• **Pushes** the image to GHCR (GitHub Container Registry). |
| **4** | `notify` | **Reporting**: <br>• Sends a deployment/build success notification to Slack. |