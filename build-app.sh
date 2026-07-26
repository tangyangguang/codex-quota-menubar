#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
output_dir="$project_dir/outputs"
app_dir="$output_dir/Codex 额度.app"

cd "$project_dir"
swift test
swift build -c release

# Recreate only this script's generated application bundle.
if [[ -d "$app_dir" ]]; then
    /bin/rm -rf "$app_dir"
fi
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/.build/release/CodexQuota" "$app_dir/Contents/MacOS/CodexQuota"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod 755 "$app_dir/Contents/MacOS/CodexQuota"

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
