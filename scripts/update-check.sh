#!/usr/bin/env bash
# One quick release check for the update banner (services/Updater.qml).
#
# Prints key=value lines and always exits 0: a failed check is data for the
# banner ("show nothing, log one line"), never a crash. The decision is made in
# services/updater.js; this script only gathers the facts.
#
#   checkout=yes|no   the installed folder is (or links to) a git checkout
#   branch=<name>     symbolic-ref --short HEAD; empty when detached or no repo
#   dirty=yes|no      git status --porcelain is not empty
#   tag=<vX.Y.Z>      one per remote release tag
#   error=<code>      the remote could not be read (offline, timeout, no git)
#
# Usage: update-check.sh [<config dir>]
set -uo pipefail

cfg=${1-${XDG_CONFIG_HOME:-$HOME/.config}/kisaru}

# A1: no checkout means a --copy install. Its own repository still answers, so
# the S4 reinstall banner can say a release exists.
upstream="https://github.com/pwn27sbx/kisaru"
url=$(git -C "$cfg" remote get-url origin 2>/dev/null) || url=""
[[ -n $url ]] || url=$upstream

checkout=no
branch=""
dirty=""
if git -C "$cfg" rev-parse --git-dir >/dev/null 2>&1; then
    checkout=yes
    # A6: a detached HEAD makes symbolic-ref fail, which reads as "not main".
    branch=$(timeout 5 git -C "$cfg" symbolic-ref --short HEAD 2>/dev/null) || branch=""
    [[ -n $(git -C "$cfg" status --porcelain 2>/dev/null) ]] && dirty=yes
fi
printf 'checkout=%s\n' "$checkout"
printf 'branch=%s\n' "$branch"
printf 'dirty=%s\n' "$dirty"

# A1: never prompt (a floating terminal has nobody to answer), and cap the
# remote at 5 s. `--refs` skips peeled annotated-tag lines; the JS parser drops
# anything that is not a numbered release anyway.
tags=$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true \
    GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
    timeout 5 git -c credential.helper= ls-remote --tags --refs "$url" 2>/dev/null)
status=$?
if ((status != 0)); then
    printf 'error=%s\n' "$status"
    exit 0
fi

while read -r _ ref; do
    [[ -n $ref ]] && printf 'tag=%s\n' "${ref#refs/tags/}"
done <<<"$tags"
exit 0
