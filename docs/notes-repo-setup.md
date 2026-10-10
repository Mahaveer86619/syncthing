# Notes repo setup

The notes live in a **separate private repo**. This public repo holds only code.

## 1. Create the repo

On GitHub: **New repository** → name it e.g. `obsidian-notes` → **Private** → tick **Add a README** (the phone can't write to a completely empty repo) → Create.

## 2. Laptop access

The laptop uses plain `git`, so whatever already works for you is fine:

- **SSH**: `remoteUrl: "git@github.com:<you>/obsidian-notes.git"`. Check with `ssh -T git@github.com`.
- **HTTPS**: `remoteUrl: "https://github.com/<you>/obsidian-notes.git"`. Git Credential Manager asks once during `sync.ps1 -Init` and remembers it.

## 3. Phone token

Create a **fine-grained personal access token** limited to this one repo:

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token
2. **Repository access**: *Only select repositories* → `obsidian-notes`
3. **Repository permissions**: **Contents → Read and write** (Metadata: read-only is added automatically)
4. Expiration: your choice. When it expires, the app logs `GitHub rejected the token (401)`; paste a new one in Settings.

The token is stored in Android's encrypted storage (`flutter_secure_storage`) and only ever sent to `api.github.com`.

## 4. Seed it from the laptop

If you already have a vault on the laptop, run `sync.ps1 -Init` there first (see [laptop-sync.md](laptop-sync.md)). The laptop pushes the whole vault with one `git push`, which is much faster than the phone uploading file by file. Then point the phone at an empty folder (or its existing vault) and sync.
