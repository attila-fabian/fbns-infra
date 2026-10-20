# SSH key login to a new NAS or server

One key per host, kept in Bitwarden (Vaultwarden). Windows stores only the public key.

Use PowerShell on Windows. Git Bash `ssh` cannot use the Bitwarden agent.

Set the host's values first, in the PowerShell window you will use for every step:

```powershell
$alias = 'fbnsbk'          # short name for ssh
$ip    = '10.5.0.5'
$user  = 'Attila Fabian'
```

## 1. Turn on SSH

- **Synology:** DSM → Control Panel → Terminal & SNMP → **Enable SSH service**. The user must be in
  group `administrators`.
- **Linux:** usually on already.

Never open port `22` on the router.

## 2. Create the key

Bitwarden → New item → **SSH key** → name it `<HOST> NAS SSH` → Save. Copy the public key.

## 3. Add the host on Windows

With the public key copied:

```powershell
(Get-Clipboard -Raw).Trim() | Set-Content $HOME\.ssh\$alias.pub -Encoding ascii

Add-Content $HOME\.ssh\config @"

Host $alias
 HostName $ip
 User "$user"
 IdentityFile ~/.ssh/$alias.pub
 IdentitiesOnly yes
"@
```

## 4. Put the key on the host

### Synology without user home service (FBNSBK, E29HU)

Log in with the DSM password. Ignore `Could not chdir to home directory`.

```powershell
Get-Content $HOME\.ssh\$alias.pub | Set-Clipboard
ssh $alias
```

On the NAS, run one line at a time:

```sh
sudo -i
head -1 /etc/ssh/sshd_config
```

Line 1 already reads `AuthorizedKeysFile ...`? Skip the `sed` line. Never run it twice.

```sh
sed -i '1i AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/keys/%u' /etc/ssh/sshd_config
mkdir -p /etc/ssh/keys && chmod 755 /etc/ssh/keys
echo 'PASTE-KEY-HERE' > "/etc/ssh/keys/$SUDO_USER"
chmod 644 "/etc/ssh/keys/$SUDO_USER"
sshd -t
systemctl restart sshd
```

`$SUDO_USER` is the user you logged in as. `sshd -t` must print nothing. If it prints an error, do
not restart.

A DSM update can undo this. Password login still works then; repeat this step.

### Linux, or Synology with user home service (Fedora, FBNS)

Synology only: first tick DSM → Control Panel → User & Group → Advanced → **Enable user home service**.

```powershell
Get-Content $HOME\.ssh\$alias.pub | ssh $alias "mkdir -p ~/.ssh && chmod 700 ~/.ssh && tr -d '\r' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 755 ~"
```

## 5. Test

In a **new PowerShell window on Windows**, not on the host. Set the values again, then:

```powershell
ssh $alias hostname
```

Approve in Bitwarden. The host name prints with no password prompt = done.

## 6. Optional, Synology: Docker without sudo

⚠️ The SSH key then gives full root access to the NAS.

```powershell
ssh $alias
```

On the NAS:

```sh
sudo /usr/syno/sbin/synogroup --add docker "$USER"
```

```sh
sudo /usr/syno/bin/synopkg restart ContainerManager
```

Containers stop briefly during the restart.

## 7. Write it down

Add the host to [infra.md](../reference/infra.md).

## Ask Claude

In Claude Code, in this repo: *"Set up SSH for `<host>` per `docs/guides/ssh-key-setup.md`"*. Claude
gives the commands one step at a time and checks the output you paste back.
