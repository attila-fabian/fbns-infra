# Fedora box: run Claude agents in YOLO mode

Goal: run `claude --dangerously-skip-permissions` on `fedora`, reachable from laptop and phone, with
no write path to anything that matters.

Box: `ssh fedora` (`10.2.0.51`, user `attilafabian`), repos in `~/projects`. Details:
[infra.md → Fedora](../reference/infra.md#fedora).

**Do not touch `overpass.service` or its port `12345` rule.** The box runs the paddle-map Overpass API.

Rules for the executing agent: the user runs every `sudo` step by hand. Stop and ask if the box
differs from this plan.

## Safety

The box has no NAS mounts or credentials, no private SSH keys, no secrets in env and no MCP servers
(checked 2026-10-17). It cannot reach anything that matters except GitHub.

GitHub is open by choice: the `gh` token keeps scopes `repo`, `workflow`, `read:org`, `gist`, and
`main` is not protected. Accepted risk: prompt injection from issues, PRs, web pages or docs can
steer the agent to push or force-push to `main`, or to change Actions workflows and expose repo
secrets. Git history and GitHub are the only recovery path.

## Steps

✅ **1. Check the box.** Clean, see Safety.

⏭️ **2. Remove write paths.** Nothing to remove.

⏳ **3. Persistent session.** `tmux` is installed. From the laptop:

```bash
ssh -t fedora tmux new -A -s claude
# inside tmux:
cd ~/projects/<repo> && claude --dangerously-skip-permissions
```

Done when `git push` works from the box and the same `ssh` command reattaches the session.

⏳ **4. Phone via Remote Control.** In the Claude session run `/remote-control`, open it in the
Claude app, and send a prompt that runs a harmless command. Done when it runs without a permission
prompt.

⏳ **5. Phone via ConnectBot (fallback).** Generate a key in ConnectBot's pubkey manager and add it
to `~/.ssh/authorized_keys`. Add one Mosh host per path, each with post-login automation
`tmux new -A -s claude`:

| Path | Host |
| --- | --- |
| LAN or UniFi VPN | `attilafabian@10.2.0.51` |
| NetBird | `attilafabian@fedora.netbird.cloud` (`100.110.35.178`) |

- Mosh survives Wi-Fi/4G switches and sleep. `mosh` is installed. It needs UDP `60000-61000` open
  in zone `FedoraServer`. NetBird `wt0` has no zone (checked 2026-10-21), so its traffic falls into
  the default zone `FedoraServer` and the same rule covers LAN, UniFi VPN and NetBird:

  ```bash
  sudo firewall-cmd --permanent --zone=FedoraServer --add-service=mosh && sudo firewall-cmd --reload
  ```

- NetBird has no LAN routing peer, so `10.2.0.51` does not work over NetBird. Install the NetBird
  app on the phone and log in first.

Done when a Mosh session reattaches the tmux session and survives a Wi-Fi to 4G switch.
