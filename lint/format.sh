#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0
#
# Format the work tree in the current directory in place.
#
#   format.sh <base> <config-dir>
#
#   base        Commit the PR is based on. C++ files changed since merge-base(<base>, HEAD) are formatted.
#               If any CMake file changed, all tracked CMake files are formatted (as the former
#               cmake-format-lint-action did with `find . -name '*.cmake' -o -name CMakeLists.txt`).
#   config-dir  Directory containing .clang-format and .cmake-format.yaml (the PR's own, as before). Both are
#               treated as data: .clang-format is plain YAML for LLVM, .cmake-format.yaml is converted (see below).
#
# File names are handled NUL-delimited and never pass through ${{ }} or word splitting.

set -Eeuo pipefail

base=$1
cfg=$2
clang_format=${CLANG_FORMAT:-clang-format}
cmake_format=${CMAKE_FORMAT:-cmake-format}
python=${PYTHON:-python3} # needs PyYAML

cpp=()
cmake_changed=false
while IFS= read -r -d '' f; do
    [[ ${f} =~ (lib/|contrib/|submodules/) ]] && continue # same filter as before
    [[ -f ${f} && ! -L ${f} ]] || continue                # regular files only
    case ${f} in
        *.cpp | *.hpp) cpp+=("${f}") ;;
        *.cmake | *CMakeLists.txt) cmake_changed=true ;;
        *) ;;
    esac
done < <(git diff -z --name-only --diff-filter=ACMRT --merge-base "${base}" --)

if ((${#cpp[@]})); then
    "${clang_format}" --style="file:${cfg}/.clang-format" -i -- "${cpp[@]}"
fi

if ${cmake_changed}; then
    cmake=()
    while IFS= read -r -d '' f; do
        [[ -f ${f} && ! -L ${f} ]] && cmake+=("${f}")
    done < <(git ls-files -z -- ':(glob)**/*.cmake' ':(glob)**/CMakeLists.txt')
    # cmake-format loads YAML with PyYAML's full Loader, so a PR-controlled .cmake-format.yaml can run arbitrary
    # code (!!python/object/apply). Convert it with safe_load and hand cmake-format the JSON instead.
    json=$(mktemp --suffix=.json)
    "${python}" -I -c 'import json, sys, yaml; json.dump(yaml.safe_load(open(sys.argv[1])) or {}, open(sys.argv[2], "w"))' \
        "${cfg}/.cmake-format.yaml" "${json}"
    "${cmake_format}" --config-files "${json}" --in-place -- "${cmake[@]}"
    rm -f "${json}"
fi
