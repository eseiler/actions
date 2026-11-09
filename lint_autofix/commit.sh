#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Turns the formatting result of Lint Autofix's `prepare` job into a signed bot commit on the PR branch.
#
# Why the checks: `prepare` has no secrets, but it processed the PR's files, so its output (a git bundle) is not
# trusted. This script runs in the job that holds the GPG key and the App token. It only signs and pushes the bundle
# if the bundle is what a formatter could have produced: one commit on top of the PR head, modifying existing source
# files, nothing else.
#
# Usage:
#   commit.sh <bundle> <base-remote> <pr> <head-sha> <push-remote> <head-ref>
#
#   bundle       git bundle from `prepare`. Only fetched (with fsck) and inspected, never checked out.
#   base-remote  URL of the repository the PR targets; provides refs/pull/<pr>/head.
#   pr           PR number (trusted, from the GitHub API).
#   head-sha     The PR head commit that `prepare` formatted (trusted, from the GitHub API).
#   push-remote  URL of the repository holding the PR branch: the contributor's fork, or the base repository.
#   head-ref     Name of the PR branch. Chosen by the contributor; only ever used as one argument.
#
# Environment: SIGN=1 signs the commit (`git commit-tree -S`, using the global user.signingkey). Authentication for
# both remotes is expected in GIT_CONFIG_* (see action.yml), not in the URLs.
#
# The push is a plain fast-forward: if the contributor pushed in the meantime, it is rejected and nothing changes.

set -Eeuo pipefail

bundle=$1
base_remote=$2
pr=$3
head_sha=$4
push_remote=$5
head_ref=$6

die() {
    echo "::error::$*" >&2
    exit 1
}

[[ ${pr} =~ ^[0-9]+$ ]] || die "invalid PR number"
[[ ${head_sha} =~ ^[0-9a-f]{40}$ ]] || die "invalid head SHA"

# --- A private, bare repository: nothing is ever checked out --------------------------------------------------------

scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
export GIT_DIR="${scratch}/git"
git init -q --bare "${GIT_DIR}"
git config transfer.fsckObjects true # reject malformed objects from the bundle

# --- The PR head must still be the commit that was formatted ---------------------------------------------------------

git fetch -q --no-tags "${base_remote}" "+refs/pull/${pr}/head:refs/pr/head"
[[ $(git rev-parse refs/pr/head) == "${head_sha}" ]] || die "PR head moved, not committing"

# --- The bundle must be exactly one commit whose only parent is the PR head -----------------------------------------

git bundle verify -q "${bundle}" > /dev/null || die "bundle does not apply to the PR head"
git fetch -q --no-tags "${bundle}" "HEAD:refs/autofix" || die "cannot fetch bundle"
fix=$(git rev-parse refs/autofix)

[[ $(git rev-list --count "${head_sha}..${fix}") == 1 ]] || die "bundle must contain exactly one commit"
[[ $(git rev-parse "${fix}^@") == "${head_sha}" ]] || die "bundle commit must have the PR head as its only parent"

# --- It may only modify existing source files, without changing their mode ------------------------------------------
#
# The same file types and exclusions as format.sh. An added file, a deletion, a rename, a symlink or a change to
# anything else (workflows, scripts, configs) means the bundle did not come from the formatters.

changes=0
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    # One record of `git diff-tree --raw -z`: ":<old mode> <new mode> <old sha> <new sha> <status>" NUL "<path>" NUL
    read -r old_mode new_mode _ _ status <<< "${meta#:}"
    [[ ${status} == M ]] || die "not a modification: ${status} ${path@Q}"
    [[ ${old_mode} == "${new_mode}" && ${new_mode} =~ ^100(644|755)$ ]] || die "mode change or non-regular file: ${path@Q}"
    case ${path} in
        *.cpp | *.hpp) [[ ! ${path} =~ (lib/|contrib/|submodules/) ]] || die "excluded path: ${path@Q}" ;;
        *.cmake | *CMakeLists.txt) ;;
        *) die "not a formatter target: ${path@Q}" ;;
    esac
    changes=$((changes + 1))
done < <(git diff-tree -r -z --no-renames --raw "${head_sha}" "${fix}")
((changes > 0)) || die "bundle commit is empty"

# --- Commit the bundle's tree again, as the bot, and push it as a fast-forward ----------------------------------------
#
# Only the tree is taken from the bundle; author, committer, message and signature are set here.

export GIT_AUTHOR_NAME="seqan-actions[bot]" GIT_AUTHOR_EMAIL="seqan-actions@users.noreply.github.com"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
sign=()
[[ ${SIGN:-0} == 1 ]] && sign=(-S)
new=$(git commit-tree "${sign[@]}" -p "${head_sha}" -m "chore(lint): formatting" "$(git rev-parse "${fix}^{tree}")")

git push -q "${push_remote}" "${new}:refs/heads/${head_ref}" # no --force: a concurrent push by the contributor wins
echo "Pushed ${new} (${changes} files) to ${head_ref@Q}."
