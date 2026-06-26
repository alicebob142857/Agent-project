# Local to VM Git-change sync

Correct workflow for this project:

## 1. Local machine

From the repository root:

```bash
bash scripts/local_export_changes.sh
bash start_share.sh
```

`start_share.sh` shares the current repository root. The generated package stays
under `tmp/`, and `vm_pull_changes.sh` is also copied to the repository root so
it can be downloaded directly.

## 2. VM

After cloudflared prints a URL like `https://xxxx.trycloudflare.com`, run:

```bash
wget -O /data/vm_pull_changes.sh https://xxxx.trycloudflare.com/vm_pull_changes.sh
bash /data/vm_pull_changes.sh https://xxxx.trycloudflare.com
```

The VM script automatically fetches `tmp/latest.txt`, downloads the latest
`git-changes-*.tar.gz`, and expands it into `/data` while preserving local
relative paths.

Example:

```text
local: src/unzip_gbk.py
VM:    /data/src/unzip_gbk.py
```

## Notes

- Only Git changed files are packaged.
- `tmp/` is never included in the package.
- Only one `git-changes-*.tar.gz` is kept under `tmp/`.
- Deleted local tracked files are deleted under `/data` too.
