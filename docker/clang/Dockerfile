# syntax=docker/dockerfile:1

# SPDX-FileCopyrightText: 2006-2024 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2024 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

FROM debian:unstable-slim

ARG CLANG_VERSION

SHELL ["/bin/bash", "-Eeuxo", "pipefail", "-c"]

COPY docker_scripts /docker_scripts
COPY --from=common install_common_packages.sh /docker_scripts/
COPY --from=common show_versions.sh /docker_scripts/

RUN /docker_scripts/install_common_packages.sh && \
    /docker_scripts/install_packages.sh ${CLANG_VERSION} && \
    /docker_scripts/install_wrapper.sh ${CLANG_VERSION} && \
    /docker_scripts/install_symlinks.sh ${CLANG_VERSION} && \
    /docker_scripts/show_versions.sh

ENV CC=clang
ENV CXX=clang++
ENV OMP_TOOL_LIBRARIES=/usr/lib/llvm-${CLANG_VERSION}/lib/libarcher.so

ENV CCACHE_BASEDIR=/home/runner/
ENV CCACHE_DIR=/home/runner/.ccache
ENV CCACHE_COMPRESS=true
ENV CCACHE_COMPRESSLEVEL=12
ENV CCACHE_MAXSIZE=75M
ENV GNUMAKEFLAGS="-j4 --no-print-directory --output-sync=target"
ENV MAKEFLAGS="-j4 --no-print-directory --output-sync=target"
