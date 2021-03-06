#!/bin/bash

set -e

echo "moving into rust directory"

cd rust

echo "building rust code"

cargo build --release

echo "moving into project base directory"

cd ..

echo "copying dll"

cp rust/target/release/godot_gif_getter.dll addons/godot-gif-getter/godot_gif_getter.dll

echo "finished"
