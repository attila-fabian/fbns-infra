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

- **Docker without `sudo`.** DSM group `docker` has one member, `Attila Fabian`. `dockerd` gives
  `/var/run/docker.sock` to that group at every start (`root:docker`, mode `660`). ⚠️ This makes the
  `FBNS NAS SSH` key passwordless root on the NAS.
- Run `ssh fbns '/usr/local/bin/docker ...'`. Use the full path, because `/usr/local/bin` is not on
  the non-interactive `PATH`. From Git Bash, prefix the command with `MSYS_NO_PATHCONV=1`. Without it,
  Git Bash rewrites `/usr/...` into a Windows path.

## FBNSBK NAS

Synology DS224+ in Slovakia. Off-site backup target, and the host that runs Active Backup for
Microsoft 365 against `e29.eu` (e29-infra `docs/reference/services.md` → Synology NAS).

| | |
|---|---|
| Host | `10.5.0.5`, reached over Tailscale only |
| SSH | `ssh fbnsbk`, port `22`, user `Attila Fabian`, key from the Bitwarden SSH agent (item `FBNSBK NAS SSH`) |
| DSM | `https://10.5.0.5:5791`, same login as FBNS |

- **SSH keys live outside home**, same as E29HU. The user home service is off, so `sshd_config`
  line 1 is `AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/keys/%u`. The key file is
  `/etc/ssh/keys/Attila Fabian`, root-owned `644` in a `755` dir, because sshd reads it as the
  user. Every login prints `Could not chdir to home directory`; ignore it.
- A DSM update may reset `/etc`. Password login still works then; re-add the line and the file.
- The user must be in DSM `administrators` to log in. Password login is still on. Never forward port
  `22` from the router.

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
