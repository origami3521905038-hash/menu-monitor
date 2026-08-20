#!/bin/zsh
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")" && /bin/pwd -P)"
artifact="$project_root/build/MenuMonitor.app"
target="/Applications/MenuMonitor.app"
binary="$target/Contents/MacOS/MenuMonitor"

fail() {
    print -u2 -- "install.sh: $1"
    exit 1
}

install_as_needed() {
    if [[ -w "/Applications" ]]; then
        "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

[[ "$target" == "/Applications/MenuMonitor.app" ]] || fail "unexpected install path."
"$project_root/build.sh"
[[ -d "$artifact" && -x "$artifact/Contents/MacOS/MenuMonitor" ]] || fail "build did not create MenuMonitor.app."

terminate_installed_copy() {
    local process_id process_path
    for process_id in $(/usr/bin/pgrep -x MenuMonitor 2>/dev/null || true); do
        process_path="$(/bin/ps -p "$process_id" -o command= 2>/dev/null || true)"
        if [[ "$process_path" == "$binary"* ]]; then
            /bin/kill "$process_id" 2>/dev/null || true
        fi
    done
}

installed_process_id() {
    local process_id process_path
    for process_id in $(/usr/bin/pgrep -x MenuMonitor 2>/dev/null || true); do
        process_path="$(/bin/ps -p "$process_id" -o command= 2>/dev/null || true)"
        if [[ "$process_path" == "$binary"* ]]; then
            print -- "$process_id"
            return 0
        fi
    done
    return 1
}

terminate_installed_copy
if [[ -e "$target" ]]; then
    install_as_needed /bin/rm -rf "$target"
fi
install_as_needed /usr/bin/ditto "$artifact" "$target"
/usr/bin/codesign --verify --strict --deep --verbose=2 "$target"

/usr/bin/open -gj "$target"
launched_process=""
for _ in {1..40}; do
    launched_process="$(installed_process_id || true)"
    [[ -n "$launched_process" ]] && break
    /bin/sleep 0.25
done
[[ -n "$launched_process" ]] || fail "MenuMonitor did not launch from the installed app. Gatekeeper may require a one-time approval in Privacy & Security."

if ! "$binary" --register-login-item; then
    fail "launch-at-login registration failed. The app remains installed for inspection."
fi

login_status=""
for _ in {1..20}; do
    login_status="$("$binary" --login-item-status 2>/dev/null || true)"
    [[ "$login_status" == "enabled" ]] && break
    /bin/sleep 0.25
done
[[ "$login_status" == "enabled" ]] || fail "launch-at-login did not reach enabled status (last status: ${login_status:-unknown})."

[[ -n "$(installed_process_id || true)" ]] || fail "MenuMonitor stopped after login-item registration. The app remains installed for inspection."

print -- "Installed: $target"
print -- "Launch at login: enabled"
print -- "This local ad-hoc build is not notarized. macOS may require a one-time approval in Privacy & Security on another Mac."
