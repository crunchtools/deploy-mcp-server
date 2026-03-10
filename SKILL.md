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
| Fleet Watchdog | yes | optional |

### Step 3: Confirm Details

Confirm with the user:
- **Server name** (e.g., `mcp-airlock`)
- **HTTP port** (check `~/Projects/MCP_ARCHITECTURE.md` for next available)
- **Environment variables** needed (API keys, URLs, tokens)
- **Container image** (e.g., `quay.io/crunchtools/mcp-airlock:latest`)

---

## Phase 2: Environment Setup

Create the environment file:

```bash
cat > ~/.config/mcp-env/mcp-<name>.env << 'EOF'
<SERVICE_URL>=https://...
<SERVICE_TOKEN>=...
EOF
chmod 600 ~/.config/mcp-env/mcp-<name>.env
```

Ask the user for the actual credential values.

**lotor:** The env file lives on lotor at `~/.config/mcp-env/`. SSH to lotor to create it:
```bash
ssh -p 22422 root@lotor.dc3.crunchtools.com
```

**breetai:** The env file lives locally at `~/.config/mcp-env/`.

---

## Phase 3: Container Deployment (lotor only)

Skip this phase for breetai deployments.

### Step 1: Create systemd Service

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

### Step 2: Verify Container

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

## Phase 7: Fleet Watchdog (Repository Monitoring)

The fleet watchdog (`crunchtools/factory`) monitors all CrunchTools repos in Zabbix across 5 dimensions every 15 minutes. This monitors the **GitHub repository**, not the running instance — it applies regardless of deployment target, but the Zabbix infrastructure runs on lotor.

For breetai-only deployments, ask the user if they want to set up fleet watchdog monitoring. For lotor deployments, always do it.

### 7a: Add to fleet-watchdog.py

Clone or pull `~/Projects/crunchtools/factory/` and edit `fleet-watchdog.py`:

1. Add `"mcp-<name>"` to the `REPOS` list (alphabetical order)
2. Add `"mcp-<name>"` to the `MCP_REPOS` list (alphabetical order)
3. Commit and push

### 7b: Create Zabbix Trapper Items

Create trapper items on the `factory.crunchtools.com` host (hostid `10700`) for each monitoring dimension. All items are type `2` (Zabbix trapper).

**All repos get these items:**

| Item Name | Key | value_type |
|-----------|-----|------------|
| Fleet GHA mcp-\<name\> | `fleet.gha[mcp-<name>]` | 3 (unsigned int) |
| Fleet Constitution mcp-\<name\> | `fleet.constitution[mcp-<name>]` | 3 (unsigned int) |
| Fleet Constitution Violations mcp-\<name\> | `fleet.constitution.violations[mcp-<name>]` | 4 (text) |
| Fleet Issues mcp-\<name\> | `fleet.issues.open[mcp-<name>]` | 3 (unsigned int) |

**MCP repos also get these items:**

| Item Name | Key | value_type |
|-----------|-----|------------|
| Fleet Version Sync mcp-\<name\> | `fleet.version.sync[mcp-<name>]` | 3 (unsigned int) |
| Fleet Version mcp-\<name\> | `fleet.version[mcp-<name>]` | 4 (text) |
| Fleet Artifact Sync mcp-\<name\> | `fleet.artifact.sync[mcp-<name>]` | 3 (unsigned int) |

Use the `mcp__zabbix__item_create` tool. If the Zabbix MCP server is in read-only mode, tell the user to create the items manually via the Zabbix web UI.

### 7c: Create Zabbix Triggers

Create triggers on `factory.crunchtools.com` for the new repo:

| Trigger | Expression | Priority |
|---------|-----------|----------|
| GHA failure | `last(/factory.crunchtools.com/fleet.gha[mcp-<name>])=0` | 2 (WARNING) |
| Version desync | `last(/factory.crunchtools.com/fleet.version.sync[mcp-<name>])=0` | 4 (HIGH) |
| Artifact desync | `last(/factory.crunchtools.com/fleet.artifact.sync[mcp-<name>])=0` | 2 (WARNING) |
| Constitution violation | `last(/factory.crunchtools.com/fleet.constitution[mcp-<name>])=0` | 4 (HIGH) |

All triggers should have tags: `{"tag": "service", "value": "fleet-watchdog"}` and `{"tag": "repo", "value": "mcp-<name>"}`.

### 7d: Deploy Updated Watchdog

On lotor, pull the updated factory container and restart:

```bash
podman pull quay.io/crunchtools/factory:latest
systemctl --user restart factory.crunchtools.com.service
```

Verify the new repo appears in the next watchdog run by checking the container logs.

### 7e: Service Tree (Factory Dashboard)

The fleet watchdog items must also appear in service-tree.php under the `factory.crunchtools.com` section. SSH to lotor and edit `/srv/zabbix.crunchtools.com/code/service-tree.php`:

1. Add the `fleet.gha[mcp-<name>]` item to the factory GHA status display section
2. Add the `fleet.version.sync[mcp-<name>]` item to the version sync display section
3. Add the `fleet.artifact.sync[mcp-<name>]` item to the artifact sync display section
4. Add the `fleet.constitution[mcp-<name>]` item to the constitution display section
5. Add the `fleet.issues.open[mcp-<name>]` item to the issues display section
6. Verify the new repo appears under factory.crunchtools.com at `https://zabbix.crunchtools.com/service-tree.php`

---

## Phase 8: Update MCP Architecture Doc

Update `~/Projects/MCP_ARCHITECTURE.md`:
- Add the server to the port allocation table (lotor) or stdio table (breetai)
- Update the version table
- Update the total server count and tool count

---

## Phase 9: Store in Memory

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
Fleet Watchdog: <factory.crunchtools.com (10700) or n/a>
Service Tree:   <both lotor + factory sections or n/a>
```
