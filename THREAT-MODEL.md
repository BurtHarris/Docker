# Threat Model — BurtHarris/Docker

> **Version:** 1.0  
> **Date:** 2026-07-06  
> **Methodology:** STRIDE (Spoofing · Tampering · Repudiation · Information Disclosure · Denial of Service · Elevation of Privilege)  
> **Scope:** All Docker stacks and PowerShell management scripts in this repository  
> **Status:** Baseline — mitigations tracked as issues; implementation deferred to the next PR

---

## 1. Scope and Assets

This repository manages Docker-based server stacks and the PowerShell scripts
(and forthcoming module) that provision secrets for those stacks.

### Protected assets

| Asset | Sensitivity | Location |
|---|---|---|
| `DB_PASSWORD` | **Critical** | Windows cert store → `secrets/DB_PASSWORD.cms` |
| `MW_SECRET_KEY` | **Critical** | Windows cert store → `secrets/MW_SECRET_KEY.cms` |
| `MW_UPGRADE_KEY` | **Critical** | Windows cert store → `secrets/MW_UPGRADE_KEY.cms` |
| RSA private key | **Critical** | `Cert:\CurrentUser\My` (DPAPI/TPM-protected) |
| `.env` file | **High** | Operator workstation (gitignored) |
| Docker image layers | **Medium** | Local daemon cache / registry push targets |
| Git repository history | **Medium** | GitHub + local clones |
| `trust/*.cer` public certificates | **Low** | Committed to repository |

### Non-assets (explicitly out of scope)

- Wiki content (MediaWiki data managed separately)
- Docker daemon security on remote/production hosts
- GitHub account and CI runner credentials

---

## 2. Architecture and Data-Flow Diagram

```
 ┌─────────────────────────────────────────────────────────────┐
 │  Operator workstation (Windows 11)                          │
 │                                                             │
 │  PowerShell module / scripts                                │
 │  ┌─────────────┐   ┌──────────────────┐  ┌──────────────┐  │
 │  │ New-Key     │   │ Set-Secrets      │  │ Start-Stack  │  │
 │  │             │   │                  │  │              │  │
 │  │ Cert store ─┼──►│ Protect-Cms ─────┼─►│ Unprotect   │  │
 │  │ (DPAPI/TPM) │   │                  │  │   ↓          │  │
 │  └─────────────┘   │  secrets/*.cms   │  │ env vars     │  │
 │       │ export     │  (gitignored)    │  │   ↓          │  │
 │       ▼            └──────────────────┘  │ docker       │  │
 │  trust/*.cer ───────────────────────────►│  compose     │  │
 │  (committed to repo)                     └──────┬───────┘  │
 └──────────────────────────────────────────────── │ ─────────┘
                                                   │
                          ┌────────────────────────▼──────────┐
                          │  Docker Compose stack              │
                          │                                    │
                          │  ┌──────────────┐  ┌───────────┐  │
                          │  │  mediawiki   │  │  database │  │
                          │  │  (www-data)  │  │  (mysql)  │  │
                          │  └──────┬───────┘  └─────┬─────┘  │
                          │         └────internal_net─┘        │
                          └────────────────────────────────────┘
```

### Trust boundaries

| Boundary | Description |
|---|---|
| **TB-1** | Windows DPAPI / TPM ↔ PowerShell process |
| **TB-2** | Operator file system ↔ Git repository (gitignore enforcement) |
| **TB-3** | Host OS ↔ Docker container runtime |
| **TB-4** | Container ↔ Container (internal Docker network) |
| **TB-5** | Container network ↔ External internet |
| **TB-6** | Developer workstation ↔ Public Docker Hub / package registries |

---

## 3. Threat Actors

| Actor | Capability | Motivation |
|---|---|---|
| **Malicious outsider** | No local access; can read public repo | Harvest credentials for wiki or DB |
| **Compromised dependency** | Code execution in build / compose context | Supply-chain pivot; data exfiltration |
| **Insider / disgruntled contributor** | Repo write access; may have workstation access | Sabotage; credential theft |
| **Physical-access attacker** | Workstation access (unlocked or during travel) | DPAPI key extraction; memory scrape |

---

## 4. Threat Catalogue

Risk ratings use a **3 × 3 likelihood/impact** matrix:

- **Likelihood:** Low / Medium / High
- **Impact:** Low / Medium / High / Critical
- **Risk** = combined score; **Critical/High** = must mitigate; **Medium** = should mitigate; **Low** = accept or defer

---

### T-01 — Accidental `.env` commit

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Medium |
| **Impact** | Critical |
| **Risk** | **Critical** |
| **Asset** | DB_PASSWORD, MW_SECRET_KEY, MW_UPGRADE_KEY |
| **Description** | A developer copies `.env.example` to `.env`, fills in real secrets, and accidentally runs `git add -A` before staging specific files. The secrets land in history and are immediately exposed on push. |
| **Existing mitigations** | `.gitignore` lists `.env` in the wikimedia sub-directory |
| **Gaps** | No repo-root `.gitignore` guard; no pre-commit hook; no secret-scanning CI step; gitignore only prevents _new_ commits — a forced `git add -f` bypasses it |
| **Recommended mitigations** | Add a `.gitignore` pattern at repo root; add pre-commit hook (`git-secrets` or `gitleaks`); add GitHub secret-scanning (free for public repos); document recovery procedure (BFG / `git filter-repo`) |

---

### T-02 — CMS secrets directory committed

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Low |
| **Impact** | Medium |
| **Risk** | **Medium** |
| **Asset** | `secrets/*.cms` ciphertext |
| **Description** | The `secrets/` directory is gitignored but an operator could commit it intentionally or via IDE tooling. Even though the files require the private key to decrypt, committing them leaks file names, indicates which secrets exist, and narrows the attack surface for future private-key compromise. |
| **Existing mitigations** | `wikimedia/.gitignore` lists `secrets/` |
| **Gaps** | No verification that `secrets/` is always excluded; no guidance for operators on what "accidental add" looks like |
| **Recommended mitigations** | Add a CI check that fails if any `*.cms` file is staged; add note to operator guide |

---

### T-03 — RSA private key extraction (DPAPI bypass)

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Low |
| **Impact** | Critical |
| **Risk** | **High** |
| **Asset** | RSA private key (`Cert:\CurrentUser\My`) |
| **Description** | An attacker with local administrator access, a memory-scraping tool, or physical access to an unencrypted drive can extract the DPAPI master key, which can then decrypt the RSA private key. With the private key, all `.cms` files are immediately decryptable. |
| **Existing mitigations** | `KeyExportPolicy NonExportable`; DPAPI/TPM binding in Windows certificate store |
| **Gaps** | `NonExportable` prevents GUI/API export but does not protect against DPAPI master-key extraction; no TPM binding enforced by script (uses default); no hardware-backed enforcement for VMs or non-TPM devices |
| **Recommended mitigations** | Document TPM 2.0 as a hard requirement; use `-KeyStorageFlags` to request `MachineKeySet + Exportable:false + ProtectedByHardware` where available; add TPM presence check in key-generation cmdlet; consider FIDO2 hardware token support as an alternative |

---

### T-04 — Plaintext secret in process memory

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Medium |
| **Impact** | High |
| **Risk** | **High** |
| **Asset** | DB_PASSWORD, MW_SECRET_KEY, MW_UPGRADE_KEY (plaintext during `Start-Wiki.ps1`) |
| **Description** | `Unprotect-CmsMessage` returns a plain `[string]`, which is an immutable .NET object. Setting `$plain = $null` only removes the variable reference — the underlying string object may survive in the managed heap until GC. The plaintext is also briefly present in .NET string interning caches and may appear in process memory dumps. |
| **Existing mitigations** | Variable cleared (`$plain = $null`) immediately after use; secrets only live in process scope |
| **Gaps** | .NET strings are immutable and cannot be securely zeroed; `SecureString` is not used; no `[gc]::Collect()` + `[gc]::WaitForPendingFinalizers()` after clearing |
| **Recommended mitigations** | Use `SecureString` for in-memory representation; convert to plaintext only at the last moment (environment variable injection); call GC.Collect after clearing; document that memory dumps on the operator machine are a residual risk; consider using Windows Data Protection API directly via `[System.Security.Cryptography.ProtectedData]` for intermediate storage |

---

### T-05 — Process environment variable leakage

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Medium |
| **Impact** | High |
| **Risk** | **High** |
| **Asset** | DB_PASSWORD, MW_SECRET_KEY, MW_UPGRADE_KEY (as env vars during `docker compose`) |
| **Description** | `[System.Environment]::SetEnvironmentVariable(..., 'Process')` makes secrets visible to any code running in the same PowerShell process (other scripts, modules). Additionally, `docker compose` may log or display environment variable values in its output, error messages, or diagnostic dumps. Other processes owned by the same Windows user can read their sibling processes' environment via WMI or procmon tools. |
| **Existing mitigations** | Env vars scoped to `Process` (not `Machine` or `User`); env vars disappear when the process exits |
| **Gaps** | No scrubbing of env vars after `docker compose` returns; logging of compose commands may include env var contents; no verification that `docker compose` does not write env vars to log files |
| **Recommended mitigations** | Clear env vars (`[System.Environment]::SetEnvironmentVariable($key, $null, 'Process')`) immediately after `docker compose` exits; review Docker Compose log verbosity; consider using Docker secrets or tmpfs-mounted files instead of environment variables for production use |

---

### T-06 — Docker image layer secret leakage

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Low |
| **Impact** | Critical |
| **Risk** | **Medium** |
| **Asset** | DB_PASSWORD, MW_SECRET_KEY (if embedded in image layers) |
| **Description** | Docker `ARG` values and `ENV` instructions are recorded in image layer history and are trivially recoverable with `docker history --no-trunc`. If a future maintainer adds secrets as build arguments or ENV instructions (e.g. during debugging), they become permanently embedded in the image. |
| **Existing mitigations** | Current `Dockerfile` does not embed any secrets; env vars are injected at `docker compose up` time, not at build time |
| **Gaps** | No policy enforcement (no `hadolint` rule preventing `ARG`/`ENV` for known secret names); no CI check; maintainer documentation does not explicitly warn against this anti-pattern |
| **Recommended mitigations** | Add `hadolint` linting to CI; add inline comment in `Dockerfile` warning against using `ARG` for secrets; add example in developer documentation |

---

### T-07 — Trust anchor substitution

| Field | Value |
|---|---|
| **STRIDE** | Spoofing, Tampering |
| **Likelihood** | Low |
| **Impact** | High |
| **Risk** | **Medium** |
| **Asset** | `trust/*.cer` public certificates |
| **Description** | An attacker with write access to the repository (or a compromised CI environment) could replace a `.cer` trust marker with their own certificate. The next operator to run `Set-Secrets` would encrypt secrets to the attacker's key. The attacker (holding the corresponding private key) can then decrypt any secrets encrypted against their certificate. |
| **Existing mitigations** | `.cer` files are committed to git (history is auditable); certificate subject encodes the wiki name |
| **Gaps** | No digital signature on the trust directory; no certificate pinning; no warning when a `.cer` file is replaced; GitHub branch protection alone is insufficient if an insider can push to the branch |
| **Recommended mitigations** | Sign `trust/*.cer` files with a GPG/SSH key stored in `allowed_signers`; add a CI check that verifies `.cer` file signatures; document the trust anchor review process; consider using GitHub's commit signature requirement on the default branch |

---

### T-08 — Mutable base-image tag (supply chain)

| Field | Value |
|---|---|
| **STRIDE** | Tampering |
| **Likelihood** | Low |
| **Impact** | Critical |
| **Risk** | **High** |
| **Asset** | `mediawiki:1.43`, `mariadb:10.11` Docker images |
| **Description** | Docker image tags are mutable — a registry owner (or a compromised Docker Hub account) can push a new image to the same tag. `docker compose build` would silently pull a backdoored image on the next build. This is a classic supply-chain substitution attack. |
| **Existing mitigations** | Explicit version tags are used (`mediawiki:1.43`, `mariadb:10.11`); `latest` is explicitly avoided per project conventions |
| **Gaps** | Tags are **not** pinned by digest (`@sha256:...`); no image signature verification (Cosign/Notary); no CI check that verifies digest matches a known-good value |
| **Recommended mitigations** | Pin base images by digest in `Dockerfile` and `docker-compose.yml` (e.g., `mediawiki:1.43@sha256:<digest>`); add Dependabot or Renovate for automated digest updates; verify signatures with `docker trust inspect` or `cosign verify` in CI |

---

### T-09 — Database network exposure in development

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure, Elevation of Privilege |
| **Likelihood** | Medium |
| **Impact** | High |
| **Risk** | **High** |
| **Asset** | MariaDB database (port 3306) |
| **Description** | `docker-compose.yml` sets `internal: false` on `internal_net` for development. While the DB container's port 3306 is not exposed to the host (`expose:` rather than `ports:`), any other container on the same Docker network bridge (including attacker-controlled containers spawned by a compromised image or a `docker run` command from the same user) can reach MariaDB. |
| **Existing mitigations** | Port 3306 not published to host (`expose:` not `ports:`); `MYSQL_RANDOM_ROOT_PASSWORD: "yes"` prevents password reuse |
| **Gaps** | `internal: false` means containers on the bridge can also reach the internet (and vice versa via routing), allowing exfiltration; production override (`docker-compose.prod.yml`) sets `internal: true` but only if applied |
| **Recommended mitigations** | Set `internal: true` by default even in development (MediaWiki can reach Wikidata via the mediawiki container, not from the DB container); add a `networks.internal_net.internal: true` note with commentary explaining the trade-off; ensure production override is the default for the `prod.yml` file |

---

### T-10 — Container privilege escalation

| Field | Value |
|---|---|
| **STRIDE** | Elevation of Privilege |
| **Likelihood** | Low |
| **Impact** | High |
| **Risk** | **Medium** |
| **Asset** | Container runtime; host kernel |
| **Description** | The MediaWiki container starts as root to bind port 80 before dropping to `www-data` (uid 33). There is no `seccomp` profile, no `AppArmor`/`SELinux` label, no explicit capability dropping, and no read-only root filesystem. A kernel exploit or container escape could allow a compromised PHP process to escalate to the host. |
| **Existing mitigations** | Apache drops from root to `www-data`; no Docker socket mounted; no `--privileged` flag |
| **Gaps** | No `cap_drop: ALL` / `cap_add: [NET_BIND_SERVICE]`; no `security_opt: seccomp`; no `read_only: true` on root filesystem; no user-namespace remapping |
| **Recommended mitigations** | Add `cap_drop: [ALL]` and `cap_add: [NET_BIND_SERVICE, CHOWN, SETGID, SETUID]` in compose; add `security_opt: ["no-new-privileges:true"]`; consider running on a high port (8080) via reverse proxy to eliminate the `CAP_NET_BIND_SERVICE` requirement; add `read_only: true` with explicit `tmpfs` mounts for writable paths |

---

### T-11 — Repudiation — no audit trail for secret operations

| Field | Value |
|---|---|
| **STRIDE** | Repudiation |
| **Likelihood** | High |
| **Impact** | Medium |
| **Risk** | **Medium** |
| **Asset** | Secret creation, rotation, and decryption events |
| **Description** | There is no logging of when keys were created, when secrets were encrypted or rotated, or when `Start-Wiki.ps1` decrypted and used secrets. An operator cannot determine after the fact whether secrets were accessed by an unauthorized party. |
| **Existing mitigations** | Git commit history records when `trust/*.cer` files were added or changed |
| **Gaps** | No structured log output from PowerShell scripts/module; no Windows Event Log write; no timestamped audit entry |
| **Recommended mitigations** | Write a structured log entry to the Windows Application Event Log (using `Write-EventLog` or `[System.Diagnostics.EventLog]`) on key creation, secret encryption, and secret decryption; include certificate thumbprint and timestamp; surface a `Get-SecretAuditLog` cmdlet in the forthcoming module |

---

### T-12 — Secret rotation not enforced

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure (latent) |
| **Likelihood** | High (over time) |
| **Impact** | High |
| **Risk** | **High** |
| **Asset** | All secrets |
| **Description** | The default certificate validity is 10 years and there is no mechanism that prompts or enforces periodic secret rotation. If a secret is compromised but the compromise goes undetected, the attacker retains access for up to the certificate lifetime. |
| **Existing mitigations** | `New-WikiKey.ps1` certificate expiry is displayed; `-Force` flag enables rotation |
| **Gaps** | No warning when certificate approaches expiry; no policy-enforced maximum secret age; no integration with any secrets rotation workflow |
| **Recommended mitigations** | Emit a prominent warning when certificate has fewer than 90 days remaining; default `ValidYears` to 2 (not 10) for newly generated certificates; add a `Test-SecretHealth` cmdlet that checks expiry and reports stale secrets; document a secrets rotation runbook |

---

### T-13 — PowerShell script code-signing bypass

| Field | Value |
|---|---|
| **STRIDE** | Tampering, Elevation of Privilege |
| **Likelihood** | Medium |
| **Impact** | High |
| **Risk** | **High** |
| **Asset** | PowerShell scripts / forthcoming module |
| **Description** | The scripts are not Authenticode-signed. An attacker who can write to the file system (e.g., via a compromised dependency, malicious git hook, or path-manipulation attack) can modify `Start-Wiki.ps1` to exfiltrate secrets to an attacker-controlled endpoint at decryption time. The operator would not notice because the command-line interface is identical. |
| **Existing mitigations** | None currently |
| **Gaps** | No `#Requires -PSEdition` or execution policy guidance; no Authenticode signature; no hash manifest; no CI signature step |
| **Recommended mitigations** | Authenticode-sign the PowerShell module manifest (`.psd1`) and all exported `.psm1` / `.ps1` files using a code-signing certificate; add a pre-run hash verification option; document expected `Get-AuthenticodeSignature` output for operators; require `Set-ExecutionPolicy AllSigned` or `RemoteSigned` on operator machines |

---

### T-14 — Git history exposure of accidentally committed secrets

| Field | Value |
|---|---|
| **STRIDE** | Information Disclosure |
| **Likelihood** | Low |
| **Impact** | Critical |
| **Risk** | **High** |
| **Asset** | Any secret that was ever in a commit |
| **Description** | If a developer accidentally commits `.env` or a `.cms` file, removing it in a subsequent commit does not expunge it from history. Any clone or shallow fetch of the repository still contains the exposed data indefinitely. Automated secret-scanning bots routinely harvest GitHub history. |
| **Existing mitigations** | `.gitignore` entries reduce accident rate |
| **Gaps** | No documented recovery procedure; no branch protection requiring review before push; no automated secret-scanning on push (GitHub Advanced Security secret scanning or `gitleaks` in CI) |
| **Recommended mitigations** | Enable GitHub secret scanning for the repository; add `gitleaks` or `trufflehog` as a pre-commit hook and CI step; document the recovery procedure (rotate secrets immediately; use `git filter-repo --path .env --invert-paths` to rewrite history; force-push; notify all collaborators to re-clone) |

---

### T-15 — Denial of service via certificate store pollution

| Field | Value |
|---|---|
| **STRIDE** | Denial of Service |
| **Likelihood** | Low |
| **Impact** | Medium |
| **Risk** | **Low** |
| **Asset** | Operator's `Cert:\CurrentUser\My` store |
| **Description** | An attacker (or a buggy script run with `Force`) could flood the certificate store with certificates matching the expected `Subject` pattern, causing the `Sort-Object NotAfter -Descending | Select-Object -First 1` selection logic to pick the wrong certificate. This would cause decryption failures (DoS) or, in a crafted scenario, cause secrets to be encrypted to an unintended certificate (see T-07). |
| **Existing mitigations** | `Select-Object -First 1` picks the most recently expiring cert |
| **Gaps** | No thumbprint pinning after key generation; no check for duplicate-subject certificates in `Set-WikiSecrets.ps1`; no warning when multiple matching certs exist |
| **Recommended mitigations** | Persist the certificate thumbprint to a config file on key creation; use thumbprint for subsequent lookups rather than subject string; emit a warning (non-fatal) when multiple valid subject-matching certs exist |

---

### T-16 — `.cms` file tampering (attacker-controlled ciphertext substitution)

| Field | Value |
|---|---|
| **STRIDE** | Tampering |
| **Likelihood** | Low |
| **Impact** | High |
| **Risk** | **Medium** |
| **Asset** | `secrets/*.cms` files |
| **Description** | If an attacker gains write access to the operator's `secrets/` directory (e.g., via a malicious repository hook, a compromised editor plugin, or shared-drive access), they can substitute `.cms` files encrypted to their own certificate. `Start-Wiki.ps1` will fail to decrypt (because the wrong private key is used), producing a confusing error rather than a security alert. In a more sophisticated attack, the substituted file might decrypt to malicious content if the attacker also controls the docker compose environment. |
| **Existing mitigations** | Decryption failure throws a terminating error |
| **Gaps** | No integrity check (MAC/HMAC) on `.cms` files beyond what CMS itself provides; no verification that the decryption certificate matches the expected thumbprint |
| **Recommended mitigations** | After decryption, verify the encrypting certificate thumbprint matches the stored thumbprint from T-15 mitigation; log certificate thumbprint used for each decryption |

---

## 5. Risk Summary

| ID | Title | Risk | Status |
|---|---|---|---|
| T-01 | Accidental `.env` commit | **Critical** | Open |
| T-02 | CMS secrets directory committed | Medium | Open |
| T-03 | RSA private key extraction (DPAPI bypass) | **High** | Partial |
| T-04 | Plaintext secret in process memory | **High** | Partial |
| T-05 | Process environment variable leakage | **High** | Partial |
| T-06 | Docker image layer secret leakage | Medium | Partial |
| T-07 | Trust anchor substitution | Medium | Open |
| T-08 | Mutable base-image tag (supply chain) | **High** | Partial |
| T-09 | Database network exposure in development | **High** | Partial |
| T-10 | Container privilege escalation | Medium | Open |
| T-11 | Repudiation — no audit trail | Medium | Open |
| T-12 | Secret rotation not enforced | **High** | Partial |
| T-13 | PowerShell script code-signing bypass | **High** | Open |
| T-14 | Git history exposure | **High** | Partial |
| T-15 | Certificate store pollution (DoS) | Low | Open |
| T-16 | `.cms` file tampering | Medium | Open |

**Status key:** Open = no mitigation exists; Partial = at least one layer of defence in place but gaps remain; Closed = fully mitigated.

---

## 6. Mitigations Scheduled for the Next PR

The following changes are planned for implementation in the PR that introduces
the cross-image PowerShell management module:

| Priority | Addresses | Planned action |
|---|---|---|
| 1 | T-04 | Use `SecureString` throughout; clear managed memory explicitly |
| 2 | T-05 | Clear process env vars immediately after `docker compose` returns |
| 3 | T-12 | Default certificate validity to 2 years; add expiry warning at 90 days |
| 4 | T-15 | Persist and use thumbprint for all cert lookups |
| 5 | T-11 | Write structured entries to Windows Application Event Log |
| 6 | T-09 | Set `internal: true` as compose default; document override for Wikidata |
| 7 | T-10 | Add `cap_drop`, `security_opt: no-new-privileges`, `read_only` to compose |
| 8 | T-08 | Document digest-pinning process; add Renovate/Dependabot config |
| 9 | T-01 / T-14 | Add root-level `.gitignore` guard; add `gitleaks` pre-commit hook |
| 10 | T-13 | Document Authenticode signing workflow for module releases |

Items T-02, T-06, T-07, T-16 are lower risk and will be addressed in subsequent
iterations or flagged as accepted risks after operator review.

---

## 7. Assumptions and Constraints

1. **Windows 11 with BitLocker** is the assumed baseline operator platform;
   DPAPI protection degrades significantly without full-disk encryption.
2. **TPM 2.0** is strongly recommended but not currently enforced by the scripts.
3. **Single-user workstation** is the assumed deployment model; shared workstations
   require additional access controls outside this module's scope.
4. **GitHub Actions** are not currently in use for secret operations; this model
   does not cover CI/CD secret injection patterns.
5. The **Git hosting platform** (GitHub) is a trusted party for repository
   integrity purposes; GitHub account compromise is out of scope.

---

## 8. Review and Maintenance

This document should be reviewed:

- When a new image or stack is added to the repository
- When the PowerShell module API surface changes materially
- When a security incident occurs
- At least once per calendar year

Raise a PR against this file to propose changes.  Tag the PR `security` and
request review from at least one additional contributor.
