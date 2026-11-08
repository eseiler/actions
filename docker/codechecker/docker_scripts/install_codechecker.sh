#!/bin/bash -l

# SPDX-FileCopyrightText: 2006-2025 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2025 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

set -Eeuxo pipefail

CODECHECKER_VERSION=$1

apt-get update 1>/dev/null
apt-get install --yes --no-install-recommends \
    python3-venv \
    python3-dev \
    cppcheck \
    openssh-client \
    rsync \
    1>/dev/null
rm -rf /var/lib/apt/lists/*

python3 -m venv /venv/codechecker
/venv/codechecker/bin/pip --quiet --quiet install codechecker=="${CODECHECKER_VERSION}"

patch_dir=$(find /venv/codechecker/ -type d -name "codechecker_report_converter")
patch --batch --forward --quiet --reject-file=- --directory="${patch_dir}" --strip=4 </docker_scripts/codechecker_report_converter.patch || true

patch_dir=$(find /venv/codechecker/ -type d -name "codechecker_analyzer")
patch --batch --forward --quiet --reject-file=- --directory="${patch_dir}" --strip=3 </docker_scripts/codechecker_analyzer.patch || true

