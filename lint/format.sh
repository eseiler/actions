#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Formats the files a PR changed, in place, with the pinned clang-format and cmake-format.
#
# Why a script: the lint action runs in two places that must agree exactly.
#   - CI (`ci_lint.yml`): formats the PR checkout; if `git diff` then shows changes, Lint fails.
#   - Lint Autofix, job `prepare`: formats the PR head again; the result becomes the bot's formatting commit.
#
# Usage (in the work tree to format):
#   format.sh <base> <config-dir>
#
#   base        The PR's base commit. Only files changed since merge-base(<base>, HEAD) are considered.
#   config-dir  Directory with .clang-format and .cmake-format.yaml. These are the PR's own files, as before.
#
# Environment: CLANG_FORMAT, CMAKE_FORMAT and PYTHON (with PyYAML) point to the pinned tools; default: from PATH.
#
# Which files (unchanged from the old lint action):
#   - C++: changed *.cpp and *.hpp, except paths containing lib/, contrib/ or submodules/.
#   - CMake: if any such *.cmake or CMakeLists.txt changed, all tracked CMake files are formatted (the old
#     cmake-format-lint-action ran on `find . -name '*.cmake' -o -name CMakeLists.txt`).
#
# The work tree may come from an untrusted PR, so:
#   - File names are read NUL-delimited and passed as separate arguments after `--`, never split or interpreted.
#   - Symlinks and other non-regular files are skipped, so a formatter never writes outside the tree.
#   - .cmake-format.yaml is never given to cmake-format directly: cmake-format reads YAML with PyYAML's full loader,
#     which runs code on tags like `!!python/object/apply`. It is converted to JSON with `safe_load` first. Because
#     --config-files is given, cmake-format does not search for other config files (e.g. an executable
#     .cmake-format.py) either.

set -Eeuo pipefail

base=$1
config_dir=$2
clang_format=${CLANG_FORMAT:-clang-format}
cmake_format=${CMAKE_FORMAT:-cmake-format}
python=${PYTHON:-python3}

excluded='(lib/|contrib/|submodules/)' # matched anywhere in the path

# --- Which files did the PR change? -------------------------------------------------------------------------------

cpp_files=()
cmake_changed=false
while IFS= read -r -d '' file; do
    [[ ${file} =~ ${excluded} ]] && continue
    [[ -f ${file} && ! -L ${file} ]] || continue # regular files only, no symlinks
    case ${file} in
        *.cpp | *.hpp) cpp_files+=("${file}") ;;
        *.cmake | *CMakeLists.txt) cmake_changed=true ;;
        *) ;;
    esac
done < <(git diff -z --name-only --diff-filter=ACMRT --merge-base "${base}" --) # added/copied/modified/renamed/type

# --- C++ ------------------------------------------------------------------------------------------------------------

if ((${#cpp_files[@]} > 0)); then
    "${clang_format}" --style="file:${config_dir}/.clang-format" -i -- "${cpp_files[@]}"
fi

# --- CMake: once one CMake file changed, all of them -----------------------------------------------------------------

if ${cmake_changed}; then
    cmake_files=()
    while IFS= read -r -d '' file; do
        [[ -f ${file} && ! -L ${file} ]] || continue # regular files only, no symlinks
        cmake_files+=("${file}")
    done < <(git ls-files -z -- ':(glob)**/*.cmake' ':(glob)**/CMakeLists.txt')

    # The PR's YAML config, parsed safely and handed to cmake-format as JSON.
    config_json=$(mktemp --suffix=.json)
    "${python}" -I -c 'import json, sys, yaml; json.dump(yaml.safe_load(open(sys.argv[1])) or {}, open(sys.argv[2], "w"))' \
        "${config_dir}/.cmake-format.yaml" "${config_json}"
    if ((${#cmake_files[@]} > 0)); then
        "${cmake_format}" --config-files "${config_json}" --in-place -- "${cmake_files[@]}"
    fi
    rm -f "${config_json}"
fi
