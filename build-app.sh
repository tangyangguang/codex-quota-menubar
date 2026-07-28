#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
output_dir="$project_dir/outputs"
app_dir="$output_dir/Codex 额度.app"

cd "$project_dir"
swift test
# 同时构建 Apple Silicon (arm64) 与 Intel (x86_64) 两种架构，
# 生成 universal binary，使任意 Mac 都能运行。
swift build -c release --arch arm64 --arch x86_64

# universal 构建的产物位于 apple/Products/Release，单架构则在 release/。
if [[ -f "$project_dir/.build/apple/Products/Release/CodexQuota" ]]; then
    binary_path="$project_dir/.build/apple/Products/Release/CodexQuota"
else
    binary_path="$project_dir/.build/release/CodexQuota"
fi

# Recreate only this script's generated application bundle.
if [[ -d "$app_dir" ]]; then
    /bin/rm -rf "$app_dir"
fi
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_path" "$app_dir/Contents/MacOS/CodexQuota"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod 755 "$app_dir/Contents/MacOS/CodexQuota"

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
