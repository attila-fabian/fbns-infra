# NetBird: clients on family devices

Goal: reach the `10.2.0.0/24` estate (NAS, Proxmox, Fedora, Home Assistant) from the laptop and phone
from anywhere, without opening router ports.

Account: NetBird Cloud (`app.netbird.io`), login `attila.fabian@live.com`. No self-hosted management.

Rules for the executing agent:

1. The user runs every `sudo` and GUI step by hand.
2. Skip steps already done. Stop and ask if anything differs from this plan.
3. Setup keys and PATs go to Windows Credential Manager, never into this repo.

## Design

Two kinds of peer:

- **Client peers** run the NetBird app and log in with SSO: laptop, phone, Fedora.
- **One routing peer** inside the LAN advertises `10.2.0.0/24` as a NetBird Network. Devices that
  cannot run a client (Fibaro, UniFi gear, printers) or should not (NAS, Proxmox host, Home
  Assistant) stay untouched and are reached through it.

No client on the Synology NAS, the Proxmox host or Home Assistant: the routing peer covers them, and
each extra client is one more root daemon to patch. Add one only if a device must be reachable when
the LAN routing peer is down.

If a Synology NAS ever needs its own client, NetBird's documented method is SSH plus
`curl -fsSL https://pkgs.netbird.io/install.sh | sudo sh`, then `netbird up --setup-key <SETUP KEY>`.
Add a DSM Task Scheduler boot task (user `root`, event Boot-up) because some models lose the `tun`
module on reboot:

```sh
if [ ! -c /dev/net/tun ]; then
  mkdir -p -m 755 /dev/net
  mknod /dev/net/tun c 10 200
  chmod 0755 /dev/net/tun
fi
lsmod | grep -q '^tun ' || insmod /lib/modules/tun.ko
```

Some Synology kernels lack netfilter `mark` and `ipset`. The client then logs `failed to create
native firewall` and falls back to userspace filtering. Update with `./install.sh --update`, not
DSM.

Routing peer host: a small Debian LXC on Proxmox (`netbird-gw`). It is always on and keeps the VPN
off the Fedora YOLO box, which should not be the gateway into the LAN.

## Steps

### Step 1: Dashboard baseline

1. ⏳ Log in to `app.netbird.io`. Under **Settings**, check that peer login expiration is on for user
   peers.
2. ⏳ Keep the default `All -> All` policy. No groups, no access restrictions: every peer is a family
   device or server.

### Step 2: Laptop (Windows 11)

1. ✅ `winget install NetBird.NetBird`.
2. ✅ Tray icon, **Connect**, SSO login.

**Done when:** `netbird status` shows `Management: Connected` and `Signal: Connected`.

✅ 2026-10-19: client `0.81.3`, peer `attila-asusb9406.netbird.cloud`, NetBird IP `100.110.144.43`,
session expires 2026-11-18. The CLI is `C:\Program Files\Netbird\netbird.exe`; shells opened
before the install do not have it on `PATH`.

### Step 3: Phone

1. ⏳ Install NetBird from the App Store or Google Play.
2. ⏳ Log in with SSO.

### Step 4: Fedora

The routing peer already reaches Fedora at `10.2.0.51`. Its own client keeps SSH working when
Proxmox or `netbird-gw` is down.

Use the official DNF repo, not `install.sh`: `dnf upgrade` then keeps the client current. Use a
setup key, not SSO: setup-key peers have no login expiry, so the headless box does not drop off
every 30 days.

1. ⏳ Dashboard, **Setup Keys**: create a one-off key, expiry 1 day.
2. ⏳ User runs on Fedora:

   ```bash
   sudo tee /etc/yum.repos.d/netbird.repo <<'EOF'
   [netbird]
   name=netbird
   baseurl=https://pkgs.netbird.io/yum/
   enabled=1
   gpgcheck=1
   gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
   repo_gpgcheck=1
   EOF
   sudo dnf install -y netbird
   sudo systemctl enable --now netbird || { sudo netbird service install && sudo netbird service start; }
   sudo netbird up --setup-key <SETUP KEY>
   netbird status
   ```

Do not touch `overpass.service` or the firewalld `12345` rule.

**Done when:** `ssh` to Fedora works over its NetBird IP (`100.x.y.z`) from the laptop.

### Step 5: Routing peer

1. ⏳ Proxmox: create an unprivileged Debian 13 LXC `netbird-gw` (Debian 12 if the Proxmox version
   has no Debian 13 template), 1 vCPU, 512 MiB RAM, static IP in `10.2.0.0/24`. Give it
   `/dev/net/tun`: **Resources**, **Add**, **Device Passthrough**, path `/dev/net/tun`. This is
   the line `dev0: /dev/net/tun` in `/etc/pve/lxc/<id>.conf` (Proxmox 8.1 or later).
2. ⏳ Dashboard: create a one-off setup key, expiry 1 day.
3. ⏳ In the LXC:

   ```bash
   apt install -y curl
   curl -fsSL https://pkgs.netbird.io/install.sh | sh
   netbird up --setup-key <SETUP KEY>
   ```

4. ⏳ Dashboard, **Networks**: create network `fbns-lan`, resource `10.2.0.0/24`, routing peer
   `netbird-gw`, masquerade on. `All -> All` does not cover Network resources: accept the
   wizard's policy, source `All`, destination the `10.2.0.0/24` resource, all ports.

No NetBird DNS: use IPs. A match domain `local` would collide with mDNS, and the LAN DNS has no
`fedora` entry anyway.

**Done when:** with phone Wi-Fi off, the phone opens DSM at `https://10.2.0.6`.

### Step 6: At-home check

With the laptop on home Wi-Fi, run `tracert 10.2.0.6`. Traffic must go direct, not through
`netbird-gw`. If it goes through the tunnel, note it in `infra.md` and decide whether to accept it.

### Step 7: Record

⏳ Add a `## NetBird` section to [infra.md](../reference/infra.md): peers, NetBird IPs, network. Retire the UniFi VPN fallback in
[261012-fedora-agent-setup.md](261012-fedora-agent-setup.md) once NetBird has run for a few weeks.

## Agent skill and MCP

Reviewed 2026-10-19.

- **No official NetBird Agent Skill.** No `SKILL.md` in the `netbirdio` GitHub org, no `llms.txt`
  on `docs.netbird.io`.
- **Official MCP server: prototype only.** [`netbirdio/netbird-mcp`](https://github.com/netbirdio/netbird-mcp)
  (v0.1.0, last push 2026-07-24, 6 stars). Read tools for peers, groups, policies, networks, DNS,
  events. Writes use draft-then-confirm; deletes need `NETBIRD_ENABLE_DESTRUCTIVE=true`. Auth by
  PAT. Its `LAUNCH.md` is a roadmap to an official Claude connector, not a release. `@netbird/mcp`
  is not on npm yet, so the README's `npx` command fails: install means clone and build.
- **Community:** [`aantti/mcp-netbird`](https://github.com/aantti/mcp-netbird), read-only, still in
  development.

Decision: ⏭️ skip MCP for now. Four peers and one network are quicker in the dashboard. Revisit
when `@netbird/mcp` is published or the Claude connector ships. If adopted: service user with a PAT
stored in Windows Credential Manager, destructive tools off.
