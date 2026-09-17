# Setting up Claude Code session sync on a new computer

[claude-sync](https://github.com/tawanorg/claude-sync) syncs `~/.claude` to Cloudflare R2, age-encrypted
before upload. Same passphrase on every machine = same key, no key file to copy.

Current setup: bucket `claude-sync` (EEUR), Cloudflare account `14060e1c07454e34568cf23e84270d1a`,
scope `sessions` — conversations, plans, tasks, history only. Plugins and their `node_modules` are not synced.

## Set up a new computer

### 1. Install the binary

Upstream ships no Windows binary, so build from source:

```powershell
winget install --id GoLang.Go -e
go install -ldflags "-s -w -X main.version=1.17.1" github.com/tawanorg/claude-sync/cmd/claude-sync@v1.17.1
```

The `winget` step puts `go` in `C:\Program Files\Go\bin`, which the shell you ran it from does not know
about yet — either open a new terminal before `go install`, or prepend it for the current one with
`$env:PATH = "$env:PATH;C:\Program Files\Go\bin"`.

`claude-sync.exe` lands in `%USERPROFILE%\go\bin`. Put that directory on PATH:

```powershell
[Environment]::SetEnvironmentVariable('PATH', "$([Environment]::GetEnvironmentVariable('PATH','User'));$env:USERPROFILE\go\bin", 'User')
```

That writes the user PATH; already-open terminals keep the old one, so
`claude-sync: The term 'claude-sync' is not recognized` after this step means the shell is stale, not the
install. Open a new terminal, or patch the current one with
`$env:PATH = "$env:PATH;$env:USERPROFILE\go\bin"`.

Never `npm install -g @tawandotorg/claude-sync` on Windows — its postinstall 404s and leaves broken
shims in `%APPDATA%\npm` that shadow the real binary.

### 2. Get the R2 credential

Reuse the existing token if you still have both values, otherwise Cloudflare dashboard → R2 →
Manage API Tokens → **Account API token** → `Object Read & Write` → scoped to bucket `claude-sync`.

Account tokens outlive any single user; user tokens die with the user's role. The token yields an
Access Key ID (32 hex) and a Secret Access Key (64 hex), shown once.

### 3. Store it in Credential Manager

```powershell
cmdkey /generic:claude-sync-r2 /user:<AccessKeyID> /pass
```

`/pass` with no value prompts hidden — paste the Secret Access Key there. Keeps it out of shell history.

### 4. Run init

From a clone of this repo:

```powershell
git clone https://github.com/attila-fabian/fbns-infra.git
cd fbns-infra
.\scripts\claude-sync\init-r2.ps1
```

Reads the credential, runs `claude-sync init --provider r2 --scope sessions`, then hardens the config
directory. Prompts for the encryption passphrase — a second, unrelated secret, not the Secret Access Key
from step 3, and **the same one as every other machine**. Look for
`Encryption key verified`; without it the passphrase differs and you will not decrypt anything.

A fresh token needs ~30 s to propagate. A `403 Forbidden` on the connection test right after creating
one means wait and re-run, not bad credentials.

### 5. Pull

```powershell
claude-sync pull
claude-sync status
```

Home directories are remapped on pull, so `claude --resume` finds sessions written under a different
username or path.

The first `pull` on a machine that already has local sessions asks what to do with them — pick
**Backup existing files, then pull**. Local-only sessions are listed `KEEP` and survive; `push` uploads
them afterwards. The prompt needs a real terminal: run non-interactively and it dies with
`Error: Incorrect function.` before changing anything. `--force` answers it by overwriting with no
backup, so do not reach for it to get past that error.

### 6. Turn on auto-sync

```powershell
claude-sync auto enable
claude-sync auto status
```

Writes two hooks into `~/.claude/settings.json` — `SessionStart → claude-sync pull -q` and
`Stop → claude-sync push -q` — leaving any hooks already there alone. Idempotent, `--dry-run` shows the
diff first, `claude-sync auto disable` removes them.

Neither hook passes `--force`, so a conflicting pull fails instead of overwriting.

Two things to know:

- The hooks call `claude-sync` by bare name, so the Claude Code process has to see the PATH entry from
  step 1. Anything started before that edit inherits the old PATH and the hooks quietly do nothing —
  restart the terminal or the editor once after enabling.
- `Stop` fires when the assistant finishes a response, not when the session closes, so expect a push per
  turn rather than one per sitting. Pushes are incremental and `-q`, so this is cheap, just chatty.

## Daily use

Nothing, with auto-sync on. Manual equivalents, for a machine without the hooks or when a sync has to
happen right now:

```powershell
claude-sync pull    # sitting down
claude-sync push    # finishing up
```

## Scripts

| `scripts/claude-sync/` | Does |
|---|---|
| `init-r2.ps1` | Reads `claude-sync-r2` from Credential Manager via `CredReadW`, runs init with R2 + `--scope sessions`, then hardens |
| `harden-config.ps1` | Strips inherited ACLs from `~/.claude-sync` — this user and SYSTEM only. Safe to re-run |

## Known rough edges

- **`claude-sync update` fails on Windows** — no release binary. Upgrade by re-running the `go install`
  line with a newer tag.
- **Secret sits plaintext in `~/.claude-sync/config.yaml`.** claude-sync reads credentials from that file
  only — no env-var or keystore support. Credential Manager is the source of record, the file is the
  tool's working copy. Mitigated by the token being scoped to one bucket, object operations only, and the
  file being readable by one account.
- **`history.jsonl` is last-writer-wins** across machines. If the `/resume` picker looks short, run
  `claude-sync pull --rebuild-history` — it reconstructs history from the session files.

## Rotating the token

Create a new token, then:

```powershell
cmdkey /delete:claude-sync-r2
cmdkey /generic:claude-sync-r2 /user:<NewAccessKeyID> /pass
.\scripts\claude-sync\init-r2.ps1   # add --force inside the script call if init refuses to overwrite
```

Delete the old token in the dashboard afterwards. Keep the same passphrase or every machine has to re-init.
