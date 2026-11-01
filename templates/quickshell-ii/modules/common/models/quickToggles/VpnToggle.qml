import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Sunrise VPN: the NetworkManager OpenVPN connection "SunriseVPN" (nmcli connection up/down). The tile follows the real connection state,
// so a connect started elsewhere (nm-applet, nmcli, autoconnect) shows up within a few seconds.
QuickToggleModel {
    id: root
    name: Translation.tr("Sunrise VPN")
    icon: toggled ? "vpn_lock" : "vpn_key_off"
    toggled: false
    statusText: busy ? busyText : (toggled ? Translation.tr("Connected") : Translation.tr("Off"))
    tooltipText: Translation.tr("Sunrise VPN (NetworkManager connection %1)").arg(connName)

    readonly property string connName: "SunriseVPN"
    property bool busy: false
    property string busyText: ""

    mainAction: () => {
        if (root.busy) return;
        root.busy = true;
        const up = !root.toggled;
        root.busyText = up ? Translation.tr("Connecting…") : Translation.tr("Disconnecting…");
        // -w 30: give up after 30 s instead of nmcli's 90 s default; a VPN that needs a login prompt fails fast
        actionProc.command = ["nmcli", "-w", "30", "connection", up ? "up" : "down", "id", root.connName];
        actionProc.running = true;
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErr }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode !== 0)
                Quickshell.execDetached(["notify-send", Translation.tr("Sunrise VPN"), actionErr.text.trim() || Translation.tr("nmcli failed (exit code %1)").arg(exitCode), "-a", "Shell"]);
            stateProc.running = true;
        }
    }

    Process {
        id: stateProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.busy) return;
                root.toggled = text.split("\n").some(l => l.startsWith(root.connName + ":"));
            }
        }
    }
    // Is the connection defined at all? Hide the tile on machines without it.
    Process {
        running: true
        command: ["nmcli", "-t", "-f", "NAME", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.available = text.split("\n").includes(root.connName)
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
