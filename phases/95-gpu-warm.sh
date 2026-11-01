#!/usr/bin/env bash
# Keep GPU + CPU "warm" (full performance) on AC, and on battery until it drops below ${LOW_BATT_PCT:-10}%, so the first window/animation after idle isn't laggy
# Why: the GPU idles at P8 (210 MHz); the first frame after a quiet spell (e.g. spawning foot after a while in VS Code) waits for it to clock up.
#   On AC: persistence daemon + graphics clock floor of ${GPU_MIN_MHZ:-1200} MHz (max stays 3105) + memory clock floor of ${GPU_MEM_MIN_MHZ:-6001} MHz
#   (max 8001; the memory clock otherwise idles at 810 and the first blur/animation frame waits for it). On battery below the threshold: floors released.
#   Hybrid BIOS mode (Intel iGPU on the PCI bus): the iGPU gets a ${IGPU_MIN_MHZ:-900} MHz floor on AC instead and NVIDIA is left alone so it can sleep (see docs/hybrid-graphics.md),
#   except in monitor mode (~/.config/hyprland-ii/render-nvidia, no gpu-passthrough: the 4070 draws the desktop), which gets the NVIDIA floors too.
#   Re-applied by vm-gpu-nvidia on every session mode switch.
#   Re-applied on AC plug/unplug (udev), boot, resume from sleep, and by a 1-minute timer that only acts when the battery crosses the threshold.
# Also sets power profile performance/balanced (CPU governor stays powersave: EPP=performance via the profile does the work, and a performance governor blocks profile changes).
# Rollback: sudo systemctl disable --now gpu-warm.service; sudo systemctl stop nvidia-persistenced; sudo systemctl disable --now gpu-warm-check.timer; sudo rm /etc/systemd/system/gpu-warm-check.* /etc/systemd/system/gpu-warm.service /etc/udev/rules.d/99-gpu-warm.rules /usr/local/sbin/gpu-warm; sudo nvidia-smi -rgc; sudo nvidia-smi -rmc
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw
LOW="${LOW_BATT_PCT:-10}"           # on battery, full performance until the charge drops below this
MIN="${GPU_MIN_MHZ:-1200}"
IGPU_MIN="${IGPU_MIN_MHZ:-900}"       # Hybrid: Intel iGPU floor on AC (its max is ~1650)
MEM_MIN="${GPU_MEM_MIN_MHZ:-6001}"   # a supported memory clock: nvidia-smi -q -d SUPPORTED_CLOCKS (405 810 6001 7001 8001)

step "gpu-warm script"
sudo tee /usr/local/sbin/gpu-warm >/dev/null <<SCRIPT
#!/bin/sh
# Full performance (profile/governor + GPU clock floors) on AC or while the battery is >= $LOW%; below that -> release, balanced/powersave.
#   'gpu-warm check' (1-minute timer) only re-applies when that decision changed.
# Which GPU gets the floors depends on the BIOS graphics mode, decided here at run time (an Intel iGPU on the PCI bus = Hybrid):
#   dGPU-only (MUX): NVIDIA draws the desktop -> graphics floor $MIN..max, memory floor $MEM_MIN..max, nvidia-persistenced running.
#   Hybrid: the iGPU draws the desktop -> iGPU floor $IGPU_MIN MHz on AC. NVIDIA is left alone (nvidia-smi and persistenced would
#   wake it / pin it awake): its clock locks are only released if it is awake, and it runtime-suspends (D3) when nothing uses it.
#   Hybrid monitor mode (a user has ~/.config/hyprland-ii/render-nvidia and no gpu-passthrough, the session wrapper's rule): the 4070
#   draws the desktop and is awake anyway, so it gets the dGPU-only floors and persistenced as well (it idled at P8/810 MHz memory
#   and the first workspace switch after a quiet spell stuttered, 2026-10-27).
ac=0; for f in /sys/class/power_supply/*/; do [ "\$(cat \$f/type 2>/dev/null)" = Mains ] && [ "\$(cat \$f/online 2>/dev/null)" = 1 ] && ac=1; done
hybrid=0; for d in /sys/bus/pci/devices/*; do [ "\$(cat \$d/vendor)" = 0x8086 ] && case "\$(cat \$d/class)" in 0x03*) hybrid=1;; esac; done
bat=100; for f in /sys/class/power_supply/*/; do [ "\$(cat \$f/type 2>/dev/null)" = Battery ] && bat=\$(cat \$f/capacity); done
full=0; { [ "\$ac" = 1 ] || [ "\$bat" -ge $LOW ]; } && full=1
if [ "\$1" = check ] && [ "\$(cat /run/gpu-warm.state 2>/dev/null)" = "\$full" ]; then exit 0; fi
echo "\$full" > /run/gpu-warm.state
nvdraws=\$((1 - hybrid)); for h in /home/*/.config/hyprland-ii; do [ -e "\$h/render-nvidia" ] && [ ! -e "\$h/gpu-passthrough" ] && nvdraws=1; done
nv() { # nvidia-smi only when the dGPU drives the desktop, or is already awake in hybrid (don't wake a suspended GPU)
  [ "\$hybrid" = 0 ] || [ "\$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)" = active ] || return 0
  nvidia-smi "\$@"
}
pp() { for i in 1 2 3 4 5; do powerprofilesctl set \$1 2>/dev/null && return; sleep 1; done; }   # retry: power-profiles-daemon answers "busy" when two udev AC events race
igpu() { for g in /sys/class/drm/card[0-9]/gt_min_freq_mhz; do [ -w "\$g" ] || continue; d=\$(dirname \$g); [ "\$(cat \$d/device/vendor)" = 0x8086 ] || continue
  if [ "\$1" = floor ]; then echo $IGPU_MIN > \$g; else cat \$d/gt_RPn_freq_mhz > \$g; fi; done; }
if [ "\$nvdraws" = 0 ]; then systemctl stop nvidia-persistenced 2>/dev/null; else systemctl start nvidia-persistenced 2>/dev/null; fi
# intel_pstate refuses EPP writes (EBUSY) while the governor is "performance", which breaks power-profiles-daemon (the bar
# toggle, and the firmware platform_profile it writes). Keep powersave; the performance profile sets EPP=performance instead.
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > \$g; done
if [ "\$full" = 1 ]; then
  if [ "\$nvdraws" = 1 ]; then
    max=\$(nvidia-smi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits | head -1)
    nvidia-smi -lgc $MIN,\$max
    mmax=\$(nvidia-smi --query-gpu=clocks.max.memory --format=csv,noheader,nounits | head -1)
    nvidia-smi -lmc $MEM_MIN,\$mmax
  fi
  [ "\$hybrid" = 1 ] && igpu floor
  pp performance
  # pp is a no-op when the daemon already says performance, so write the firmware mode (Fn+Q, power LED) directly.
  # Legion firmware only allows performance (red) on AC; on battery it tops out at balanced (white) and overrides anything higher.
  if [ "\$ac" = 1 ]; then echo performance > /sys/firmware/acpi/platform_profile 2>/dev/null; else echo balanced > /sys/firmware/acpi/platform_profile 2>/dev/null; fi
  # governor stays powersave: with intel_pstate (HWP) the performance profile sets EPP=performance, which is equivalent, and a
  # "performance" governor would make EPP writes fail, breaking the bar toggle
else
  nv -rgc
  nv -rmc
  [ "\$hybrid" = 1 ] && igpu release
  pp balanced
  echo balanced > /sys/firmware/acpi/platform_profile 2>/dev/null
  for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > \$g; done
fi
SCRIPT
sudo chmod 755 /usr/local/sbin/gpu-warm

step "systemd unit + udev trigger"
sudo tee /etc/systemd/system/gpu-warm.service >/dev/null <<'UNIT'
[Unit]
Description=Keep GPU/CPU clocks warm on AC
Wants=nvidia-persistenced.service
After=nvidia-persistenced.service systemd-suspend.service systemd-hibernate.service systemd-suspend-then-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gpu-warm

[Install]
WantedBy=multi-user.target suspend.target hibernate.target suspend-then-hibernate.target
UNIT
sudo tee /etc/systemd/system/gpu-warm-check.service >/dev/null <<'UNIT'
[Unit]
Description=Re-check the battery threshold for full performance

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gpu-warm check
UNIT
sudo tee /etc/systemd/system/gpu-warm-check.timer >/dev/null <<'UNIT'
[Unit]
Description=Re-check the battery threshold for full performance every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
UNIT
echo 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", TAG+="systemd", ENV{SYSTEMD_WANTS}+="gpu-warm.service"' | sudo tee /etc/udev/rules.d/99-gpu-warm.rules >/dev/null
sudo systemctl daemon-reload
sudo udevadm control --reload
# nvidia-persistenced is a static unit: pulled in via Wants= in gpu-warm.service
sudo systemctl enable gpu-warm.service
sudo systemctl restart gpu-warm.service
sudo systemctl enable --now gpu-warm-check.timer

step "Fn+Q -> bar: platform-profile watcher"
install -Dm755 "$(dirname "$0")/../templates/scripts/platform-profile-sync.sh" ~/.config/hypr/custom/scripts/platform-profile-sync.sh
EXECS="$HOME/.config/hypr/custom/execs.lua"
if grep -q platform-profile-sync.sh "$EXECS" 2>/dev/null; then echo "exec already present"; else
  cat >> "$EXECS" <<'EOF2'

-- Fn+Q (firmware power mode) -> power-profiles-daemon, so the bar icon follows the key (custom/scripts/platform-profile-sync.sh)
hl.on("hyprland.start", function ()
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/platform-profile-sync.sh")
end)
EOF2
fi
pgrep -f 'platform-profile-sync' >/dev/null || (setsid ~/.config/hypr/custom/scripts/platform-profile-sync.sh >/dev/null 2>&1 &)

step "Check"
sleep 1
if lspci | grep -qiE 'VGA.*Intel|Display.*Intel'; then   # Hybrid: nvidia-smi would wake the sleeping GPU
  echo "Hybrid: iGPU floor $(cat /sys/class/drm/card[0-9]/gt_min_freq_mhz | tr '\n' ' ')MHz on AC; NVIDIA runtime status: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status)"
else
  nvidia-smi --query-gpu=pstate,clocks.gr,power.draw,persistence_mode --format=csv
fi
ok "Clocks set for the current power source (floors up on AC or battery >= $LOW%; released below)."
