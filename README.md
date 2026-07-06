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
