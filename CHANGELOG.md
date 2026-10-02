# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

This project has not cut a tagged release; changes since the repo was created
are not recorded here. Entries accrue from 2026-09-19 forward (RT #1484).

### Changed

- Constitution is now a v1.18.0 manifest: fleet and profile rules apply by
  reference, and the file keeps only what is specific to this repo.
- Constitution validation is pinned to the inherited release via
  `.github/workflows/constitution.yml`.
- Dependabot auto-merges GitHub Actions minor and patch updates.
- `SKILL.md` synced from `crunchtools/josui-skills`, where the skill is
  maintained. This also replaces the stale Zabbix phase with Nagios. The retired `MCP_ARCHITECTURE.md` is gone; Nagios is the MCP port
  registry (next port from `check_tcp_*` in `crunchtools/nagios-agent`
  `deploy/nagios-agent/nrpe-host.cfg`).
