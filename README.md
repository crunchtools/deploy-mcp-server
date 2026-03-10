# /deploy-mcp-server

Claude Code skill for deploying CrunchTools MCP servers to target hosts.

## Usage

```
/deploy-mcp-server airlock
/deploy-mcp-server gemini
```

## Target Hosts

| Host | Type | Service Model |
|------|------|---------------|
| **lotor** | Production web server | Root systemd services in `/etc/systemd/system/`, data in `/srv/` |
| **breetai** | Interactive laptop | User systemd services in `~/.config/systemd/user/` |

## Phases

1. **Gather Context** — search memory, select target host, confirm details
2. **Environment Setup** — env files, trust configs, data directories
3. **Container Deployment** — systemd service (lotor: root, breetai: user)
4. **Claude Code Configuration** — HTTP (lotor) or stdio (breetai)
5. **Verification** — test MCP tools respond
6. **Zabbix Monitoring** — TCP port, triggers, service-checker, service-tree (lotor only)
7. **Update MCP Architecture Doc**
8. **Store in Memory**

## Installation

```bash
cd ~/Projects/crunchtools
git clone https://github.com/crunchtools/deploy-mcp-server.git
ln -s ~/Projects/crunchtools/deploy-mcp-server ~/.claude/skills/deploy-mcp-server
```

## License

AGPL-3.0-or-later
