# deploy-mcp-server Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-03-10
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.1.0
> **Profile:** Claude Skill

## Overview

The `/deploy-mcp-server` skill deploys built CrunchTools MCP servers to target hosts — either lotor (production web server, root services) or breetai (interactive laptop, user services). It covers environment setup, container deployment, Claude Code configuration, Zabbix monitoring, and service-tree dashboard entries.

## License

AGPL-3.0-or-later

## Versioning

Follow Semantic Versioning 2.0.0. MAJOR/MINOR/PATCH.

## SKILL.md Standards

- YAML frontmatter with `name`, `description`, `argument-hint`, `allowed-tools`
- Organized into numbered Phases with numbered Steps
- Phase gates prevent proceeding without user approval at critical checkpoints
- Host-specific branching: lotor (root/system) vs breetai (user)

## Memory Integration

- Phase 1 Step 1: Searches memory for server build details, port allocation, host context
- Phase 8: Stores deployment details (target host, port, systemd service, Zabbix items)

## User Confirmation Gates

- Phase 1 → Phase 2: User confirms target host, port, env vars, container image
- Phase 5: Verification — MCP tools respond to test calls

## Relationship to Other Skills

This skill is the deployment counterpart to `/draft-mcp-server`, which handles building, testing, and publishing. The workflow is:
1. `/draft-mcp-server <name>` — build and publish
2. `/deploy-mcp-server <name>` — deploy to target host
