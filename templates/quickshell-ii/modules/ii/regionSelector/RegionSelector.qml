pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    property var targetScreen: null
    property bool openedForCurrentTrigger: false

    function fallbackScreen() {
        return Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function findScreenForPos(cx, cy) {
        if (HyprlandData.monitors && HyprlandData.monitors.length > 0) {
            const mon = HyprlandData.monitors.find(m => {
                const scale = m.scale || 1.0;
                const w = m.width / scale;
                const h = m.height / scale;
                return cx >= m.x && cx < (m.x + w) && cy >= m.y && cy < (m.y + h);
            });
            if (mon) {
                const screen = Quickshell.screens.find(s => s.name === mon.name);
                if (screen)
                    return screen;
            }
        }
        const sFound = Quickshell.screens.find(s => {
            return cx >= s.x && cx < (s.x + s.width) && cy >= s.y && cy < (s.y + s.height);
        });
        if (sFound)
            return sFound;

        return root.fallbackScreen();
    }

    function triggerOpen(screen) {
        if (root.openedForCurrentTrigger)
            return;
        root.openedForCurrentTrigger = true;
        fallbackTimer.stop();
        root.targetScreen = screen ?? root.fallbackScreen();
        GlobalStates.regionSelectorOpen = true;
    }

    function applyCursorPosAndOpen(rawText) {
        fallbackTimer.stop();
        try {
            const pos = JSON.parse(rawText.trim());
            root.triggerOpen(root.findScreenForPos(pos.x, pos.y));
        } catch (e) {
            root.triggerOpen(root.fallbackScreen());
        }
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            id: cursorPosCollector
            onStreamFinished: {
                root.applyCursorPosAndOpen(cursorPosCollector.text);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.triggerOpen(root.fallbackScreen());
            }
        }
    }

    Timer {
        id: fallbackTimer
        interval: 100
        repeat: false
        onTriggered: {
            root.triggerOpen(root.fallbackScreen());
        }
    }

    function dismiss() {
        fallbackTimer.stop();
        GlobalStates.regionSelectorOpen = false;
        root.targetScreen = null;
        root.openedForCurrentTrigger = false;
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen && (root.targetScreen !== null) && (regionSelectorLoader.modelData?.name === root.targetScreen?.name)

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    function startSelection(action, selectionMode) {
        root.action = action;
        root.selectionMode = selectionMode;
        if (GlobalStates.regionSelectorOpen) {
            GlobalStates.regionSelectorOpen = false;
        }
        root.openedForCurrentTrigger = false;
        fallbackTimer.restart();
        cursorPosProc.running = false;
        cursorPosProc.running = true;
    }

    function screenshot() {
        root.startSelection(RegionSelection.SnipAction.Copy, RegionSelection.SelectionMode.RectCorners);
    }

    function search() {
        const mode = Config.options.search.imageSearch.useCircleSelection ? RegionSelection.SelectionMode.Circle : RegionSelection.SelectionMode.RectCorners;
        root.startSelection(RegionSelection.SnipAction.Search, mode);
    }

    function ocr() {
        root.startSelection(RegionSelection.SnipAction.CharRecognition, RegionSelection.SelectionMode.RectCorners);
    }

    function record() {
        root.startSelection(RegionSelection.SnipAction.Record, RegionSelection.SelectionMode.RectCorners);
    }

    function recordWithSound() {
        root.startSelection(RegionSelection.SnipAction.RecordWithSound, RegionSelection.SelectionMode.RectCorners);
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot();
        }
        function search() {
            root.search();
        }
        function ocr() {
            root.ocr();
        }
        function record() {
            root.record();
        }
        function recordWithSound() {
            root.recordWithSound();
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
