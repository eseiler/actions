#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Submits the packages of a CPM package lock and the CPM version to the repository's dependency graph
# (https://docs.github.com/en/rest/dependency-graph/dependency-submission).
#
# Usage:
#   dependency_snapshot.sh <work-tree> <package-lock>
#
#   work-tree     Checkout of the commit to submit (its HEAD). Read as data; only the package lock is evaluated,
#                 by dependency_snapshot.cmake.
#   package-lock  Path of the package lock, relative to <work-tree>. Also the snapshot's correlator.
#
# The snapshot (dependency_snapshot.jq) has one manifest for the package lock and one for every CPM.cmake.
#
# Environment: GH_TOKEN (contents: write), GITHUB_REPOSITORY, GITHUB_REF; optional: GITHUB_RUN_ID and
# GITHUB_SERVER_URL (job id and URL; without GITHUB_RUN_ID, the job id is manual-<time>), DETECTOR_VERSION (default:
# unknown), RUNNER_TEMP (default: TMPDIR or /tmp).
#
# Problems are warnings (GitHub annotations) with exit code 0: the dependency snapshot must not break the job.
# Exit code other than 0: wrong usage (2) or a missing environment variable (1).

set -Euo pipefail
# No -e: every command that can fail is checked, and a failure ends the script with a warning.

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Warns and ends the script successfully. https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
skip_snapshot() {
    local message="$*"
    message=${message//'%'/'%25'}
    message=${message//$'\r'/'%0D'}
    message=${message//$'\n'/'%0A'}
    echo "::warning title=Dependency snapshot::${message}"
    exit 0
}

if (($# != 2)); then
    sed -n 's/^#   dependency_snapshot.sh /Usage: dependency_snapshot.sh /p' "${BASH_SOURCE[0]}" >&2
    exit 2
fi
work_tree=$1
package_lock=$2

sha=$(git -C "${work_tree}" rev-parse HEAD) \
    || skip_snapshot "${work_tree} is not a git work tree, no dependency snapshot submitted."

dir=$(mktemp --directory "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dependency_snapshot.XXXXXX") \
    || skip_snapshot "Could not create a temporary directory, no dependency snapshot submitted."
trap 'rm -rf -- "${dir}"' EXIT

cmake -D "SOURCE_DIR=${work_tree}" \
      -D "PACKAGE_LOCK=${package_lock}" \
      -D "OUTPUT=${dir}/packages.tsv" \
      -P "${script_dir}/dependency_snapshot.cmake" \
    || skip_snapshot "Could not read ${package_lock} (see the log), no dependency snapshot submitted."

if [[ -n ${GITHUB_RUN_ID:-} ]]; then
    run_id=${GITHUB_RUN_ID}
    run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:?}/actions/runs/${GITHUB_RUN_ID}"
else
    run_id="manual-$(date --utc +%Y%m%dT%H%M%SZ)"
    run_url=""
fi

jq --null-input --raw-input --from-file "${script_dir}/dependency_snapshot.jq" \
   --arg correlator "${package_lock}" \
   --arg sha "${sha}" \
   --arg ref "${GITHUB_REF:?}" \
   --arg run_id "${run_id}" \
   --arg run_url "${run_url}" \
   --arg detector_version "${DETECTOR_VERSION:-unknown}" \
   --arg scanned "$(date --utc +%Y-%m-%dT%H:%M:%SZ)" \
   "${dir}/packages.tsv" > "${dir}/snapshot.json" \
    || skip_snapshot "Could not create the dependency snapshot (see the log), none submitted."
jq . "${dir}/snapshot.json"

if ! response=$(gh api --method POST "repos/${GITHUB_REPOSITORY:?}/dependency-graph/snapshots" \
                       --input "${dir}/snapshot.json" 2> "${dir}/gh.log"); then
    printf '%s\n' "${response}"
    cat "${dir}/gh.log"
    skip_snapshot "Could not submit the dependency snapshot: $(< "${dir}/gh.log")" \
                  "Is the dependency graph enabled for the repository, and does the token have contents: write?"
fi
printf '%s\n' "${response}"

# SUCCESS: dependencies updated. ACCEPTED: snapshot stored, dependencies not updated. INVALID: malformed.
result=$(jq --raw-output '.result // empty' <<< "${response}")
message=$(jq --raw-output '.message // empty' <<< "${response}")
[[ -n ${result} ]] || skip_snapshot "Unexpected response to the dependency snapshot: ${response:0:500}"
[[ ${result} == SUCCESS ]] || skip_snapshot "Dependency snapshot ${result}: ${message}"
echo "Dependency snapshot submitted: ${message}"
