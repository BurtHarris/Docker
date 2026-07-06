# Docker Image Builds

A collection of Docker image build instructions and related configuration. Each
subdirectory contains everything needed to build and run a specific image or
service stack.

## Repository conventions

| Convention | Details |
|---|---|
| One folder per image / stack | `<name>/Dockerfile`, `<name>/docker-compose.yml` |
| Secrets via `.env` | Copy `.env.example` → `.env`, never commit `.env` |
| Pinned base-image versions | Use explicit tags, not `latest`, in `FROM` lines |
| Non-root runtime user | Prefer `USER` directive or image defaults that drop privileges |
| Health checks | Add `HEALTHCHECK` or `healthcheck:` in compose for every long-running service |
| `.dockerignore` per image | Keep build contexts small |

## Available images

| Folder | Description |
|---|---|
| [`wikimedia/`](wikimedia/) | MediaWiki server (the software that powers Wikipedia) |

## Quick start

Each folder has its own `README.md` with image-specific instructions.
General workflow:

```bash
cd <image-folder>
cp .env.example .env        # fill in secrets
docker compose up -d        # start the stack
docker compose logs -f      # watch logs
docker compose down         # stop
```

## Windows developer initialization (repo-level defaults)

For Windows developer machines, initialize local repository defaults once:

```powershell
.\Initialize-DockerRepo.ps1
```

This cmdlet prompts for defaults such as where test containers should be
deployed, then stores personal values in:

- `HKCU\Software\BurtHarris\Docker`

Effective settings are read with:

```powershell
.\Get-DockerRepoConfig.ps1
```

Policy enforcement is transparent: values defined in
`HKLM\SOFTWARE\Policies\BurtHarris\Docker` automatically override user values.
Scripts can call `.\Get-DockerRepoConfig.ps1` to consume effective settings
without implementing policy logic themselves.
