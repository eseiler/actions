#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2006-2025 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2025 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

set -Eeuo pipefail

case "$1" in
    gcc-latest)
        COMPILER="gcc-16"
        ;;
    gcc-second-latest)
        COMPILER="gcc-15"
        ;;
    gcc-third-latest)
        COMPILER="gcc-14"
        ;;
    *)
        COMPILER="$1"
        ;;
esac

install "${COMPILER}"
echo "CC=${COMPILER}" >> "${GITHUB_ENV}"
echo "CXX=${COMPILER/gcc/g++}" >> "${GITHUB_ENV}"
