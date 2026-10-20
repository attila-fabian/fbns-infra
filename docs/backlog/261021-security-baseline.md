# Security baseline: family and E29 estate

Goal: protect what matters with simple, free tools. Admin access goes over one VPN overlay, public
content goes through Cloudflare, and no admin interface is reachable from the internet.

## What is exposed today (checked 2026-10-21)

- WAN `81.182.144.117`: TCP `443` → Traefik (`10.2.0.20`). TCP `5291`, `5295`, `5296` → E29HU
  (`10.2.0.32`, on the family LAN). `5291` serves the DSM / Drive login page.
- Public DNS: only `fbns.eu` and `p46.eu` resolve, both proxied by Cloudflare. `*.fbns.eu` service
  names resolve on the LAN only.
- Traefik: only the `traefik` router and the file routes in `traefik/config/config.yml` (DSM, HA,
  Proxmox, UniFi, Fibaro, Jellyfin, Drive, Photos) use the `secured` (LAN-only) middleware. Docker
  routes have no middleware: Dozzle, Gitea, Dockhand, code-server, Immich, Vaultwarden, pgadmin,
  adminer, AdGuard, Paperless, Open WebUI and the rest.
- ❌ Not verified: whether the UniFi `443` forward accepts only Cloudflare source IPs. If it accepts
  any source, a request to the WAN IP with `Host: dozzle.fbns.eu` reaches Dozzle (no auth, container
  logs) from the internet. The UniFi MCP failed with `getaddrinfo failed` during the check.

## What needs protection

| Asset | Risk | Protection |
|---|---|---|
| Accounts: `attila@e29.eu` (M365 admin), `attila.fabian@live.com`, GitHub, Cloudflare, Bitwarden master | Takeover of everything else | Passkeys or two hardware keys, break-glass M365 admin. E29 Conditional Access: e29-infra backlog F2 |
| FBNSBK | Holds the M365 backup certificate with tenant-takeover permissions; SSH key = root | e29-infra backlog F1 (trim to read-only), admin access over VPN only |
| NAS data (E29HU, FBNS) and backup targets (E29PT, FBNSBK) | Ransomware, deletion | Immutable snapshots on the backup targets, so an infected source cannot wipe them |
| Admin interfaces: DSM, Proxmox, UniFi, HA, Fibaro, Docker tools | Full control of house and NAS | LAN or NetBird only, never public |
| Vaultwarden `vault.e29.eu` (Azure, public) | All E29 passwords | Signups off, `/admin` off, 2FA required |
| Public by design: `p46.eu`, Photos and Drive share links | Leak, DSM attack surface | Only share pages public, behind Cloudflare, no DSM login on the internet |

## Approach

- **One VPN overlay: NetBird.** Admin and family devices on the free NetBird Cloud plan. Tailscale
  goes once NetBird is proven.
- **E29 network: second free NetBird Cloud account** rather than self-hosting. Same separation from
  the family network, no VM to patch and no Azure egress cost. Self-host only if E29 outgrows the
  free plan. Supersedes the server part of e29-infra `docs/plans/261020-netbird-e29.md`.
- **Traefik LAN-only by default.** Default middleware `secured@file` on the `websecure`
  entrypoint; public routes (`p46.eu`, `fbns.eu`) opt out.
- **Public shares through Cloudflare Tunnel** (`cloudflared` on the NAS, free) instead of port
  forwards.
- **Cloudflare Access** (free up to 50 users) for family or staff who need a web app without
  NetBird: email one-time code or Entra login in front of it.

## Steps

1. ⏳ From a phone on mobile data:
   `curl -I --resolve dozzle.fbns.eu:443:81.182.144.117 https://dozzle.fbns.eu/`. `200` = open to the
   internet.
2. ⏳ Traefik: `secured@file` as default middleware on `websecure` in `traefik/traefik.yml`
   (fbns-docker), exempt `p46.eu` and `fbns.eu`. Limit the UniFi `443` forward to Cloudflare IP
   ranges.
3. ⏳ e29-infra backlog F1: trim the FBNSBK M365 backup app to read-only.
4. ⏳ Immutable snapshots on E29PT and FBNSBK (DSM Snapshot Replication).
5. ⏳ Passkeys or hardware keys on all accounts in the table; break-glass M365 admin.
6. ⏳ `vault.e29.eu`: confirm signups off, `/admin` off, 2FA enforced.
7. ⏳ Cloudflare Tunnel and Access for Photos and Drive shares on new hostnames. Close `5291`,
   `5295`, `5296` once old links are moved; e29-infra `services.md` says both link bases must stay,
   so plan the link migration first.
8. ⏳ NetBird rollout (phone, FBNS NAS, routing peer), then remove Tailscale.
9. ⏳ Hygiene: DSM auto security updates, auto-block, firewall and admin 2FA on every NAS. UniFi
   IDS/IPS on.

Skipped: VLAN split of the family `10.2.0.0/24` (E29 NAS, IoT, family devices). Add when the steps
above are done.
