---
name: unifi-connect
description: >-
  Use when an agent talks to the FBNS UniFi gateway, or when API calls to it are
  failing: 401 on a working key, empty firewall or device lists, a documented
  endpoint that 404s, "connect to UniFi", "talk to my UniFi controller", "run
  udm". Covers API-key auth through scripts/unifi/udm.ps1, which endpoint
  families exist, the endpoint map, and the safety doctrine: dry-run, read-only
  mode, snapshot-before-mutate rollback, and the audit trail. Start here: the
  other skills assume this one. Not for firewall policy (unifi-firewall), Wi-Fi
  and radios (unifi-wifi), client and port operations (unifi-clients).
compatibility: >-
  UniFi OS gateways running a self-hosted Network controller. Verified on
  UniFi OS 5.1.19 / Network 10.4.57. Endpoint paths and auth behavior are
  version-sensitive; confirm against your own controller.
---

# UniFi Connect

The first thing to know: **SSH is usually closed and you do not need it.** UniFi
OS exposes a full REST API on the same host as the web UI, and everything these
skills do goes through it.

Throughout, `<UDM_HOST>` is the gateway's LAN address. Never hardcode it into a
file you might share.

## Reads vs writes

Reads and writes both go through **`scripts/unifi/udm.ps1`**, which wraps
`scripts/udm.py` in this skill. Read-only unless `--write` is passed.

## Auth: API key

Only the API key is used. The key lives in Windows Credential Manager, target
`unifi-api` (user = gateway host, password = key). `udm.ps1` injects it into its
own process environment, so the agent sees command output, never the key:

```powershell
cmdkey /generic:unifi-api /user:<UDM_HOST> /pass     # prompts for the key, one-time
pwsh -File scripts\unifi\udm.ps1 status
```

Never print, echo, or `cat` the key. See `docs/reference/unifi-secrets-hygiene.md`.

**The key is as strong as the account that minted it.** A key minted by an admin
inherits that account's rights across every UniFi application on the box, not
just Network. There is no "read-only Network" key. Treat it as that account's
password. Existing keys, with their `permissions` map:

```powershell
pwsh -File scripts\unifi\udm.ps1 raw GET /proxy/users/api/v2/user/self/keys
```

### What a key can reach

| Surface | Base path | API key? |
|---|---|:---:|
| Network, legacy | `/proxy/network/api/s/default/...` | yes |
| Network, v2 | `/proxy/network/v2/api/site/default/...` | yes |
| UniFi OS system | `/api/system` | yes |

Self-signed cert on the gateway is normal; `udm.py` skips verification.

## Endpoint map

### UniFi OS level, `https://<UDM_HOST>/api/`

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `system` | OS version, storage, location |

`GET /api/users` **404s** on current UniFi OS; it was removed. There is no known
OS-level user-list endpoint. If a doc or an older skill tells you to call it,
that doc predates the change.

### Network controller, `https://<UDM_HOST>/proxy/network/api/s/default/`

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `stat/sysinfo` | Controller version, uptime |
| GET | `stat/health` | Subsystem health summary |
| GET | `stat/device` | Adopted devices: APs, switches, gateway |
| GET | `stat/sta` | Currently connected clients |
| GET | `stat/alluser` | All known clients including offline |
| GET | `rest/networkconf` | Networks and VLANs |
| GET | `rest/wlanconf` | Wi-Fi SSIDs |
| GET | `rest/user` | Known clients, including fixed-IP reservations |
| GET | `rest/portforward` | Port forwarding rules |
| GET | `rest/routing` | Static routes |
| GET | `rest/alarm` | Unresolved alarms |
| GET | `stat/sitedpi?type=by_app` | DPI traffic breakdown |
| POST | `cmd/stamgr` | Client ops: block, unblock, kick, forget |
| POST | `cmd/devmgr` | Device ops: restart, provision, power-cycle, speedtest |
| POST | `cmd/evtmgr` | Alarm archiving |

`rest/firewallrule` still exists and, on a zone-based-firewall controller,
**returns an empty list**. That does not mean you have no firewall. See
`unifi-firewall`.

### Network controller v2, `https://<UDM_HOST>/proxy/network/v2/api/site/default/`

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `firewall-policies` | Zone-based firewall policies |
| GET | `firewall/zone` | Firewall zones, **singular**, `zones` 404s |
| POST | `system-log/all` | System log, body `{"pageSize":100,"pageNumber":0}` |

Legacy `stat/event` **404s** on Network 10.4. Events live at the v2 system-log
endpoint now, and it is a POST with a pagination body, not a GET.

**v2 PUTs may return HTTP 201 rather than 200. That is success.** Do not retry on
201, and do not treat it as a redirect.

## The helper script

`scripts/udm.py` wraps the above. Standard library only, no dependencies. Run it
through `scripts/unifi/udm.ps1`, never directly: the wrapper supplies host and key
from Credential Manager and sets `UNIFI_READONLY=1` unless `--write` is passed.

```powershell
pwsh -File scripts\unifi\udm.ps1                 # command list
pwsh -File scripts\unifi\udm.ps1 devices         # adopted devices
pwsh -File scripts\unifi\udm.ps1 clients --json  # compact output for piping
```

The other UniFi skills write examples as `udm <command>`. Read that as
`pwsh -File scripts\unifi\udm.ps1 <command>`, adding `--write` for mutations.

Commands: `status`, `clients` (+ `--all` / `block` / `unblock` / `kick`),
`devices` (+ `restart` / `provision` / `power-cycle <switch-mac> <port>`),
`networks`, `wlans`, `policies`, `zones`, `portforward`, `reservations`,
`events`, `alarms`, `dpi`, `raw <METHOD> <path> ['<json>']`.

`raw` is the escape hatch: any path on the gateway, any method, so you are never
blocked waiting for the script to grow a subcommand.

### Two brakes, because this script can take your network down

`block`, `kick`, `restart`, `power-cycle` and `raw PUT` are all one typo away from
cutting off the thing you are typing on. Both brakes are enforced inside the single
request function, so `raw` gets them too:

```powershell
pwsh -File scripts\unifi\udm.ps1 devices restart <mac> --write --dry-run  # prints the request, sends nothing
pwsh -File scripts\unifi\udm.ps1 devices restart <mac>                    # no --write: UNIFI_READONLY=1, refused
```

`--dry-run` prints the method, URL and body it *would* have sent. `UNIFI_READONLY`
hard-fails instead, and `udm.ps1` sets it unless `--write` is passed. Run the
`--dry-run` form first for every write.

**Writes are classified by HTTP method, not by command name.** Anything that is not
a GET counts as a write unless its call site explicitly opts out, so a mutation
cannot sneak in later by riding along on a new subcommand. Only the v2 system-log
queries opt out, because they are POST-based reads. `events` keeps working under
`UNIFI_READONLY=1`, and that is the one case worth knowing about if you add a
POST-based read of your own.

## Snapshot before you mutate, because the controller has no undo

Dry-run tells you what you are about to do. It does not give you a way back once
you have done it. The way back is the object you are about to replace, saved
before the write:

```bash
mkdir -p ~/udm-snapshots
pwsh -File scripts/unifi/udm.ps1 raw GET /proxy/network/api/s/default/rest/user/<id> \
  | tee ~/udm-snapshots/$(date +%Y%m%dT%H%M%S)-user-<id>.json
```

Rollback is then the same full-object PUT you were already doing, with the
snapshot as the body. This works precisely *because* of the full-object PUT
discipline: the snapshot is the complete prior state, not a diff.

Three things this cannot roll back, so know them before you need them:

- **`cmd/*` actions.** A restart, kick, or power-cycle is an event, not state.
  There is nothing to PUT back.
- **Deletes.** Re-creating a deleted object gets a new `_id`, and anything that
  referenced the old id (a policy, a reservation) still points at the corpse.
  Snapshot the referrers too before deleting anything they name.
- **Cascades.** Deleting a network can take its DHCP scope and zone membership
  with it. The snapshot of the network object alone does not capture what the
  controller cleaned up around it.

## Keep an audit trail

One append-only line per mutating call: when, what, and which snapshot escapes
it. Cheap enough that there is no excuse:

```bash
echo "$(date -u +%FT%TZ) PUT rest/user/<id> pre=20260822T141530-user-<id>.json reason=fix-vlan" \
  >> ~/udm-snapshots/audit.log
```

This pairs with minting the agent its own named key: the controller tells you
*which identity* wrote a policy, the audit log tells you *why*, and the snapshot
gives you the way back. When something appears on the network that nobody admits
to, those three answer it in under a minute. The MCP crowd builds this into the
server ([mcp-unifi](https://github.com/pete-builds/mcp-unifi) logs every call as
JSONL with secrets scrubbed, a design worth copying); `udm.ps1` writes go
unlogged, so you write the line yourself.

## Read before write, always

Every skill here assumes it, so it belongs in the foundation:

1. **GET the object first.** Most `rest/*` endpoints want the whole object back
   on PUT. Partial PUTs silently drop the fields you omitted. See
   `unifi-clients`.
2. **Verify from a fresh read, not the PUT echo.** The controller will happily
   echo back a config it did not operationally apply. Two documented cases live
   in `unifi-wifi` (radio channel, and in-wall AP port VLAN).
3. **Know your out-of-band path before touching firewall or DHCP.** You are
   configuring the device that carries your management traffic.

## Version drift

Everything here was verified on **UniFi OS 5.1.19 / Network 10.4.57** in mid-2026.
Ubiquiti moves endpoints between versions with no deprecation notice: `stat/event`
died, `/api/users` died, and the whole firewall model changed. Treat this map as
a strong prior, not gospel.

Check what you are actually running before trusting any of it: MCP
`get_system_info`, or:

```powershell
pwsh -File scripts\unifi\udm.ps1 status
```

When a documented endpoint 404s, it moved. Look for a v2 equivalent first: that
has been the direction of travel for every migration so far.
