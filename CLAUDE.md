# fbns-infra — family infra management

Management workspace and index for the Fabian home/office estate: the `10.2.0.0/24` network, both
FBNS Synology NAS, the Proxmox node, the Fedora workstation, the Docker services on `*.fbns.eu`, Home
Assistant and the Fibaro controllers.

Infrastructure is **operated from here** — read, write, create, delete. No application code, no IaC,
no service configuration: compose files live in `fbns-docker`.

Store environment variable values in Windows Credential Manager.

Claude Code session sync (Cloudflare R2): `scripts/claude-sync/`, set up per
`docs/guides/claude-sync-setup.md`.
