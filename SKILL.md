---
name: deploy-mcp-server
description: Deploy a CrunchTools MCP server to breetai (laptop) or lotor (web server) with monitoring
argument-hint: "<server-name, e.g. airlock, gemini, gitlab>"
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Grep, Glob, Task, mcp__memory__memory_search, mcp__memory__memory_store, mcp__zabbix__host_get, mcp__zabbix__item_create, mcp__zabbix__item_get, mcp__zabbix__trigger_create, mcp__zabbix__trigger_get, mcp__zabbix__hostgroup_get
---

# Deploy a CrunchTools MCP Server

Deploy a built MCP server to a target host. Use this after `/draft-mcp-server` has created, tested, and published the server.

## Usage

```
/deploy-mcp-server airlock
/deploy-mcp-server gemini
```

---

## Phase 1: Gather Context

### Step 1: Search Memory

Search memory for the server's build details:
- `memory_search` for the server name (port, env vars, tool count)
- `memory_search` for "MCP architecture" to load port allocation and patterns
- `memory_search` for "lotor infrastructure" or "breetai" for host context

### Step 2: Select Target Host

Ask the user with `AskUserQuestion`:

| Host | Type | When to Use |
|------|------|-------------|
| **lotor** | Production web server | Containerized, systemd-managed, Zabbix-monitored, always-on |
| **breetai** | Interactive laptop | Development, testing, or stdio-only servers |

The target determines which phases apply:

| Phase | lotor | breetai |
|-------|-------|---------|
| Environment Setup | yes | yes |
| Container Deployment | yes | no |
| Claude Code Configuration | yes (HTTP) | yes (stdio or HTTP) |
| Verification | yes | yes |
| Zabbix Monitoring | yes | no |

### Step 3: Confirm Details

Confirm with the user:
- **Server name** (e.g., `mcp-airlock`)
- **HTTP port** (check `~/Projects/MCP_ARCHITECTURE.md` for next available)
- **Environment variables** needed (API keys, URLs, tokens)
- **Container image** (e.g., `quay.io/crunchtools/mcp-airlock:latest`)

---

## Phase 2: Environment Setup

Ask the user for the actual credential values.

### lotor (root services)

SSH to lotor and create the env file under `/srv/`:

```bash
ssh -p 22422 root@lotor.dc3.crunchtools.com
mkdir -p /srv/mcp-<name>.crunchtools.com/config
cat > /srv/mcp-<name>.crunchtools.com/config/mcp-<name>.env << 'EOF'
<SERVICE_URL>=https://...
<SERVICE_TOKEN>=...
EOF
chmod 600 /srv/mcp-<name>.crunchtools.com/config/mcp-<name>.env
```

Lotor convention: all service data lives under `/srv/<hostname>/` with subdirectories `config/`, `code/` (git-ignored), and `data/` (git-ignored).

### breetai (user services)

Create the env file locally:

```bash
cat > ~/.config/mcp-env/mcp-<name>.env << 'EOF'
<SERVICE_URL>=https://...
<SERVICE_TOKEN>=...
EOF
chmod 600 ~/.config/mcp-env/mcp-<name>.env
```

### Additional Config Files

Some servers need config files beyond environment variables (e.g., trust allowlists, domain configs). Check the server's `config.py` for any file paths it reads. Common patterns:

- **Trust config:** trust.json files with domain/path allowlists
- **Database:** Servers with SQLite databases need a persistent data directory (see Phase 3 volume mounts)

Create any additional config files the server expects, with correct permissions (`chmod 600`).

**Do NOT proceed to Phase 3 until all credentials and config files are in place.**

---

## Phase 3: Container Deployment

### lotor (root system service)

Systemd units on lotor MUST be regular files in `/etc/systemd/system/` (NOT symlinks — SELinux rejects symlinked unit files on bootc).

```bash
cat > /etc/systemd/system/mcp-<name>.crunchtools.com.service << 'EOF'
[Unit]
Description=MCP <Name> Server (Streamable HTTP)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/podman run --rm --name mcp-<name> \
    -p 127.0.0.1:<PORT>:<PORT> \
    --env-file /srv/mcp-<name>.crunchtools.com/config/mcp-<name>.env \
    quay.io/crunchtools/mcp-<name>:latest \
    --transport streamable-http --host 0.0.0.0 --port <PORT>
ExecStop=/usr/bin/podman stop mcp-<name>
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mcp-<name>.crunchtools.com.service
```

**Stateful servers:** Add volume mounts to the `ExecStart` line before the image name:

```
    -v /srv/mcp-<name>.crunchtools.com/data:/data:Z \
```

Create the host directory first: `mkdir -p /srv/mcp-<name>.crunchtools.com/data`

**Config file mounts:** If the server reads additional config files (trust configs, etc.):

```
    -v /srv/mcp-<name>.crunchtools.com/config/trust.json:/root/.config/mcp-env/mcp-<name>-trust.json:ro,Z \
```

### breetai (user service)

```bash
cat > ~/.config/systemd/user/mcp-<name>.service << 'EOF'
[Unit]
Description=MCP <Name> Server (Streamable HTTP)
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/mcp-env/mcp-<name>.env
ExecStart=/usr/bin/podman run --rm --name mcp-<name> \
    --network host \
    --env-file %h/.config/mcp-env/mcp-<name>.env \
    quay.io/crunchtools/mcp-<name>:latest \
    --transport streamable-http --host 127.0.0.1 --port <PORT>
ExecStop=/usr/bin/podman stop mcp-<name>
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now mcp-<name>.service
```

**Stateful servers:** Add volume mounts before the image name:

```
    -v %h/.local/share/mcp-<name>:/data:Z \
```

Create the host directory first: `mkdir -p ~/.local/share/mcp-<name>`

### Verify Container

**lotor:**
```bash
systemctl status mcp-<name>.crunchtools.com.service
curl -s http://127.0.0.1:<PORT>/mcp | head
```

**breetai:**
```bash
systemctl --user status mcp-<name>.service
curl -s http://127.0.0.1:<PORT>/mcp | head
```

---

## Phase 4: Claude Code Configuration

### lotor (HTTP)

Add to `~/.claude.json` on **breetai** (where Claude Code runs):
```json
"mcp-<name>-crunchtools": {
    "type": "http",
    "url": "http://127.0.0.1:<PORT>/mcp"
}
```

Note: breetai connects to lotor's ports via SSH tunnel or direct network access.

### breetai (stdio)

Add to `~/.claude.json` on breetai:
```json
"mcp-<name>-crunchtools": {
    "command": "uvx",
    "args": ["mcp-<name>-crunchtools"],
    "env": {
        "SERVICE_TOKEN": "..."
    }
}
```

Or with a container:
```json
"mcp-<name>-crunchtools": {
    "command": "podman",
    "args": [
        "run", "-i", "--rm",
        "--env-file", "/home/fatherlinux/.config/mcp-env/mcp-<name>.env",
        "quay.io/crunchtools/mcp-<name>"
    ]
}
```

---

## Phase 5: Verification

Test the MCP tools work by calling a read operation (e.g., site info, search, list). Restart Claude Code if needed to pick up the new config.

---

## Phase 6: Zabbix Monitoring (lotor only)

Skip this phase for breetai deployments.

All MCP servers on lotor get three-layer Zabbix monitoring. The monitoring items live on the lotor host (hostid `10698`, interfaceid `45`), not on separate Zabbix hosts.

### 6a: TCP Port Check

Create a `net.tcp.service` item on lotor to verify the MCP server port is reachable:

```
item_create:
  name: "MCP <Name> Port <PORT>"
  key_: "net.tcp.service[http,127.0.0.1,<PORT>]"
  hostid: "10698"
  type: 0          # Zabbix agent
  value_type: 3    # unsigned integer (1=up, 0=down)
  delay: "1m"
```

Use the `mcp__zabbix__item_create` tool. If the Zabbix MCP server is in read-only mode, tell the user to create the item manually via the Zabbix web UI or enable Zabbix writes temporarily.

### 6b: TCP Port Trigger

Create a trigger that fires when the port is unreachable for 5 minutes:

```
trigger_create:
  description: "MCP <Name> port <PORT> is unreachable"
  expression: "max(/lotor.dc3.crunchtools.com/net.tcp.service[http,127.0.0.1,<PORT>],5m)=0"
  priority: 4      # HIGH
  tags: [{"tag": "host", "value": "lotor.dc3.crunchtools.com"}, {"tag": "service", "value": "mcp-<name>"}]
```

### 6c: service-checker.py

Tell the user to add the new container to `/srv/zabbix-agent/scripts/service-checker.py` on lotor. The entry format is:

```python
("mcp-<name>", "svc.mcp-<name>", "python"),
```

This checks that a Python process is running inside the container via `podman exec mcp-<name> pgrep -c python` and sends the count to Zabbix via the trapper protocol every 60 seconds.

A corresponding trapper item must also be created on lotor:

```
item_create:
  name: "MCP <Name> Process"
  key_: "svc.mcp-<name>"
  hostid: "10698"
  type: 2          # Zabbix trapper
  value_type: 3    # unsigned integer (process count)
```

### 6d: Service Tree (Running Instance)

The Zabbix dashboard at `https://zabbix.crunchtools.com/service-tree.php` displays all monitored services in a visual tree. New MCP servers must be added to the service tree so they appear on the dashboard.

The service-tree.php file lives at `/srv/zabbix.crunchtools.com/code/service-tree.php` on lotor (mounted into the Zabbix container). It queries Zabbix for `web.test.fail` (web scenarios), `net.tcp.service` (port checks), and `svc.*` (trapper items) and renders them as a status tree.

To add the new MCP server to the dashboard:

1. SSH to lotor and edit `/srv/zabbix.crunchtools.com/code/service-tree.php`
2. Add the MCP server's port to the TCP check display section
3. Add the `svc.mcp-<name>` trapper item to the `$svc_display_names` array:
   ```php
   'svc.mcp-<name>' => 'MCP <Name>',
   ```
4. Verify the new entry appears at `https://zabbix.crunchtools.com/service-tree.php`

MCP servers are loopback-only (no public HTTPS), so they appear in the service tree under lotor's TCP port checks and process checks, not as separate hosts with web scenarios.

---

## Phase 7: Update MCP Architecture Doc

Update `~/Projects/MCP_ARCHITECTURE.md`:
- Add the server to the port allocation table (lotor) or stdio table (breetai)
- Update the version table
- Update the total server count and tool count

---

## Phase 8: Store in Memory

Store the deployment details using `memory_store`:
- Target host (breetai or lotor)
- Port number and transport type
- systemd service name (if lotor)
- Zabbix items created
- Any deployment-specific notes or workarounds

---

## Output Summary

```
Server:         mcp-<name>-crunchtools
Target:         <breetai|lotor>
Transport:      <stdio|streamable-http>
Port:           <PORT or n/a>
Systemd:        <service name or n/a>
Env File:       ~/.config/mcp-env/mcp-<name>.env
Claude Config:  ~/.claude.json
Zabbix:         <TCP port check + trapper on lotor (10698) or n/a>
Service Tree:   <lotor running instance section or n/a>
```
