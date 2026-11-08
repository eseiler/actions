#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0
#
# Turn the formatting result of the unprivileged prepare job into a bot commit on the PR branch.
#
#   commit.sh <bundle> <base-remote> <pr> <head-sha> <push-remote> <head-ref>
#
#   bundle       git bundle from the prepare job. Untrusted: it is only fetched (with fsck) and inspected.
#   base-remote  URL of the base repository (provides refs/pull/<pr>/head).
#   pr, head-sha PR number and the head commit that was formatted (trusted, from the GitHub API).
#   push-remote  URL of the repository that holds the PR branch (the fork, or the base repository).
#   head-ref     Name of the PR branch. Attacker-chosen, but it is only ever a single argv element.
#
# The bundle must contain exactly one commit on top of <head-sha> that only modifies existing regular files whose
# names a formatter may touch, without changing modes. Its tree is then committed again with the bot identity (and
# signed if SIGN=1) and pushed as a fast-forward. If the contributor pushed in the meantime, the push is rejected.

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

scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
export GIT_DIR="${scratch}/git"
git init -q --bare "${GIT_DIR}"
git config transfer.fsckObjects true

git fetch -q --no-tags "${base_remote}" "+refs/pull/${pr}/head:refs/pr/head"
[[ $(git rev-parse refs/pr/head) == "${head_sha}" ]] || die "PR head moved, not committing"

git bundle verify -q "${bundle}" > /dev/null || die "bundle does not apply to the PR head"
git fetch -q --no-tags "${bundle}" "HEAD:refs/autofix" || die "cannot fetch bundle"
fix=$(git rev-parse refs/autofix)

[[ $(git rev-list --count "${head_sha}..${fix}") == 1 ]] || die "bundle must contain exactly one commit"
[[ $(git rev-parse "${fix}^@") == "${head_sha}" ]] || die "bundle commit must have the PR head as its only parent"

changes=0
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
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

export GIT_AUTHOR_NAME="seqan-actions[bot]" GIT_AUTHOR_EMAIL="seqan-actions@users.noreply.github.com"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
sign=()
[[ ${SIGN:-0} == 1 ]] && sign=(-S)
new=$(git commit-tree "${sign[@]}" -p "${head_sha}" -m "chore(lint): formatting" "$(git rev-parse "${fix}^{tree}")")

# Fast-forward only: no force, so a concurrent push by the contributor wins.
git push -q "${push_remote}" "${new}:refs/heads/${head_ref}"
echo "Pushed ${new} (${changes} files) to ${head_ref@Q}."
