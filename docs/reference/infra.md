# Infra

## FBNS NAS

Synology NAS. Docker host for `*.fbns.eu`.

| | |
|---|---|
| Host | `FBNS.local` · `10.2.0.6` |
| SSH | `ssh fbns`, port `22`, LAN only, user `Attila Fabian`, key from the Bitwarden SSH agent (item `FBNS NAS SSH`) |
| DSM | port `443` |
| Gitea SSH | port `2222` on the NAS IP (`gitea/compose.yaml` maps `2222:22`). Not the NAS shell |

- Key is in `~/.ssh/authorized_keys`, under the user home service (`/var/services/homes` →
  `/volume2/homes`). The user must be in DSM `administrators` to log in. sshd StrictModes needs home
  `755`, `.ssh` `700`, `authorized_keys` `600`.
- DSM `sshd_config` still has `PasswordAuthentication yes`. That is acceptable while port 22 is not
  forwarded from the router.

`Y:` = `\FBNS\docker` = `/volume1/docker` — same files over SMB and SSH.

- **Docker needs `sudo`.** `/var/run/docker.sock` is `root:root`; the user runs `sudo docker ...` on
  request. Agents read container state from Dozzle instead (`http://10.2.0.6:8888`, LAN, no auth,
  read-only). Container list from its SSE stream:

  ```bash
  python -c "
  import json,urllib.request
  for l in urllib.request.urlopen('http://10.2.0.6:8888/api/events/stream',timeout=5):
      if l.startswith(b'data: '):
          for c in sorted(json.loads(l[6:]),key=lambda c:c['name']): print(f\"{c['name']:26}{c['state']:10}{c['image']}\")
          break"
  ```

  Dockhand (`:3000`) has auth on and is not used by agents.

## Fedora

Headless Fedora 43 server on the LAN. Runs Claude Code sessions, dev work and the paddle-map Overpass API.

| | |
|---|---|
| Host | `fedora` · `fedora.local` (mDNS) · `10.2.0.51` (DHCP reservation on the UniFi router) |
| SSH | `ssh fedora`, user `attilafabian`, key from the Bitwarden SSH agent |
| Hardware | 24 CPUs, 92 GiB RAM |
| Disks | `/` xfs on LVM `fedora-root` (NVMe, holds `/home`) · `/data` btrfs, second NVMe, unused |
| Tools | rootless Podman, git, Node 24, `gh` (authenticated), Claude Code (`~/.local/bin/claude`); repos in `~/projects` |

- **SSH from Windows needs Windows OpenSSH.** Git Bash's own `ssh` cannot reach the Bitwarden agent
  pipe (`Permission denied (publickey)`), so `~/.bashrc` puts `/c/Windows/System32/OpenSSH` first on
  `PATH`. Shells that skip `.bashrc` must call `ssh.exe` by that path.
- `sudo` needs a password; run root steps by hand. Linger is on, so user services start at boot.
- **Node 24 sits beside the distro's Node 22.** `nodejs24` + `nodejs24-npm` ship `/usr/bin/node-24`,
  `npm-24`, `npx-24`; `/usr/bin/node` stays 22. Symlinks `~/.local/bin/{node,npm,npx}` → `*-24` make
  v24 the default for `attilafabian` (first on `PATH`). systemd units do not read that `PATH`: call
  `/usr/bin/node-24` there. Remove the symlinks to fall back to 22.
- firewalld zone `FedoraServer`. Only extra rule: TCP `12345` from `10.2.0.0/24`. Never forward it from
  the router.
- LAN DNS (`10.2.0.22`/`.23`) has no `fedora` entry — use `fedora.local` or the IP.
- ⏳ GitHub SSH from the box not set up (`git@github.com` host key unknown, no key).

### Overpass API

`http://fedora.local:12345/api/interpreter` — Overpass for paddle-map's `npm run data`. Quadlet
`~/.config/containers/systemd/overpass.container` (user unit `overpass.service`), database in
`~/overpass/db`, rebuilt by `~/overpass/refresh.sh` (service is down during a rebuild). Setup and
reasons: [paddle-map `docs/plans/260925-own-overpass.md`](../../../paddle-map/docs/plans/260925-own-overpass.md).
On the box use `127.0.0.1`, not `localhost` (rootless Podman forwards IPv4 only).

### GitHub Actions runner (E29eu)

User `gh-runner` (uid 1001, linger on, `ssh gh-runner@10.2.0.51` with the same key). Quadlet
`~/.config/containers/systemd/gh-runner.container` (user unit `gh-runner.service`) runs
`ghcr.io/actions/actions-runner`; `~/.config/gh-runner/start.sh` takes a one-job JIT config, so each
job gets a fresh container. PAT in `~/.config/gh-runner/runner.env` (mode 600).
`podman-auto-update.timer` keeps the image current. Setup and rollback:
[e29-infra `docs/plans/261017-fedora-actions-runner.md`](../../../e29-infra/docs/plans/261017-fedora-actions-runner.md).
