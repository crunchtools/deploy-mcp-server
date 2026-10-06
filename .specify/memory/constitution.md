# deploy-mcp-server Constitution

> **Version:** 1.1.0
> **Ratified:** 2026-03-10
> **Amended:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.20.0
> **Profile:** Claude Skill

The `/deploy-mcp-server` skill deploys a built CrunchTools MCP server to a
target host: environment setup, container deployment, Claude Code
configuration, Nagios monitoring, and a memory record of the result.

This file holds what is specific to this skill. The fleet rules and the
Claude Skill profile (frontmatter, phased workflow, gates, memory
integration) apply at the inherited version and are checked against this
repo's files by `constitution.yml`. They are not restated here.

## Two Host Types

The skill branches on the target: the production web server, where the
server runs as a root (system) service, or an interactive laptop, where it
runs as a user service. Nagios monitoring (Phase 6) applies to the web server
only. Port allocation comes from Nagios, which is the MCP port registry
(Phase 1 Step 3).

## Phase Gates

- Phase 1 to Phase 2: the user confirms target host, port, env vars and
  container image.
- Phase 5: the MCP tools answer test calls.
- Phase 6 to Phase 7: the Nagios host and both services are OK.

## Memory Records

Phase 1 Step 1 searches memory for the server's build details and host
context; Phase 7 stores the deployment (target host, port, systemd service,
Nagios checks).

## Relationship to Other Skills

The deployment counterpart to `/draft-mcp-server`, which builds, tests and
publishes:

1. `/draft-mcp-server <name>`: build and publish.
2. `/deploy-mcp-server <name>`: deploy to the target host.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-10 | Initial constitution |
| 1.1.0 | 2026-10-02 | Manifest under constitution v1.18.0: profile restatement removed; host names dropped (XVII); monitoring is Nagios |
