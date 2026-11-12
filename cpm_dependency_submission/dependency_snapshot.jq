# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Builds a GitHub dependency snapshot from the output of dependency_snapshot.cmake. Called by dependency_snapshot.sh.
#
#   jq --null-input --raw-input --from-file dependency_snapshot.jq --arg correlator <id> --arg sha <commit> \
#      --arg ref <ref> --arg run_id <id> --arg run_url <url or ""> --arg detector_version <version> \
#      --arg scanned <ISO 8601> <packages.tsv>
#
# Snapshot: https://docs.github.com/en/rest/dependency-graph/dependency-submission
# Package URL: https://github.com/package-url/purl-spec/blob/main/types/github-definition.json
#   (owner and repository lower-cased; @uri percent-encodes everything but the unreserved characters of RFC 3986).
# No scope: it cannot be told from a package lock.
#
# Only the latest snapshot of each (correlator, detector name) pair is used, so the caller passes the path of the
# package lock alone: renaming the calling workflow or job replaces the old snapshot instead of adding a second one.

[inputs | split("\t") | {manifest: .[0], name: .[1], owner: .[2], repository: .[3], reference: .[4]}]
| {
    version: 0,
    sha: $sha,
    ref: $ref,
    job: ({correlator: $correlator, id: $run_id} + (if $run_url == "" then {} else {html_url: $run_url} end)),
    detector: {
      name: "seqan/actions/cpm_dependency_submission",
      version: $detector_version,
      url: "https://github.com/seqan/actions/tree/main/cpm_dependency_submission"
    },
    scanned: $scanned,
    manifests: (
      reduce .[] as $p ({};
        .[$p.manifest].name = $p.manifest
        | .[$p.manifest].file.source_location = $p.manifest
        | .[$p.manifest].resolved[$p.name] = {
            package_url: @uri "pkg:github/\($p.owner | ascii_downcase)/\($p.repository | ascii_downcase)@\($p.reference)",
            relationship: "direct"
          }
      )
    )
  }
