#!/usr/bin/bash
# bash roles/git_repo_sync/tests/test-sync.sh (from the collection root)
# The login sync script against a local bare repo standing in for GitHub; a second
# clone plays the other machine. notify-send is a stub that logs.
set -uo pipefail
script="$(cd "$(dirname "$0")/.." && pwd)/files/git-repo-sync"
fail=0
pass=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

setup() {
    T=$(mktemp -d)
    BIN=$T/bin NOTE=$T/notify.log
    mkdir -p "$BIN"
    printf '#!/usr/bin/bash\necho "$*" >> %s\n' "$NOTE" > "$BIN/notify-send"
    chmod +x "$BIN/notify-send"
    git init -q --bare -b main "$T/origin.git"
    git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
    printf 'one\n' > "$T/seed/note.md"
    git -C "$T/seed" add -A && git -C "$T/seed" commit -qm init && git -C "$T/seed" push -q origin main
    git clone -q "$T/origin.git" "$T/here"      # this machine
    git clone -q "$T/origin.git" "$T/other"     # another machine
}

sync() { PATH="$BIN:/usr/bin:/bin" bash "$script" "$@"; }

other_commits() {  # other_commits <file> <content>
    printf '%s\n' "$2" > "$T/other/$1"
    git -C "$T/other" add -A && git -C "$T/other" commit -qm "other: $1" && git -C "$T/other" push -q origin main
}

check() {
    local name=$1; shift
    if "$@"; then pass=$((pass + 1)); echo "ok    $name"; else fail=1; echo "FAIL  $name"; fi
}

test_pull_fast_forward() {
    setup
    other_commits new.md fresh
    sync obsidian "$T/here" pull && [ "$(cat "$T/here/new.md")" = fresh ]
}

test_pull_skips_dirty() {
    setup
    other_commits new.md fresh
    printf 'my edit\n' > "$T/here/note.md"
    sync obsidian "$T/here" pull || return 1
    [ "$(cat "$T/here/note.md")" = "my edit" ] && [ ! -e "$T/here/new.md" ] && [ ! -s "$NOTE" ]
}

test_sync_commits_pulls_pushes() {
    setup
    other_commits from-other.md hi
    printf 'task\n' > "$T/here/task.md"
    sync obsidian "$T/here" sync || return 1
    git -C "$T/other" pull -q
    msg=$(git -C "$T/origin.git" log -1 --format=%s main)
    [ -f "$T/other/task.md" ] && [ -f "$T/here/from-other.md" ] &&
        grep -qE '^obsidian sync from .+ \([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\)$' <<<"$msg"
}

test_sync_nothing_to_do_is_quiet() {
    setup
    out=$(sync obsidian "$T/here" sync 2>&1) || return 1
    [ "$(git -C "$T/origin.git" rev-list --count main)" = 1 ] && [ ! -s "$NOTE" ]
}

test_sync_conflict_aborts_and_notifies() {
    setup
    other_commits note.md theirs
    printf 'mine\n' > "$T/here/note.md"
    before_head=$(git -C "$T/here" rev-parse HEAD)
    sync obsidian "$T/here" sync; rc=$?
    [ "$rc" -eq 0 ] &&
        [ "$(git -C "$T/here" rev-parse HEAD)" = "$before_head" ] &&
        [ "$(cat "$T/here/note.md")" = mine ] &&
        [ ! -e "$T/here/.git/rebase-merge" ] && [ ! -e "$T/here/.git/rebase-apply" ] &&
        [ "$(wc -l < "$NOTE")" -eq 1 ] && grep -q "obsidian sync needs you" "$NOTE" &&
        [ "$(git -C "$T/origin.git" log -1 --format=%s main)" = "other: note.md" ]
}

test_offline_is_quiet() {
    setup
    printf 'task\n' > "$T/here/task.md"
    mv "$T/origin.git" "$T/gone.git"
    sync obsidian "$T/here" sync || return 1
    [ ! -s "$NOTE" ] && [ -z "$(git -C "$T/here" log --format=%s -1 | grep sync)" ]
}

test_sync_skips_rebase_in_progress() {
    setup
    printf 'task\n' > "$T/here/task.md"
    mkdir "$T/here/.git/rebase-merge"
    before=$(git -C "$T/here" rev-parse HEAD)
    sync obsidian "$T/here" sync || return 1
    [ "$(git -C "$T/here" rev-parse HEAD)" = "$before" ] &&
        [ "$(git -C "$T/origin.git" rev-list --count main)" = 1 ] && [ ! -s "$NOTE" ]
}

test_after_pull_runs_only_after_pull() {
    setup
    sync claude-config "$T/here" pull "touch $T/ran" || return 1
    [ -e "$T/ran" ] || return 1
    rm "$T/ran"
    printf 'my edit\n' > "$T/here/note.md"            # dirty: no pull, no after_pull
    sync claude-config "$T/here" pull "touch $T/ran" || return 1
    [ ! -e "$T/ran" ] || return 1
    git -C "$T/here" checkout -q -- note.md
    mv "$T/origin.git" "$T/gone.git"                  # offline: no pull, no after_pull
    sync claude-config "$T/here" pull "touch $T/ran" || return 1
    [ ! -e "$T/ran" ]
}

test_bad_usage() {
    setup
    sync obsidian "$T/here" bogus >/dev/null 2>&1; [ $? -eq 2 ] || return 1
    sync obsidian >/dev/null 2>&1; [ $? -eq 2 ]
}

for t in test_pull_fast_forward test_pull_skips_dirty test_sync_commits_pulls_pushes test_sync_nothing_to_do_is_quiet \
         test_sync_conflict_aborts_and_notifies test_offline_is_quiet test_sync_skips_rebase_in_progress \
         test_after_pull_runs_only_after_pull test_bad_usage; do
    check "$t" "$t"
done
echo "$pass passed"
exit "$fail"
