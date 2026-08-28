# syntax=docker/dockerfile:1

# SPDX-FileCopyrightText: 2006-2025 Knut Reinert & Freie Universität Berlin
# SPDX-FileCopyrightText: 2016-2025 Knut Reinert & MPI für molekulare Genetik
# SPDX-License-Identifier: CC-BY-4.0

# 20 is just a default value in case no version is provided
ARG CLANG_VERSION=22
FROM ghcr.io/seqan/clang-${CLANG_VERSION}

ARG CLANG_VERSION
ARG CODECHECKER_VERSION

COPY docker_scripts /docker_scripts

RUN /docker_scripts/install_codechecker.sh ${CODECHECKER_VERSION}

ENV CC_ANALYZER_BIN=clangsa:/usr/bin/clang-${CLANG_VERSION};clang-tidy:/usr/bin/clang-tidy-${CLANG_VERSION}
ENV PATH=/venv/codechecker/bin:${PATH}
ENV VIRTUAL_ENV=/venv/codechecker
ENV VIRTUAL_ENV_PROMPT=codechecker
