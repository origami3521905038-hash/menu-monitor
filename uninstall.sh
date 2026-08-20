#!/bin/zsh
set -euo pipefail

target="/Applications/MenuMonitor.app"
binary="$target/Contents/MacOS/MenuMonitor"
account_name="$(/usr/bin/id -un)"
user_home="$(/usr/bin/dscl . -read "/Users/$account_name" NFSHomeDirectory | /usr/bin/awk '/NFSHomeDirectory:/ { print $2; exit }')"
preferences_file="$user_home/Library/Preferences/com.local.menumonitor.plist"
support_directory="$user_home/Library/Application Support/MenuMonitor"

fail() {
    print -u2 -- "uninstall.sh: $1"
    exit 1
}

remove_as_needed() {
    if [[ -w "/Applications" ]]; then
        "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

[[ "$target" == "/Applications/MenuMonitor.app" ]] || fail "unexpected app path."
[[ "$user_home" == /Users/* && "$user_home" != "/" ]] || fail "could not validate the local user home directory."
[[ "$preferences_file" == "$user_home/Library/Preferences/com.local.menumonitor.plist" ]] || fail "unexpected preferences path."
[[ "$support_directory" == "$user_home/Library/Application Support/MenuMonitor" ]] || fail "unexpected support path."

if [[ -d "$target" ]]; then
    [[ -x "$binary" ]] || fail "installed app executable is missing; refusing to remove a login item blindly."
    if ! "$binary" --unregister-login-item; then
        login_status="$("$binary" --login-item-status 2>/dev/null || true)"
        [[ "$login_status" == "notRegistered" ]] || fail "launch-at-login removal failed (last status: ${login_status:-unknown})."
    fi

    for process_id in $(/usr/bin/pgrep -x MenuMonitor 2>/dev/null || true); do
        process_path="$(/bin/ps -p "$process_id" -o command= 2>/dev/null || true)"
        if [[ "$process_path" == "$binary"* ]]; then
            /bin/kill "$process_id" 2>/dev/null || true
        fi
    done
    remove_as_needed /bin/rm -rf "$target"
fi

/bin/rm -f "$preferences_file"
if [[ -d "$support_directory" ]]; then
    /bin/rm -rf "$support_directory"
fi

print -- "MenuMonitor was removed."
