# fbns-infra - family infra management

Management workspace for the Fabian home/office estate: `10.2.0.0/24` network, both FBNS Synology
NAS, Proxmox node, Fedora workstation, Docker services on `*.fbns.eu`, Home Assistant, Fibaro
controllers. Estate map: [infra.md](docs/reference/infra.md).

Operated **from here**: read, write, create, delete. No application code, no IaC, no service
configuration: compose files live in `fbns-docker`.

Store passwords and secrets in Windows Credential Manager, SSH keys in Bitwarden . Credential
Manager target name: `<system>-<purpose>`.

Name new files in `docs/plans/` and `docs/backlog/` `YYMMDD-<slug>.md`.

## Minimalism

Read the target and its live state first. Then stop at the first rung that holds:

1. Needed at all? Speculative need = skip it, say so in one line.
2. Already exists? Reuse a script in `scripts/`, a `unifi-*` skill, or a doc section.
3. Platform setting covers it? DSM, UniFi, Home Assistant built-in over a custom script.
4. Existing tool does it? `ssh`, `scripts/unifi/udm.ps1`, an MCP. No new script for a one-off command.
5. Only then: the smallest change that works.

- Fix the root cause, not the symptom.
- No speculative resources, settings or scaffolding "for later".
- Deletion over addition. Fewest files, shortest diff.
- Never simplify away: security, access control, backups, anything explicitly requested.