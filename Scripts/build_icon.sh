#!/bin/zsh
# Regenerates the app icon in the asset catalog from design/logo. Run it with make icon.
# Requires Node (the SVG is rendered by resvg through npx, pinned below). The output is committed,
# so builds never need it.
set -euo pipefail

command -v npx >/dev/null || { echo "error: npx is missing; install Node (brew install node)." >&2; exit 1; }

root=${0:A:h:h}
logo=$root/design/logo/launchsweep-icon-1024.svg
appicon=$root/LaunchSweep/Resources/Assets.xcassets/AppIcon.appiconset

render() {
  npx -y --quiet @resvg/resvg-js-cli@2.6.2-beta.1 --log-level error --no-system-font \
    --fit-width "$1" "$logo" "$2" >/dev/null
}

for size in 16 32 128 256 512; do
  render $size "$appicon/icon_${size}x${size}.png"
  render $((size * 2)) "$appicon/icon_${size}x${size}@2x.png"
done
echo "Icon written to $appicon"
