#!/bin/bash
# Fn+Q changes the firmware platform_profile, but power-profiles-daemon (what the bar reads) doesn't notice.
# Wait for the firmware to announce a change and tell the daemon, so the bar follows the key. Started from custom/execs.lua.
pgrep -fx "python3 - platform-profile-sync" >/dev/null && exit 0   # already running
exec python3 - platform-profile-sync <<'PY'
import select, subprocess
PATH = '/sys/firmware/acpi/platform_profile'
MAP = {'low-power': 'power-saver', 'balanced': 'balanced', 'performance': 'performance'}
def ppd():
    return subprocess.run(['powerprofilesctl', 'get'], capture_output=True, text=True).stdout.strip()
f = open(PATH)
p = select.poll(); p.register(f, select.POLLPRI | select.POLLERR)
f.read()
while True:
    p.poll()
    f.seek(0); fw = f.read().strip()
    want = MAP.get(fw)
    if want and ppd() != want:
        subprocess.run(['powerprofilesctl', 'set', want], capture_output=True)
PY
