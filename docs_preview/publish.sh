#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Replaces (or deletes) one documentation preview on the content branch of seqan/docs-preview.
#
# The branch `previews` holds every open preview of every repository as <owner>/<repo>/<pr>/; GitHub Pages serves it
# at https://seqan.github.io/docs-preview/. This script swaps out one of those directories.
#
# Usage:
#   publish.sh <src> <dest> <remote> [<branch>]
#
#   src     Directory with the rendered HTML. Empty string: delete <dest>.
#   dest    <owner>/<repo>/<pr>, computed by the caller from trusted event fields.
#   remote  URL of the preview repository. Authentication is expected in GIT_CONFIG_* (see action.yml), not in the URL.
#   branch  Content branch, default `previews`.
#
# Environment: PREVIEW_MAX_MIB (default 500) limits the size of one preview.
#
# Why it looks like this:
#   - The HTML was built from PR code, so it is untrusted data. It is only hashed into git objects; nothing from it is
#     checked out or executed, and there is no work tree to check it out into.
#   - Only regular files and directories are accepted. A symlink would be followed when the Pages workflow packs the
#     site (upload-pages-artifact uses tar --dereference), e.g. to /proc/self/environ of that job. A .git* entry could
#     be an embedded repository, or a .gitattributes that applies filters/LFS when the branch is checked out.
#   - Every update is one parentless commit, so the branch never accumulates history.
#   - Previews of different PRs and repositories are published concurrently. The push uses --force-with-lease against
#     the tip the update was built on; whoever loses the race rebuilds on the new tip and tries again.
#   - The branch has no .github/ directory, so a token without the Workflows permission may replace it wholesale.

set -Eeuo pipefail

src=$1
dest=$2
remote=$3
branch=${4:-previews}
max_mib=${PREVIEW_MAX_MIB:-500}

die() {
    echo "::error::$*" >&2
    exit 1
}

# <owner>/<repo>/<pr>: three components, no `.` or `..`, digits for the PR.
name='[A-Za-z0-9._-]+'
if [[ ! ${dest} =~ ^${name}/${name}/[0-9]+$ || ${dest} =~ (^|/)\.\.?/ ]]; then
    die "invalid destination '${dest}'"
fi

# --- A private repository without a work tree ----------------------------------------------------------------------

scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
export GIT_DIR="${scratch}/git" GIT_WORK_TREE="${scratch}/empty" GIT_INDEX_FILE="${scratch}/git/index"
mkdir "${GIT_WORK_TREE}" # stays empty: index operations below never write files
export GIT_AUTHOR_NAME="seqan-actions[bot]" GIT_AUTHOR_EMAIL="seqan-actions@users.noreply.github.com"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
git init -q

# --- The new preview as a git tree object (none when deleting) -----------------------------------------------------

subtree=
if [[ -n ${src} ]]; then
    if [[ -n $(find "${src}" \( \( ! -type f ! -type d \) -o -name '.git*' \) -print -quit) ]]; then
        die "preview contains entries that are neither regular files nor directories, or .git* entries"
    fi
    size_mib=$(du -sm "${src}" | cut -f1)
    ((size_mib <= max_mib)) || die "preview is ${size_mib} MiB, limit is ${max_mib} MiB"

    # Hash the files into objects through a throw-away index; the preview directory itself is only read.
    GIT_INDEX_FILE="${scratch}/subtree.index" git -C "${src}" --work-tree=. add -A -- .
    subtree=$(GIT_INDEX_FILE="${scratch}/subtree.index" git write-tree)
fi

# --- Swap the directory on the current tip and push; retry if someone else pushed first -------------------------------

for attempt in 1 2 3 4 5; do
    if git fetch -q --no-tags --depth=1 "${remote}" "refs/heads/${branch}" 2> /dev/null; then
        old=$(git rev-parse FETCH_HEAD)
        git read-tree "${old}"
    else
        old= # the branch does not exist yet; the lease below then requires that it still does not
        git read-tree --empty
    fi

    git ls-files -z -- "${dest}/" | git update-index -z --force-remove --stdin # drop the old version
    if [[ -n ${subtree} ]]; then
        git read-tree --prefix="${dest}/" "${subtree}" # graft the new one
    fi
    tree=$(git write-tree)

    if [[ -n ${old} && ${tree} == $(git rev-parse "${old}^{tree}") ]]; then
        echo "Preview ${dest} is already up to date."
        exit 0
    fi

    action=$([[ -n ${src} ]] && echo Update || echo Delete)
    new=$(git commit-tree "${tree}" -m "${action} preview ${dest}") # no -p: parentless
    if git push -q --force-with-lease="refs/heads/${branch}:${old}" "${remote}" "${new}:refs/heads/${branch}"; then
        echo "Published ${dest} (${new})."
        exit 0
    fi
    echo "Lost the race for ${branch} (attempt ${attempt}), retrying."
    sleep $((attempt * 3 + RANDOM % 5))
done

die "could not update ${branch} after 5 attempts"
