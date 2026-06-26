#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Generates a reproducible vendored Go-module tarball for telegraf.
#
# The custom (minimal-plugin) build still vendors the *full* dependency tree so
# the build is hermetic and offline; only the selected plugins are compiled in
# (see %{buildtags} in telegraf.spec). Pruning vendor/ is intentionally NOT
# done — it would break reproducibility and `go mod verify`.
#
# Usage:
#   ./generate_source_tarball.sh --srcTarball <path> --pkgVersion <version> [--outFolder <dir>]

set -e

get_param() {
    if [ -n "${2}" ] && [ "${2:0:1}" != "-" ]; then
        echo "${2}"
    else
        echo "Error: argument for (${1}) is missing." >&2
        return 1
    fi
}

PKG_VERSION=""
SRC_TARBALL=""
OUT_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

while (( "$#" )); do
    case "${1}" in
        --srcTarball)
            SRC_TARBALL="$(get_param "${1}" "${2}")"
            shift 2
            ;;
        --outFolder)
            OUT_FOLDER="$(get_param "${1}" "${2}")"
            shift 2
            ;;
        --pkgVersion)
            PKG_VERSION="$(get_param "${1}" "${2}")"
            shift 2
            ;;
        -*)
            echo "Error: unsupported flag ${1}." >&2
            exit 1
            ;;
    esac
done

echo "--srcTarball   -> ${SRC_TARBALL}"
echo "--outFolder    -> ${OUT_FOLDER}"
echo "--pkgVersion   -> ${PKG_VERSION}"

if [ -z "${PKG_VERSION}" ]; then
    echo "Error: --pkgVersion parameter cannot be empty." >&2
    exit 1
fi

if [ ! -f "${SRC_TARBALL}" ]; then
    echo "Error: --srcTarball is not a file." >&2
    exit 1
fi

SRC_TARBALL="$(realpath "${SRC_TARBALL}")"
# Create the output folder up front so realpath can resolve the (not-yet-existing)
# vendor archive path below, and so a nested --outFolder works on a clean tree.
mkdir -p "${OUT_FOLDER}"
OUT_FOLDER="$(realpath "${OUT_FOLDER}")"

echo "Creating a tempdir."
tmpdir=$(mktemp -d)
function cleanup {
    echo "Clean-up: removing tempdir (${tmpdir})."
    rm -rf "${tmpdir}"
}
trap cleanup EXIT

pushd "${tmpdir}" > /dev/null

NAME_VER="telegraf-${PKG_VERSION}"
# Fedora forge macros expect the vendor archive as %{archivename}-vendor.tar.bz2.
VENDOR_TARBALL="$(realpath "${OUT_FOLDER}/${NAME_VER}-vendor.tar.bz2")"

echo "Unpacking the source tarball."
tar -xf "${SRC_TARBALL}"

cd "${NAME_VER}"
echo "Getting the vendored modules."
go mod vendor


echo "Tar vendored modules (deterministic flags for reproducibility)."
# Reproducible mtime: honor SOURCE_DATE_EPOCH when the build provides it (the same
# knob rpm/Fedora use), else fall back to the Unix epoch. The exact value doesn't
# matter for reproducibility — only that it's constant — so we pin a documented
# epoch rather than an arbitrary date. --clamp-mtime caps anything newer.
tar  --sort=name \
     --mtime="@${SOURCE_DATE_EPOCH:-0}" --clamp-mtime \
     --owner=0 --group=0 --numeric-owner \
     --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
     -cjf "${VENDOR_TARBALL}" vendor

popd > /dev/null

echo "Telegraf vendored modules are available at (${VENDOR_TARBALL})."
echo "SHA512: $(sha512sum "${VENDOR_TARBALL}")."
