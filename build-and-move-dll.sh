#!/bin/bash

echo "building rust code"

cargo build --release

echo "copying dll"

cp target/release/godot_gif_getter.dll addons/godot-gif-getter/godot_gif_getter.dll

echo "finished"
