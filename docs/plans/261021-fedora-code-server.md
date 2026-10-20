# Fedora: VS Code in the browser for LAN and phone

Goal: open and edit every repo in `~/projects` on `fedora` in a browser, with a working terminal
(`git`, `gh`, Node 24, `claude`):

- **LAN:** `https://code.fbns.eu` and `https://vscode.fbns.eu`, through NAS Traefik.
- **On the go (Samsung Fold8):** `http://fedora.netbird.cloud:8080`, over NetBird.

The code-server container on the FBNS NAS goes away; both names point to Fedora.

Box: `ssh fedora` (`10.2.0.51`, NetBird `100.110.35.178`). Details:
[infra.md → Fedora](../reference/infra.md#fedora). Related: [Fedora agent setup](261012-fedora-agent-setup.md).

**Do not touch `overpass.service` or `gh-runner.service`.** The user runs every `sudo` step by hand.

## Decisions

**Fedora, not the FBNS NAS.** The code-server terminal runs on the host that runs code-server. On
the NAS that is a container with no Node 24, `gh`, `claude` or Podman. Reaching `~/projects` from
the NAS would need an NFS or SSHFS mount, which makes `git` and `npm` slow and breaks file watchers.
Remote-SSH does not work in code-server.

**Native install, not a container.** Fedora runs rootless Podman, not Docker. A container would
have to mount `~/projects`, `~/.config/gh` and `~/.claude` to be useful, so it would isolate
nothing. Its terminal would also run inside the image, without the host's Node 24, `claude`,
`podman` or `tmux`. The standalone install needs no `sudo` and runs as a user unit like the rest of
the box.

**HTTPS on the LAN through NAS Traefik.** Traefik already holds the `*.fbns.eu` wildcard
certificate. A file route sends both names to `http://10.2.0.51:8080`. The route uses `lan-only`,
not `secured`: the `secure-headers` part sets `frameDeny`, and code-server shows webviews (Markdown
preview, extension views) in iframes.

**Plain HTTP over NetBird.** The NAS is not a NetBird peer yet, so the phone cannot use Traefik
when away. NetBird WireGuard already encrypts phone to box. A Chrome flag on the phone gives the
secure context that webviews and the clipboard need. A certificate on Fedora itself would need a
Cloudflare DNS token on the agent box, which breaks its "no secrets" rule.

**Firewall gates the port.** code-server listens on `0.0.0.0:8080`. firewalld lets in only Traefik
(`10.2.0.20`) and NetBird peers (`100.64.0.0/10`). Other LAN devices must use the Traefik names.
`wt0` has no firewalld zone (checked 2026-10-21), so NetBird traffic falls into the default zone
`FedoraServer` and needs the rule too.

## Safety

code-server is a password-protected shell on the box: same access as `ssh fedora`. The NetBird
policy is still `All -> All`, so the NAS peers (`fbnsbk`, `e29hu`, `e29pt`) can reach the port;
password auth covers that. Tightening the policy belongs to the
[security baseline](../backlog/261021-security-baseline.md).

## Steps

✅ **1. Check the box.** 2026-10-21: nothing on `8080`, no code-server installed, `wt0` in no zone.
LAN DNS already resolves `code.fbns.eu` and `vscode.fbns.eu` to Traefik `10.2.0.20`.

⏳ **2. Install code-server.** Standalone method, no `sudo`, into `~/.local/lib` and
`~/.local/bin/code-server`:

```bash
curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone
```

Update later by running the same command again.

⏳ **3. Configure.** Run `code-server` once and stop it with Ctrl+C. The first start writes
`~/.config/code-server/config.yaml` with a random password. Change only `bind-addr`:

```yaml
bind-addr: 0.0.0.0:8080
auth: password
password: <generated>
cert: false
```

Never set `auth: none`: code-server is a shell on the box. Copy the password into Windows
Credential Manager as `fedora-code-server` (repo rule) and into Bitwarden as item
`fedora-code-server` with URIs `https://code.fbns.eu`, `https://vscode.fbns.eu` and
`http://fedora.netbird.cloud:8080`, so the phone autofills it. The file on the box stays the source;
after a password change, update both copies.

⏳ **4. User service.** `~/.config/systemd/user/code-server.service`:

```ini
[Unit]
Description=code-server

[Service]
ExecStart=%h/.local/bin/code-server %h/projects
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

Linger is already on, so the service starts at boot.

```bash
systemctl --user daemon-reload && systemctl --user enable --now code-server
```

⏳ **5. Firewall (user, `sudo`).**

```bash
sudo firewall-cmd --permanent --zone=FedoraServer \
  --add-rich-rule='rule family=ipv4 source address=10.2.0.20 port port=8080 protocol=tcp accept'
sudo firewall-cmd --permanent --zone=FedoraServer \
  --add-rich-rule='rule family=ipv4 source address=100.64.0.0/10 port port=8080 protocol=tcp accept'
sudo firewall-cmd --reload
```

Never forward `8080` from the router.

⏳ **6. Remove the NAS code-server.** Its only volume is `./data` (80M: settings, extensions,
`.claude`). Archive it to the NAS home folder, outside the `fbns-docker` repo (it holds
credentials), then stop and delete it:

```bash
ssh fbns 'cd /volume1/docker/code-server && tar czf ~/code-server-data-261021.tgz data \
  && /usr/local/bin/docker compose down'
```

Then delete `code-server/` in `fbns-docker` (`Y:\code-server`). This removes the
`code-server@docker` router for `code.fbns.eu`, so the file route in step 7 does not collide with it.

⏳ **7. Traefik route.** In `fbns-docker` `traefik/config/config.yml` (file provider, `watch: true`,
no restart needed), under `routers`:

```yaml
    code-server:
      rule: "Host(`code.fbns.eu`) || Host(`vscode.fbns.eu`)"
      entryPoints:
        - websecure
      tls: {}
      service: code-server
      middlewares:
        - lan-only
```

and under `services`:

```yaml
    code-server:
      loadBalancer:
        servers:
          - url: "http://10.2.0.51:8080"
```

Done when `https://code.fbns.eu` and `https://vscode.fbns.eu` open the login page from the laptop on
the LAN, with a valid certificate, and Markdown preview works.

⏳ **8. Phone.**

1. Install the NetBird app, log in with `attila.fabian@live.com`, connect.
2. In Chrome, open `chrome://flags/#unsafely-treat-insecure-origin-as-secure`, add
   `http://fedora.netbird.cloud:8080`, enable, relaunch.
3. Open `http://fedora.netbird.cloud:8080`, log in, then Chrome menu → **Add to home screen**.

Samsung Internet has no such flag; use Chrome. At home on Wi-Fi, `https://code.fbns.eu` works too.

Done when, from the phone on mobile data: the file tree shows `~/projects`, the terminal prints
`v24` for `node -v` and a version for `claude --version`, Markdown preview opens, and paste into the
editor works.

⏳ **9. Update [infra.md](../reference/infra.md).** Add a `code-server` subsection under Fedora:
URLs, config path, unit name, firewall rules, Credential Manager target, update command.

## Rollback

```bash
systemctl --user disable --now code-server
rm -rf ~/.config/systemd/user/code-server.service ~/.config/code-server \
  ~/.local/share/code-server ~/.local/lib/code-server-* ~/.local/bin/code-server
sudo firewall-cmd --permanent --zone=FedoraServer \
  --remove-rich-rule='rule family=ipv4 source address=10.2.0.20 port port=8080 protocol=tcp accept'
sudo firewall-cmd --permanent --zone=FedoraServer \
  --remove-rich-rule='rule family=ipv4 source address=100.64.0.0/10 port port=8080 protocol=tcp accept'
sudo firewall-cmd --reload
```

Then remove the `code-server` router and service from `traefik/config/config.yml`. To bring the NAS
container back, restore `code-server/` from `fbns-docker` git history, unpack `~/code-server-data-261021.tgz` on the NAS into it and run
`docker compose up -d`.

Skipped: HTTPS over NetBird. Add it with the LAN routing peer `netbird-gw` (NetBird rollout): a
route to `10.2.0.0/24` plus a NetBird nameserver group `fbns.eu` → `10.2.0.22` lets the phone use
`https://code.fbns.eu` from anywhere, and the Chrome flag can go. The NAS as a plain peer is not
enough: Traefik sits on macvlan `10.2.0.20`, which the NAS host itself cannot reach.
