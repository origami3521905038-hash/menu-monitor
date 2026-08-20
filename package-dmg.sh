#!/bin/zsh
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")" && /bin/pwd -P)"
artifact="$project_root/build/MenuMonitor.app"
output_dir="$project_root/dist"
installer_package="$output_dir/MenuMonitor-Installer.pkg"

fail() {
    print -u2 -- "package-dmg.sh: $1"
    exit 1
}

source_info_plist="$project_root/Resources/Info.plist"
[[ -f "$source_info_plist" ]] || fail "application Info.plist is missing."
source_bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_info_plist")"
[[ -n "$source_bundle_version" && "$source_bundle_version" != *[/\\]* ]] || fail "invalid source bundle version."
output_path="${1:-$output_dir/MenuMonitor-${source_bundle_version}-universal.dmg}"

[[ "$output_path" == /* ]] || output_path="$project_root/$output_path"
output_path="$(/usr/bin/dirname -- "$output_path")/$(/usr/bin/basename -- "$output_path")"

/bin/mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && /bin/pwd -P)"
output_parent="$(/usr/bin/dirname -- "$output_path")"
[[ -d "$output_parent" ]] || fail "output directory must already exist under $output_dir."
output_parent="$(cd -- "$output_parent" && /bin/pwd -P)"
[[ "$output_parent" == "$output_dir" ]] || fail "DMG output must stay inside $output_dir."
output_name="$(/usr/bin/basename -- "$output_path")"
[[ "$output_name" == *.dmg && "$output_name" != .dmg ]] || fail "DMG output filename must end in .dmg."
[[ ! -L "$output_path" ]] || fail "refusing to overwrite a symbolic-link output path."
output_path="$output_dir/$output_name"

[[ -x "/usr/bin/hdiutil" ]] || fail "hdiutil is required on macOS."
[[ -x "/usr/bin/lipo" ]] || fail "lipo is required on macOS."
[[ -x "/usr/bin/codesign" ]] || fail "codesign is required on macOS."
[[ -x "/usr/sbin/pkgutil" ]] || fail "pkgutil is required on macOS."

"$project_root/build.sh"
[[ -d "$artifact" ]] || fail "build did not create MenuMonitor.app."
/usr/bin/codesign --verify --strict --deep --verbose=2 "$artifact" >/dev/null \
    || fail "application signature validation failed."

"$project_root/package-pkg.sh" "$installer_package" >/dev/null
[[ -s "$installer_package" ]] || fail "installer package was not created."
/usr/sbin/pkgutil --payload-files "$installer_package" | /usr/bin/grep -Fq 'Applications/MenuMonitor.app/Contents/MacOS/MenuMonitor' \
    || fail "installer package payload is incomplete."

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$artifact/Contents/Info.plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact/Contents/Info.plist")"
[[ "$bundle_identifier" == "com.local.menumonitor" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$bundle_version" != "" && "$bundle_version" != *[/\\]* ]] || fail "invalid bundle version: $bundle_version"
[[ "$bundle_version" == "$source_bundle_version" ]] || fail "built app version differs from source metadata."

staging_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/MenuMonitor-dmg.XXXXXXXX")"
mounted_volume=""
cleanup() {
    if [[ -n "$mounted_volume" && -d "$mounted_volume" ]]; then
        /usr/bin/hdiutil detach "$mounted_volume" -force >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$staging_root"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$staging_root/MenuMonitor"
/usr/bin/ditto --rsrc --extattr --acl "$artifact" "$staging_root/MenuMonitor/MenuMonitor.app"
/usr/bin/ditto --rsrc --extattr --acl "$installer_package" "$staging_root/MenuMonitor/MenuMonitor-Installer.pkg"
/bin/ln -s /Applications "$staging_root/MenuMonitor/Applications"

/usr/bin/hdiutil create \
    -volname "性能简读" \
    -srcfolder "$staging_root/MenuMonitor" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$output_path" >/dev/null

[[ -s "$output_path" ]] || fail "hdiutil did not create a readable disk image."
image_format="$(/usr/bin/hdiutil imageinfo "$output_path" | /usr/bin/awk -F': ' '/^ *Format:/ { print $2; exit }')"
[[ "$image_format" == "UDZO" ]] || fail "unexpected DMG format: ${image_format:-unknown}"

attach_output="$(/usr/bin/hdiutil attach -nobrowse -readonly "$output_path")"
mounted_volume="$(print -- "$attach_output" | /usr/bin/awk 'match($0, /\/Volumes\/.*/) { print substr($0, RSTART); exit }')"
[[ -n "$mounted_volume" && -d "$mounted_volume" ]] || fail "could not determine the mounted DMG volume."

mounted_app="$mounted_volume/MenuMonitor.app"
mounted_package="$mounted_volume/MenuMonitor-Installer.pkg"
mounted_app_binary="$mounted_app/Contents/MacOS/MenuMonitor"
mounted_ui_binary="$mounted_app/Contents/PlugIns/MenuMonitorUI.bundle/Contents/MacOS/MenuMonitorUI"
[[ -d "$mounted_app" ]] || fail "DMG is missing MenuMonitor.app."
[[ -s "$mounted_package" ]] || fail "DMG is missing MenuMonitor-Installer.pkg."
[[ -L "$mounted_volume/Applications" ]] || fail "DMG is missing the Applications alias."
[[ "$(/usr/bin/readlink "$mounted_volume/Applications")" == "/Applications" ]] || fail "Applications alias points to the wrong location."
[[ -x "$mounted_app_binary" && -x "$mounted_ui_binary" ]] || fail "DMG contains an incomplete app bundle."

for binary in "$mounted_app_binary" "$mounted_ui_binary"; do
    architecture_list="$(/usr/bin/lipo -archs "$binary")"
    [[ "$architecture_list" == *arm64* && "$architecture_list" == *x86_64* ]] || fail "DMG binary is not universal: $binary ($architecture_list)"
done
/usr/bin/codesign --verify --strict --deep --verbose=2 "$mounted_app" >/dev/null
/usr/sbin/pkgutil --payload-files "$mounted_package" | /usr/bin/grep -Fq 'Applications/MenuMonitor.app/Contents/MacOS/MenuMonitor' \
    || fail "DMG installer package payload is incomplete."
/usr/bin/hdiutil detach "$mounted_volume" >/dev/null
mounted_volume=""

print -- "Created: $output_path"
print -- "Format: UDZO"
print -- "Architectures: arm64, x86_64"
print -- "Signature: ad-hoc (not notarized)"
print -- "Validated: app bundle, installer package, code signature, and /Applications alias"
