# Reads the R2 credential from Windows Credential Manager (target: claude-sync-r2)
# and runs `claude-sync init`. Keeps the secret out of shell history and out of any file
# under version control.
#
# ponytail: the secret still lands in plaintext in ~/.claude-sync/config.yaml - claude-sync
# has no env-var or credential-store support. Blast radius is limited by scoping the R2
# token to the claude-sync bucket only; harden-config.ps1 locks the file down to this user.

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class CredMan {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredReadW(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr cred);

    // type 1 = CRED_TYPE_GENERIC (what `cmdkey /generic` writes)
    public static string[] Read(string target) {
        IntPtr ptr;
        if (!CredReadW(target, 1, 0, out ptr)) {
            throw new Exception("credential not found in Credential Manager: " + target);
        }
        CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
        string user = c.UserName;
        string secret = Marshal.PtrToStringUni(c.CredentialBlob, (int)c.CredentialBlobSize / 2);
        CredFree(ptr);
        return new string[] { user, secret };
    }
}
'@

$cred = [CredMan]::Read('claude-sync-r2')

& "$env:USERPROFILE\go\bin\claude-sync.exe" init `
    --provider r2 `
    --scope sessions `
    --passphrase `
    --account-id 14060e1c07454e34568cf23e84270d1a `
    --bucket claude-sync `
    --access-key $cred[0] `
    --secret-key $cred[1]

if ($LASTEXITCODE -eq 0) {
    & "$PSScriptRoot\harden-config.ps1"
}
