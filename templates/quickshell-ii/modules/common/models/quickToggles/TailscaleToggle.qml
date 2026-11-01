import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

// Tailscale: `tailscale up` / `tailscale down`, state from `tailscale status --json`. Driving up/down as a normal user needs
// `sudo tailscale set --operator=$USER` once; without it the tile shows tailscale's error in a notification.
QuickToggleModel {
    id: root
    name: Translation.tr("Tailscale")
    icon: "hub"
    toggled: false
    statusText: busy ? busyText : (toggled ? (ip ? Translation.tr("Connected · %1").arg(ip) : Translation.tr("Connected")) : Translation.tr("Off"))
    tooltipText: toggled ? Translation.tr("Tailscale: %1 of %2 peers online%3").arg(online).arg(peers).arg(exitNode ? Translation.tr(" · exit node %1").arg(exitNode) : "") : Translation.tr("Tailscale is off")

    property bool busy: false
    property bool wantUp: false
    property double settleUntil: 0 // tailscale status lags a moment behind up/down; don't let a stale read flip the tile back
    property string busyText: ""
    property string ip: ""
    property int peers: 0
    property int online: 0
    property string exitNode: ""

    mainAction: () => {
        if (root.busy) return;
        root.busy = true;
        const up = !root.toggled;
        root.wantUp = up;
        root.busyText = up ? Translation.tr("Connecting…") : Translation.tr("Disconnecting…");
        actionProc.command = ["tailscale", up ? "up" : "down"];
        actionProc.running = true;
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErr }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode === 0) {
                root.toggled = root.wantUp;
                root.settleUntil = Date.now() + 4000;
                return;
            }
            Quickshell.execDetached(["notify-send", Translation.tr("Tailscale"), actionErr.text.trim() || Translation.tr("tailscale failed (exit code %1)").arg(exitCode), "-a", "Shell"]);
            stateProc.running = true;
        }
    }

    Process {
        id: stateProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.busy || Date.now() < root.settleUntil) return;
                try {
                    const s = JSON.parse(text);
                    root.toggled = s.BackendState === "Running";
                    root.ip = (s.TailscaleIPs ?? [])[0] ?? "";
                    const peers = Object.values(s.Peer ?? {});
                    root.peers = peers.length;
                    root.online = peers.filter(p => p.Online).length;
                    root.exitNode = peers.find(p => p.ExitNode)?.HostName ?? "";
                } catch (e) {
                    root.toggled = false;
                }
            }
        }
    }
    Process {
        running: true
        command: ["which", "tailscale"]
        onExited: (exitCode, exitStatus) => root.available = exitCode === 0
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy && Date.now() >= root.settleUntil) stateProc.running = true
    }
}
