#!/bin/zsh
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")" && /bin/pwd -P)"
artifact="$project_root/build/MenuMonitor.app"
output_dir="$project_root/dist"
source_info_plist="$project_root/Resources/Info.plist"
scripts_dir="$project_root/Resources/Installer"

fail() {
    print -u2 -- "package-pkg.sh: $1"
    exit 1
}

[[ -f "$source_info_plist" ]] || fail "application Info.plist is missing."
[[ -f "$scripts_dir/postinstall" ]] || fail "postinstall script is missing."
source_bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_info_plist")"
[[ -n "$source_bundle_version" && "$source_bundle_version" != *[/\\]* ]] || fail "invalid source bundle version."
output_path="${1:-$output_dir/MenuMonitor-${source_bundle_version}-Installer.pkg}"
[[ "$output_path" == /* ]] || output_path="$project_root/$output_path"
output_path="$(/usr/bin/dirname -- "$output_path")/$(/usr/bin/basename -- "$output_path")"

/bin/mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && /bin/pwd -P)"
output_parent="$(/usr/bin/dirname -- "$output_path")"
[[ -d "$output_parent" ]] || fail "output directory must already exist under $output_dir."
output_parent="$(cd -- "$output_parent" && /bin/pwd -P)"
[[ "$output_parent" == "$output_dir" ]] || fail "package output must stay inside $output_dir."
output_name="$(/usr/bin/basename -- "$output_path")"
[[ "$output_name" == *.pkg && "$output_name" != .pkg ]] || fail "package output filename must end in .pkg."
[[ ! -L "$output_path" ]] || fail "refusing to overwrite a symbolic-link output path."
output_path="$output_dir/$output_name"

[[ -x /usr/bin/pkgbuild ]] || fail "pkgbuild is required on macOS."
[[ -x /usr/sbin/pkgutil ]] || fail "pkgutil is required on macOS."

"$project_root/build.sh" >/dev/null
[[ -d "$artifact" ]] || fail "build did not create MenuMonitor.app."
/usr/bin/codesign --verify --strict --deep "$artifact" >/dev/null \
    || fail "application signature validation failed."

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$artifact/Contents/Info.plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact/Contents/Info.plist")"
[[ "$bundle_identifier" == "com.local.menumonitor" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$bundle_version" == "$source_bundle_version" ]] || fail "built app version differs from source metadata."

staging_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/MenuMonitor-pkg.XXXXXXXX")"
cleanup() { /bin/rm -rf "$staging_root"; }
trap cleanup EXIT INT TERM
/bin/mkdir -p "$staging_root/Applications"
/usr/bin/ditto --rsrc --extattr --acl "$artifact" "$staging_root/Applications/MenuMonitor.app"
/bin/chmod 755 "$scripts_dir/postinstall"

/usr/bin/pkgbuild \
    --root "$staging_root" \
    --scripts "$scripts_dir" \
    --identifier "$bundle_identifier" \
    --version "$bundle_version" \
    --install-location / \
    --ownership recommended \
    --preserve-xattr \
    "$output_path" >/dev/null

[[ -s "$output_path" ]] || fail "pkgbuild did not create a readable package."
/usr/sbin/pkgutil --payload-files "$output_path" | /usr/bin/grep -Fq 'Applications/MenuMonitor.app/Contents/MacOS/MenuMonitor' \
    || fail "installer package payload is missing MenuMonitor.app."

print -- "Created: $output_path"
print -- "Install location: /Applications/MenuMonitor.app"
print -- "Signature: unsigned package carrying an ad-hoc signed app"
print -- "Validated: package payload and app bundle signature"
