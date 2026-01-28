# Security & SBOM Integration Research

## 1. Project Security Assessment

### Current Posture
| Component | Status | Tooling | Notes |
| :--- | :--- | :--- | :--- |
| **Dependency Management** | ✅ Good | `dependabot` | Configured for Go, Docker, and Actions. |
| **Image Signing** | ✅ Good | `cosign` | Images are signed in the build pipeline. |
| **Vulnerability Scanning** | ❌ Missing | None | No container or filesystem scanning in CI. |
| **SBOM** | ❌ Missing | None | No software bill of materials generated. |
| **Static Analysis (SAST)** | ❌ Missing | None | No security-focused code analysis (e.g., CodeQL, Gosec). |
| **K8s Policy** | ❌ Missing | None | No automated checks for best practices (e.g., non-root users). |

### Key Findings in Codebase
- **Missing `securityContext`**: A search of the `kubernetes/` directory revealed no defined `securityContext`. This means containers likely run as `root` by default, which is a major security risk.
- **No CI Security Gates**: Builds succeed even if the code contains known vulnerabilities.

---

## 2. Industry Standards (Big Tech & CNCF)

You asked about what "big companies" and the industry leaders are using. Here is the 2024/2025 landscape:

### Google & The Open Source Security Foundation (OpenSSF)
- **SLSA (Supply-chain Levels for Software Artifacts)**: A framework for ensuring artifact integrity. Achieving SLSA Level 2+ requires signed provenance (what we plan to do with Cosign) and SBOMs.
- **Tools**: Google heavily uses **Trivy** (via OSV detection), **Cosign** (part of Sigstore, which they co-founded), and **Go-Fuzz** for fuzzing.

### Microsoft
- **S2C2F**: A consumption framework similar to SLSA but focused on *ingesting* open source.
- **Tools**: They integrate **Trivy** and **Checkov** into Azure DevOps. They heavily invest in **CodeQL** (GitHub Advanced Security) for static analysis.

### CNCF Cloud Native Security Stack (2025 Standards)
- **Scanning**: **Trivy** (Aqua Security) is the de-facto standard for all-in-one scanning (fs, image, k8s).
- **Policy**: **Kyverno** or **OPA/Gatekeeper**. Kyverno is trending for K8s-native ease of use.
- **Runtime**: **Falco** (Sysdig) for behavioral monitoring at the kernel level.

---

## 3. Recommendations

Based on the assessment and industry standards, here is the prioritized roadmap:

### Phase 1: Supply Chain Basics (The "Quick Wins")
1.  **SBOM Generation**: Use **Syft** to generate SPDX SBOMs.
2.  **Attestation**: Use **Cosign** to attach SBOMs to images (achieves SLSA Level 2 compliance).
    *   *Why*: Low effort, high value for compliance. Allows future policy enforcement.

### Phase 2: Vulnerability Defense (The "Must Haves")
3.  **Implement Trivy Scanner**: Add a CI step to scan the generated images/SBOMs.
    *   *Why*: Catch "Critical" CVEs before they deploy. preventing bad code from reaching prod.
4.  **Enable CodeQL**: Enable GitHub's native CodeQL analysis for Go.
    *   *Why*: Catches bugs like SQL injection or unsafe pointer usage in code.

### Phase 3: Runtime & Policy (Advanced)
5.  **Kubernetes Hardening**: Implement `securityContext` (run as non-root) in all Helm charts/manifests.
6.  **Policy Engine**: Deploy **Kyverno** to block non-compliant pods (e.g., those running as root).

---

## 4. Proposed Implementation: Phase 1 (SBOM + Scanning)

We will start by modifying `build-be.yml` to include Syft and Trivy.

```yaml
# Example Workflow Additions
- name: Generate SBOM
  uses: anchore/sbom-action@v0
  with:
    image: ghcr.io/${{ github.repository_owner }}/${{ matrix.service }}:v6

- name: Scan Image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/${{ github.repository_owner }}/${{ matrix.service }}:v6
    format: 'table'
    exit-code: '1' # Fail build on error
    ignore-unfixed: true
    severity: 'CRITICAL,HIGH'
```
