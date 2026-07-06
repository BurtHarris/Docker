# `trust/` — public encryption certificates (trust markers)

This directory holds the **public half** of each wiki's encryption certificate.
Files here are safe to commit; they contain no private key material.

## What is a trust marker?

When `New-WikiKey.ps1` runs, it:
1. Generates a self-signed RSA key pair in the Windows certificate store
   (`Cert:\CurrentUser\My`) — the private key never leaves the machine.
2. Exports the **public certificate** (`.cer`) here.

The `.cer` file encodes *who is authorised to supply secrets* for this wiki:
anyone may encrypt a value using this certificate, but only the person holding
the matching private key can decrypt it.

## Files in this directory

| File | Wiki instance | Purpose |
|---|---|---|
| `wiki-mywiki-encrypt.cer` | `mywiki` (default) | Encryption trust marker |

Add a row for each wiki instance created with `New-WikiKey.ps1 -WikiName <name>`.

## Migrating to a new machine

1. Run `.\New-WikiKey.ps1 -Force` on the new machine.
2. Commit the new `.cer` file.
3. Re-run `.\Set-WikiSecrets.ps1` — the old `.cms` files (encrypted to the old
   key) are no longer usable; the new key produces fresh `.cms` files.
