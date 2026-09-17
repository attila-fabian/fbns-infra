# Strips inherited ACLs from ~/.claude-sync so only this user (and SYSTEM) can read
# config.yaml (plaintext R2 secret) and age-key.txt (encryption key).
# Safe to re-run.

$ErrorActionPreference = 'Stop'
$dir = "$env:USERPROFILE\.claude-sync"
$me = (whoami).Trim()

# Explicit ACEs on the directory only, then make every child re-inherit from it.
# (Granting with /T leaves existing children with an empty ACL - nobody can read them.)
icacls $dir /inheritance:r /grant:r "${me}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null
if (Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue) {
    icacls "$dir\*" /reset /T /C /Q | Out-Null
}
icacls $dir
