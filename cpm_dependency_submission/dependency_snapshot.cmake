# SPDX-FileCopyrightText: 2006-2026 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2026 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# Lists the GitHub packages of a CPM package lock and the CPM version, for dependency_snapshot.jq.
#
#   cmake -D SOURCE_DIR=<work-tree> -D PACKAGE_LOCK=<path> -D OUTPUT=<file> -P dependency_snapshot.cmake
#
# PACKAGE_LOCK is relative to SOURCE_DIR. OUTPUT has one line per package, tab-separated:
#   manifest, name, owner, repository, tag or commit
#
# The lock file is evaluated by CMake, with a stand-in for CPMDeclarePackage. Unlike a regex over the text, this
# expands variables and ignores commented-out declarations. The reference is the one CPM fetches: GIT_TAG, otherwise
# v${VERSION}. Supported are GITHUB_REPOSITORY and GitHub source archives (URL); other packages are skipped with a
# warning, local archives (URL without scheme) silently.
# CPM itself is cpm-cmake/CPM.cmake@v<CPM_DOWNLOAD_VERSION>, one manifest per CPM.cmake.

cmake_minimum_required (VERSION 3.25)

function (warn text)
    string (REPLACE "%" "%25" text "${text}")
    string (REPLACE "\n" "%0A" text "${text}")
    message (NOTICE "::warning title=Dependency snapshot::${text}")
endfunction ()

set (output "")

file (GLOB_RECURSE cpm_files
      RELATIVE "${SOURCE_DIR}"
      "${SOURCE_DIR}/CPM.cmake")
foreach (cpm_file IN LISTS cpm_files)
    file (STRINGS "${SOURCE_DIR}/${cpm_file}" lines REGEX "CPM_DOWNLOAD_VERSION[ \t]+[0-9]")
    if (lines MATCHES "CPM_DOWNLOAD_VERSION[ \t]+([0-9][^ \t)]*)")
        string (APPEND output "${cpm_file}\tCPM.cmake\tcpm-cmake\tCPM.cmake\tv${CMAKE_MATCH_1}\n")
    else ()
        warn ("${cpm_file}: CPM skipped, no set (CPM_DOWNLOAD_VERSION <version>).")
    endif ()
endforeach ()

# Same rule as CPM: the first declaration of a name wins.
function (CPMDeclarePackage name)
    get_property (names GLOBAL PROPERTY CPM_DECLARED)
    if (NOT name IN_LIST names)
        set_property (GLOBAL APPEND PROPERTY CPM_DECLARED "${name}")
        set_property (GLOBAL PROPERTY "CPM_DECLARATION_${name}" "${ARGN}")
    endif ()
endfunction ()

# A scope of its own, so that the lock file cannot change the variables of this script.
# cmake-format: off
block (SCOPE_FOR VARIABLES)
    include ("${SOURCE_DIR}/${PACKAGE_LOCK}")
endblock ()
# cmake-format: on

get_property (names GLOBAL PROPERTY CPM_DECLARED)
foreach (name IN LISTS names)
    get_property (declaration GLOBAL PROPERTY "CPM_DECLARATION_${name}")
    # Only the keywords that are read. CPM's other keywords would only matter if one of their values were one of these.
    cmake_parse_arguments (arg "" "VERSION;GIT_TAG;GITHUB_REPOSITORY" "URL" ${declaration})

    set (reference "")
    if (DEFINED arg_GIT_TAG)
        set (reference "${arg_GIT_TAG}")
    elseif (DEFINED arg_VERSION)
        set (reference "v${arg_VERSION}")
    endif ()

    if ("${arg_GITHUB_REPOSITORY}" MATCHES "^([^/]+)/([^/]+)$")
        set (repository "${CMAKE_MATCH_1}\t${CMAKE_MATCH_2}")
    elseif ("${arg_URL}" MATCHES
            "^https://github\\.com/([^/]+)/([^/]+)/archive/(refs/(heads|tags)/)?([^;]+)\\.(tar\\.gz|zip)(;|$)")
        set (repository "${CMAKE_MATCH_1}\t${CMAKE_MATCH_2}")
        set (reference "${CMAKE_MATCH_5}")
    elseif (DEFINED arg_URL AND NOT "${arg_URL}" MATCHES "^[a-z]+://")
        message (STATUS "${name}: local archive, skipped.")
        continue ()
    else ()
        warn ("${name}: skipped, only GITHUB_REPOSITORY and GitHub source archives (URL) are supported.")
        continue ()
    endif ()

    if (reference STREQUAL "")
        warn ("${name}: skipped, neither GIT_TAG nor VERSION is set.")
        continue ()
    endif ()

    string (APPEND output "${PACKAGE_LOCK}\t${name}\t${repository}\t${reference}\n")
endforeach ()

message (STATUS "Packages:\n${output}")
file (WRITE "${OUTPUT}" "${output}")
