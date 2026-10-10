# Notes repo setup

The notes live in a **separate private repo**. This public repo holds only code.

## 1. Create the repo

On GitHub: **New repository** → name it e.g. `obsidian-notes` → **Private** → Create. It can start empty: the Windows app creates the [layout](architecture.md#repo-layout) (`obsidian-notes/` + `syncthing-config/`) on first connect.

Have an existing vault? After the Windows app connects, copy your vault's contents into `<sync folder>\obsidian-notes`, and the background sync pushes them. A repo from before the layout existed (notes at the root) is reorganised automatically.

## 2. PC access

The PC uses plain `git`, so whatever already works for you is fine:

- **SSH**: `git@github.com:<you>/obsidian-notes.git`. Check with `ssh -T git@github.com`.
- **HTTPS**: `https://github.com/<you>/obsidian-notes.git`. Git Credential Manager asks once and remembers.

Several GitHub accounts on one PC? If you pick keys per folder with `includeIf "gitdir:..."`, a sync folder outside those folders gets your *default* key, and a private repo then shows `Repository not found`. Point the clone at the right account:

```powershell
git -C <sync folder> config include.path C:/Users/you/.gitconfig-personal
```

## 3. Phone token

The phone talks to the GitHub API, so it needs a **fine-grained personal access token** limited to this one repo:

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token
2. **Repository access**: *Only select repositories* → `obsidian-notes`
3. **Repository permissions**: **Contents → Read and write** only (Metadata: read-only is added automatically). Leave everything else on *No access*.
4. Expiration: your choice. When it expires, the phone shows "GitHub token is wrong or expired"; pair again with a new one.

## 4. Pair the phone (no typing)

1. Windows app → Settings → **Pair your phone**: paste the token (stored in Windows Credential Manager) → **Show pairing code**.
2. Phone app → Settings → **Scan pairing code**. Repo, branch and token are filled in.
3. Pick the vault folder and tap **Save**.

The QR holds the token, so close it when done. Don't send tokens through chat apps: they end up in chat backups. A token can't be "hashed" into the repo and recovered later, and encrypting it there would only move the problem to a key you still have to copy. Pairing keeps the token off GitHub entirely.
