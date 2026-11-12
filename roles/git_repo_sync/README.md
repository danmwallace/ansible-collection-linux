# danmwallace.linux.git_repo_sync

Gives each GitHub repo its own deploy key on the machine, clones it, and
installs a login service that either pulls the clone or syncs it (commit,
pull --rebase, push). Built for keeping a notes vault and a shared config
repo current across laptops without a personal GitHub credential on each one.

## What it does, per repo

- Creates `~/.ssh/deploy_<name>_ed25519` if absent, and an `~/.ssh/config`
  alias `github-<name>` that uses only that key. GitHub's host key is pinned.
- Clones `git@github-<name>:<owner/repo>.git` to `dest` if `dest` is absent.
  An existing clone is never touched, except that an `origin` pointing at the
  same repo on github.com in another form is switched to the alias.
- Installs `~/.config/systemd/user/git-repo-sync@.service` and enables one
  instance per repo whose `mode` isn't `none` (by creating the
  `default.target.wants` link, so it works with no user session).

If a clone fails (GitHub doesn't know the key yet, or no network), the play
stops for that host and prints a `gh repo deploy-key add` command per key,
read-write when `writable` is true. The role never registers keys itself.

## The login service (`/usr/local/libexec/git-repo-sync`)

| mode | at login |
|---|---|
| `pull` | skip if the clone has uncommitted changes, else `pull --ff-only`, then `after_pull` |
| `sync` | commit everything (`<name> sync from <host> (<date>)`), `pull --rebase`, `push`, then `after_pull` |

It never forces anything:
- Offline, or a key GitHub doesn't know: a line in the journal, exit 0.
- A rebase or merge already in progress: it does nothing.
- A pull that conflicts or a push that fails: the rebase is aborted, its own
  commit is undone (the changes are back as uncommitted edits), and a
  desktop notification says so. The next login tries again.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `git_repo_sync_user` | `ansible_user_id` | owner of the clones, keys and units |
| `git_repo_sync_repos` | `[]` | list of `{name, github, dest, mode, writable, after_pull}` |
| `git_repo_sync_github_host_key` | GitHub's ed25519 key | pinned in `~/.ssh/known_hosts` |
| `git_repo_sync_script` | `/usr/local/libexec/git-repo-sync` | where the login script goes |

`dest` may start with `~`; it is expanded to the user's home.

## Example

```yaml
- hosts: laptops
  become: true
  roles:
    - role: danmwallace.linux.git_repo_sync
      vars:
        git_repo_sync_user: dwallace
        git_repo_sync_repos:
          - { name: obsidian, github: danmwallace/obsidian, dest: ~/Notebook, mode: sync, writable: true }
          - { name: claude-config, github: danmwallace/claude-config, dest: ~/.local/share/claude-config,
              mode: pull, after_pull: "~/.local/share/claude-config/apply" }
```

## Gotchas

- The service runs once per login. It waits up to 60 s for NetworkManager to
  report a connection, then skips quietly if origin is still unreachable.
- `writable` only changes the printed `gh` command. GitHub enforces
  read-only versus read-write on the key.
- A deploy key is per repo: GitHub refuses to register the same public key
  on two repos, which is why each repo gets its own.

## Tests

```bash
bash roles/git_repo_sync/tests/test-sync.sh   # the login script
cd roles/git_repo_sync && molecule test        # the role (podman)
```
