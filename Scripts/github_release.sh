#!/bin/zsh
# Checks and publishes the GitHub release that make publish creates as a draft.
#
#   Scripts/github_release.sh verify [version]    # make verify-release [VERSION=x.y.z]
#   Scripts/github_release.sh go-live [version]   # make go-live [VERSION=x.y.z]
#
# verify downloads the release's assets (a draft too) and checks what users will get:
# - the assets are all there and match the release's SHA256SUMS
# - the DMG is signed by Developer ID, notarized, stapled and accepted by Gatekeeper
# - the app inside it verifies, is accepted by Gatekeeper and carries this version
#
# go-live runs verify, then publishes the draft as the latest release (which creates the tag).
#
# The version defaults to MARKETING_VERSION in project.yml.
set -euo pipefail

root=${0:A:h:h}
cd "$root"
mode=${1:-}
[[ $mode == verify || $mode == go-live ]] \
  || { echo "usage: Scripts/github_release.sh verify|go-live [version]" >&2; exit 2; }

fail() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }
ok() { echo "    ok: $*"; }

repo=gicek/LaunchSweep
version=${2:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)}
tag=v$version
dmg_name=LaunchSweep-$version.dmg

command -v gh >/dev/null || fail "gh is missing; brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run gh auth login."

is_draft=$(gh release view "$tag" -R "$repo" --json isDraft --jq .isDraft 2>/dev/null) \
  || fail "No GitHub release $tag; create a draft with make publish."
release_url=$(gh release view "$tag" -R "$repo" --json url --jq .url)
asset_names=$(gh release view "$tag" -R "$repo" --json assets --jq '.assets[].name')

# Set at the top level: in zsh, an EXIT trap set inside a function runs when the function returns.
# The mounted copy gets registered with Launch Services; drop it before deleting.
tmp=$(mktemp -d)
# Each step may fail (the DMG is usually detached already); with set -e, a failure would end the trap.
trap 'hdiutil detach -quiet "$tmp/mnt" 2>/dev/null || true
  "$root/Scripts/unregister_apps.sh" "$tmp" || true; rm -rf "$tmp"' EXIT

verify() {
  step "Verifying GitHub release $tag ($([[ $is_draft == true ]] && echo draft || echo published))"
  echo "    $release_url"

  # Assets and checksums.
  for name in "$dmg_name" SHA256SUMS; do
    [[ $'\n'$asset_names$'\n' == *$'\n'$name$'\n'* ]] || fail "The release has no $name."
  done
  gh release download "$tag" -R "$repo" -D "$tmp/assets" -p "$dmg_name" -p SHA256SUMS
  (cd "$tmp/assets" && shasum -a 256 -c --quiet SHA256SUMS) || fail "An asset does not match SHA256SUMS."
  ok "assets present and matching SHA256SUMS"

  # The DMG people download, and the app inside it.
  local dmg=$tmp/assets/$dmg_name app=$tmp/mnt/LaunchSweep.app
  codesign --verify --strict "$dmg" || fail "$dmg_name: the signature does not verify."
  xcrun stapler validate -q "$dmg" || fail "$dmg_name: no notarization ticket is stapled."
  spctl -a -t open --context context:primary-signature "$dmg" 2>/dev/null \
    || fail "$dmg_name: Gatekeeper rejects it."
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$tmp/mnt" "$dmg"
  [[ -L $tmp/mnt/Applications ]] || fail "$dmg_name has no Applications link."
  codesign --verify --deep --strict "$app" || fail "The app in $dmg_name does not verify."
  spctl -a -t exec "$app" 2>/dev/null || fail "Gatekeeper rejects the app in $dmg_name."
  local plist=$app/Contents/Info.plist
  local found=$(plutil -extract CFBundleShortVersionString raw "$plist")
  local build=$(plutil -extract CFBundleVersion raw "$plist")
  [[ $found == "$version" ]] || fail "The app in $dmg_name is version $found, expected $version."
  hdiutil detach -quiet "$tmp/mnt"
  ok "$dmg_name: Developer ID, notarized and stapled, LaunchSweep $version ($build) inside"

  if [[ $is_draft == true && $mode != go-live ]]; then
    echo "    Draft: not live yet. Publish it with make go-live."
  fi
}

verify
if [[ $mode == go-live ]]; then
  [[ $is_draft == true ]] || { echo "==> $tag is already published."; exit 0; }
  step "Publishing $tag as the latest release"
  gh release edit "$tag" -R "$repo" --draft=false --latest >/dev/null
  git fetch --quiet --tags origin
  ok "live: LaunchSweep $version is the latest release"
  echo "    $(gh release view "$tag" -R "$repo" --json url --jq .url)"
fi
