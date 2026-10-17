# Fedora box: run Claude agents in YOLO mode

Goal: run `claude --dangerously-skip-permissions` on `fedora`, reachable from laptop and phone, with
no write path to anything that matters.

Box: `ssh fedora` (`10.2.0.51`, user `attilafabian`), repos in `~/projects`. Details:
[infra.md → Fedora](../reference/infra.md#fedora).

**Do not touch `overpass.service` or its port `12345` rule.** The box runs the paddle-map Overpass API.

Safety comes from what the box can reach: no NAS access and no production MCP servers. GitHub is
open by choice: the `gh` token stays broad (`repo`, `workflow`) and `main` is not protected, so the
agent may edit anything on GitHub.

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

Findings (2026-10-17):

| Check | Result |
| --- | --- |
| ✅ NAS mounts | No CIFS or NFS mounts, no `fstab` entries. `fusectl` and `rpc_pipefs` are kernel pseudo-filesystems. |
| ✅ NAS credentials | No `~/.smbcredentials`, `~/.git-credentials` or `~/.netrc`. |
| ✅ SSH keys | `~/.ssh` holds only `authorized_keys` and `known_hosts`. No private keys, so the box cannot SSH out. The laptop's `Host fedora` entry has no `ForwardAgent`. |
| ✅ Secrets in env | Only `DEBUGINFOD_IMA_CERT_PATH`, a Fedora default. |
| ✅ MCP servers | None at user level, no `~/projects/*/.mcp.json`. |
| ✅ `~/.claude/settings.json` env | None. |
| ⏭️ `gh` token | OAuth `gho_` token, scopes `repo`, `workflow`, `read:org`, `gist`. `git` authenticates through `gh auth git-credential`. Kept broad by choice. |
| ✅ Tools | `tmux`, `gh` and `claude` installed. |

Risk accepted with the broad token: prompt injection from issues, PRs, web pages or dependency
docs can steer a YOLO agent, and the `workflow` scope can change Actions workflows and expose repo
secrets. No branch protection on `main`, so the agent can push or force-push straight to it. Git
history and GitHub are the only recovery path.

### Step 2: Remove write paths

⏭️ Nothing to do. Step 1 found no NAS mounts, credentials or MCP servers. The broad `gh` token and
the unprotected `main` stay by choice.

### Step 3: Persistent session

`tmux` is already installed. From the laptop:

```bash
ssh -t fedora tmux new -A -s claude
# inside tmux:
cd ~/projects/<repo> && claude --dangerously-skip-permissions
```

The session keeps running after you disconnect. The same `ssh` command reattaches it.

**Done when:** `git push` works from the box and the tmux session reattaches.

## Part 2: Mobile access

### Step 4: Remote Control

1. In the Claude session, run `/remote-control`.
2. Open the session in the Claude app on the phone.
3. Send a prompt that runs a harmless command. It must run without a permission prompt.

Fallback: UniFi VPN plus Termius (`ssh -t fedora tmux new -A -s claude`), with Termius's own key in
`~/.ssh/authorized_keys`.

**Done when:** the phone continues the same session and commands run without prompts.
