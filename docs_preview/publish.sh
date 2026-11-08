#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0
#
# Replace (or delete) one preview directory on the content branch of the preview repository.
#
#   publish.sh <src> <dest> <remote> [<branch>]
#
#   src     Directory with the rendered preview. Untrusted data: it is only hashed into git, never executed.
#           An empty string deletes <dest>.
#   dest    <owner>/<repo>/<pr>. Must be computed by the caller from trusted event fields.
#   remote  URL of the preview repository. Authentication is expected in the environment
#           (GIT_CONFIG_* extraheader), not in the URL.
#   branch  Content branch, default "previews". It holds no .github/ directory, so a token without the
#           "workflows" permission can replace it wholesale.
#
# Every update is a parentless commit pushed with --force-with-lease, so the branch never accumulates history.
# Concurrent publishers (different repositories or PRs) lose the lease and retry on top of the new tip.

set -Eeuo pipefail

src=$1
dest=$2
remote=$3
branch=${4:-previews}

if [[ ! ${dest} =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[0-9]+$ ]]; then
    echo "::error::invalid destination '${dest}'" >&2
    exit 1
fi

max_mib=${PREVIEW_MAX_MIB:-200}

scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
# Plumbing only: an empty work tree, so nothing from the preview is ever checked out here.
export GIT_DIR="${scratch}/git" GIT_WORK_TREE="${scratch}/empty" GIT_INDEX_FILE="${scratch}/git/index"
mkdir "${GIT_WORK_TREE}"
export GIT_AUTHOR_NAME="seqan-actions[bot]" GIT_AUTHOR_EMAIL="seqan-actions@users.noreply.github.com"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
git init -q

subtree=
if [[ -n ${src} ]]; then
    # Only regular files and directories: no symlinks (upload-pages-artifact dereferences them, e.g. into
    # /proc/self/environ of the Pages job), devices or FIFOs. No .git* entries: no embedded repositories (gitlinks),
    # and no .gitattributes that would apply filters/LFS when the Pages workflow checks the branch out.
    if [[ -n $(find "${src}" \( \( ! -type f ! -type d \) -o -name '.git*' \) -print -quit) ]]; then
        echo "::error::preview contains entries that are neither regular files nor directories, or .git* entries" >&2
        exit 1
    fi
    size_mib=$(du -sm "${src}" | cut -f1)
    if ((size_mib > max_mib)); then
        echo "::error::preview is ${size_mib} MiB, limit is ${max_mib} MiB" >&2
        exit 1
    fi
    # Hash the preview into a tree object using a throw-away index.
    GIT_INDEX_FILE="${scratch}/subtree.index" git -C "${src}" --work-tree=. add -A -- .
    subtree=$(GIT_INDEX_FILE="${scratch}/subtree.index" git write-tree)
fi

for attempt in 1 2 3 4 5; do
    if git fetch -q --no-tags --depth=1 "${remote}" "refs/heads/${branch}" 2> /dev/null; then
        old=$(git rev-parse FETCH_HEAD)
        git read-tree "${old}"
    else
        old= # Branch does not exist yet; the lease below then requires that it still does not.
        git read-tree --empty
    fi

    # Drop the old version of this preview, graft the new one.
    git ls-files -z -- "${dest}/" | git update-index -z --force-remove --stdin
    if [[ -n ${subtree} ]]; then
        git read-tree --prefix="${dest}/" "${subtree}"
    fi
    tree=$(git write-tree)

    if [[ -n ${old} && ${tree} == $(git rev-parse "${old}^{tree}") ]]; then
        echo "Preview ${dest} is already up to date."
        exit 0
    fi

    new=$(git commit-tree "${tree}" -m "$([[ -n ${src} ]] && echo Update || echo Delete) preview ${dest}")
    if git push -q --force-with-lease="refs/heads/${branch}:${old}" "${remote}" "${new}:refs/heads/${branch}"; then
        echo "Published ${dest} (${new})."
        exit 0
    fi
    echo "Lost the race for ${branch} (attempt ${attempt}), retrying."
    sleep $((attempt * 3 + RANDOM % 5))
done

echo "::error::could not update ${branch} after 5 attempts" >&2
exit 1
