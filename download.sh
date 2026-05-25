#!/bin/sh
# Download GCC 14.2.0 source and its prerequisites

set -e

GCC_VERSION="14.2.0"
GCC_URL="https://ftpmirror.gnu.org/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"

echo "Downloading GCC ${GCC_VERSION}..."
if [ ! -f "gcc-${GCC_VERSION}.tar.xz" ]; then
    curl -L "${GCC_URL}" -o "gcc-${GCC_VERSION}.tar.xz"
fi

echo "Extracting..."
if [ ! -d "gcc-${GCC_VERSION}" ]; then
    tar xf "gcc-${GCC_VERSION}.tar.xz"
fi

echo "Downloading prerequisites (GMP, MPFR, MPC)..."
echo "  (Alternatively: brew install gmp mpfr mpc)"
cd "gcc-${GCC_VERSION}"
./contrib/download_prerequisites
cd ..

echo "Done. Prerequisites are in gcc-${GCC_VERSION}/"
echo "Next: run ./configure.sh"
