import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Metered connection (bin/metered-guard): sets NetworkManager's "metered" flag on the active connection, which the guard follows by pausing
// Syncthing and unplugging the Windows VM's network. The flag is the single source of truth: nmcli / nm-connection-editor changes show up here.
//   On  -> connection.metered yes      Off -> connection.metered no   (a hotspot NM merely guesses as metered shows "On" too)
QuickToggleModel {
    id: root
    name: Translation.tr("Metered")
    icon: toggled ? "data_saver_on" : "data_saver_off"
    toggled: false
    statusText: busy ? Translation.tr("Applying…") : (toggled ? (remoteDesktop ? Translation.tr("On · remote desktop still uses data") : paused ? Translation.tr("On · %1 paused").arg(paused) : Translation.tr("On")) : Translation.tr("Off"))
    tooltipText: Translation.tr("Mark the current connection as metered: Syncthing and the Windows VM's network pause until you turn it off.")

    property bool busy: false
    property string dev: ""
    property string conn: ""
    property string paused: ""
    property bool remoteDesktop: false

    mainAction: () => {
        if (root.busy || root.conn === "") return;
        root.busy = true;
        const next = root.toggled ? "no" : "yes";
        root.toggled = !root.toggled;   // optimistic: the tile flips at once, the poll corrects it
        applyProc.command = ["bash", "-c", 'nmcli connection modify "$1" connection.metered "$2" && nmcli device reapply "$3"', "_", root.conn, next, root.dev];
        applyProc.running = true;
    }

    Process {
        id: applyProc
        stderr: StdioCollector { id: applyErr }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode !== 0)
                Quickshell.execDetached(["notify-send", Translation.tr("Metered"), applyErr.text.trim() || Translation.tr("nmcli failed (exit code %1)").arg(exitCode), "-a", "Shell"]);
            stateProc.running = true;
        }
    }

    // metered|dev|connection|what the guard paused|remote desktop running
    Process {
        id: stateProc
        command: ["bash", "-c", 'd=$(ip route show default | awk \'{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}\'); [ -n "$d" ] || exit 0; m=$(nmcli -g GENERAL.METERED dev show "$d"); c=$(nmcli -g GENERAL.CONNECTION dev show "$d"); p=$(sed -n 2p "${XDG_RUNTIME_DIR:-/tmp}/metered-guard.state" 2>/dev/null); pgrep -x remoter-viewer >/dev/null && r=1 || r=0; echo "$m|$d|$c|$p|$r"']
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("|");
                if (root.busy || f.length < 5) return;
                root.toggled = f[0].startsWith("yes");
                root.dev = f[1];
                root.conn = f[2];
                root.paused = f[3].replace("syncthing", "Syncthing").replace("vm", "VM").replace(" ", " + ");
                root.remoteDesktop = f[4] === "1";
                root.available = root.conn !== "";
            }
        }
    }
    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy) stateProc.running = true
    }
}
