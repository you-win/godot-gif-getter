#!/bin/bash
set -euo pipefail

declare -r SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

declare -r BASE_LIBRARY_NAME="godot_gif_getter"
declare -r WIN_LIBRARY_NAME="${BASE_LIBRARY_NAME}.dll"
declare -r OSX_LIBRARY_NAME="lib${BASE_LIBRARY_NAME}.dylib"

case "$(uname -s)" in
  Darwin)
    LIBRARY_NAME="${OSX_LIBRARY_NAME}"
    ;;
  CYGWIN*|MINGW32*|MSYS*|MINGW*)
    LIBRARY_NAME="${WIN_LIBRARY_NAME}"
    ;;
  *)
    echo "ERROR: OS Not Supported"
    exit 1
    ;;
esac

echo -e "Building Rust code..."
cargo build --release --manifest-path "${SCRIPT_DIR}"/rust/Cargo.toml

echo -e "\nCopying DLL into addon directory..."
cp -v "${SCRIPT_DIR}"/rust/target/release/"${LIBRARY_NAME}" "${SCRIPT_DIR}"/addons/godot-gif-getter/"${LIBRARY_NAME}"

echo -e "\nFinished!"
