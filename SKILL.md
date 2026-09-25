---
name: deploy-mcp-server
description: Deploy a CrunchTools MCP server to breetai (laptop) or lotor (web server) with monitoring
argument-hint: "<server-name, e.g. airlock, gemini, gitlab>"
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Grep, Glob, Agent, mcp__trentina__memory__memory_search, mcp__trentina__memory__memory_store, mcp__trentina__nagios__nagios_host_status_tool, mcp__trentina__nagios__nagios_service_status_tool
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
- `memory_search` for the server name (port, env vars, tool count). Port allocation comes from Nagios, not memory (Step 3)
- `memory_search` for "lotor infrastructure" or "breetai" for host context

### Step 2: Select Target Host

Ask the user with `AskUserQuestion`:

| Host | Type | When to Use |
|------|------|-------------|
| **lotor** | Production web server | Containerized, systemd-managed, Nagios-monitored, always-on |
| **breetai** | Interactive laptop | Development, testing, or stdio-only servers |

The target determines which phases apply:

| Phase | lotor | breetai |
|-------|-------|---------|
| Environment Setup | yes | yes |
| Container Deployment | yes | no |
| Claude Code Configuration | yes (HTTP) | yes (stdio or HTTP) |
| Verification | yes | yes |
| Nagios Monitoring | yes | no |

### Step 3: Confirm Details

Confirm with the user:
- **Server name** (e.g., `mcp-airlock`)
- **HTTP port** — Nagios is the port registry: take the next port above the highest `check_tcp_<port>` in `crunchtools/nagios-agent` `deploy/nagios-agent/nrpe-host.cfg`, and confirm it is free with `ssh lotor ss -ltn`
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

## Phase 6: Nagios Monitoring (lotor only)

Skip this phase for breetai deployments.

All MCP servers on lotor get three Nagios checks: container running, container memory, and a TCP port check. All run through the NRPE agent, because MCP ports are loopback-only on lotor. Nagios config is file-based — the same files `/decommission` removes entries from, edited in reverse here.

Placeholders below: the container is `mcp-<name>` (`<name>` lowercase, hyphens, exactly as in the container name); `<PORT>` is the integer port chosen in Phase 1.

### 6a: NRPE Commands (agent side)

Add the commands in `crunchtools/nagios-agent` (source of truth) and copy them to `/srv/nagios-agent.crunchtools.com/config/` on lotor, copying an existing `mcp-*` entry and changing only the name and port:
- `deploy/nagios-agent/nrpe-host.cfg` (fast pool, :5666): `check_tcp_<PORT>`
- `deploy/nagios-agent/nrpe-ctr.cfg` (container pool, :5667): `check_ctr_run_mcp_<name>` and `check_ctr_mem_mcp_<name>`

```
command[check_tcp_<PORT>]=/usr/local/nagios/libexec/check_tcp_local.sh <PORT>
command[check_ctr_run_mcp_<name>]=/usr/local/nagios/libexec/check_container_running.sh mcp-<name>
command[check_ctr_mem_mcp_<name>]=/usr/local/nagios/libexec/check_container_memory.sh mcp-<name> 85 95
```

### 6b: Service Definitions (server side)

In `/srv/nagios.crunchtools.com/config/services/container-hosts.cfg`, add the host and its `Container memory` and `MCP port` services, and add the host to the `mcp-services` hostgroup members. The `MCP port` service is what marks the port taken for the next deploy.

```
define host {
    use                 crunchtools-mcp-container
    host_name           ctr-mcp-<name>.crunchtools.com
    alias               mcp-<name> container
    address             10.88.0.1
    check_command       check_nrpe_ctr!10.88.0.1!check_ctr_run_mcp_<name>
}
define service {
    use                 crunchtools-service
    host_name           ctr-mcp-<name>.crunchtools.com
    service_description Container memory
    check_command       check_nrpe_ctr!10.88.0.1!check_ctr_mem_mcp_<name>
}
define service {
    use                 crunchtools-service
    host_name           ctr-mcp-<name>.crunchtools.com
    service_description MCP port
    check_command       check_nrpe_command!10.88.0.1!check_tcp_<PORT>
}
```

### 6c: Validate and Restart

```bash
ssh lotor "systemctl restart nagios-agent.crunchtools.com nagios-agent-ctr.crunchtools.com"
ssh lotor "podman exec nagios.crunchtools.com /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg && systemctl restart nagios.crunchtools.com"
```

NRPE reads its config only at start, so the agents restart first (this trips the agents' cross-watch restart checks; that is expected). `nagios -v` runs in the container and `systemctl` on the lotor host; the `&&` means a failed validation never restarts Nagios (it would not come back up). On failure, fix the file and line it names and re-run. If a check stays red after two cycles, run its NRPE command by hand (`ssh lotor "podman exec nagios.crunchtools.com /usr/lib64/nagios/plugins/check_nrpe -H 10.88.0.1 -p 5666 -c check_tcp_<PORT>"`; container checks use port 5667) to see the raw output.

### 6d: Verify Checks

Use `nagios_service_status_tool` to confirm the new checks appear and go green (the first check cycle can take a couple of minutes). `nagios_host_status_tool` confirms lotor itself is still OK.

**Gate:** do not proceed to Phase 7 until the host and both services are OK.

---

## Phase 7: Store in Memory

Store the deployment details using `memory_store`:
- Target host (breetai or lotor)
- Port number and transport type
- systemd service name (if lotor)
- Nagios checks added
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
Monitoring:     <Nagios host/service checks added, or n/a>
```
