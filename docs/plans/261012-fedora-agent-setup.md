# Fedora box: run Claude agents in YOLO mode

Goal: run `claude --dangerously-skip-permissions` on `fedora`, reachable from laptop and phone, with
no write path to anything that matters.

Box: `ssh fedora` (`10.2.0.51`, user `attilafabian`), repos in `~/projects`. Details:
[infra.md → Fedora](../reference/infra.md#fedora).

**Do not touch `overpass.service` or its port `12345` rule.** The box runs the paddle-map Overpass API.

Safety comes from what the box can reach: no NAS access, no production MCP servers, a GitHub token
limited to the agent's repos, and a protected `main`.

Rules for the executing agent:

1. Step 1 is read-only. Report, then wait for approval.
2. The user runs every `sudo` step by hand.
3. Skip steps already done. Stop and ask if anything differs from this plan.

## Part 1: Dev environment

### Step 1: Check the box (read-only)

```bash
command -v tmux gh claude
mount | grep -Ei 'cifs|nfs|fuse' ; grep -Ei 'cifs|nfs' /etc/fstab
ls -la ~/.ssh ~/.config ~/.smbcredentials ~/.git-credentials ~/.netrc 2>/dev/null
env | grep -iE 'token|secret|key|pass' | sed 's/=.*/=<set>/'
claude mcp list
ls ~/projects/*/.mcp.json 2>/dev/null
gh auth status
git config --global --get-regexp 'credential'
grep -i env ~/.claude/settings.json 2>/dev/null
```

Report as a short table: NAS mounts and credentials, secrets, production MCP servers, `gh` token
scope.

### Step 2: Remove write paths

Propose each removal, the user decides:

- NAS mounts, fstab entries and credentials
- production MCP servers: `claude mcp remove <name>`
- broad `gh` token

Replace the `gh` token with a fine-grained PAT: only the agent's repos; Contents and Pull requests
read/write, Metadata read; nothing else. User runs on the box:

```bash
gh auth login --with-token < token.txt && rm token.txt
gh auth setup-git
```

On the laptop, check each repo:

```bash
gh api repos/<owner>/<repo>/branches/main/protection \
  --jq '{enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled}'
```

Expected: `enforce_admins: true`, `force_push: false`.

### Step 3: Persistent session

User runs: `sudo dnf install -y tmux`

Then from the laptop:

```bash
ssh -t fedora tmux new -A -s claude
# inside tmux:
cd ~/projects/<repo> && claude --dangerously-skip-permissions
```

The session keeps running after you disconnect. The same `ssh` command reattaches it.

**Done when:** no NAS mounts, no production MCP servers, `git push` to a feature branch works, and
the tmux session reattaches.

## Part 2: Mobile access

### Step 4: Remote Control

1. In the Claude session, run `/remote-control`.
2. Open the session in the Claude app on the phone.
3. Send a prompt that runs a harmless command. It must run without a permission prompt.

Fallback: UniFi VPN plus Termius (`ssh -t fedora tmux new -A -s claude`), with Termius's own key in
`~/.ssh/authorized_keys`.

**Done when:** the phone continues the same session and commands run without prompts.
