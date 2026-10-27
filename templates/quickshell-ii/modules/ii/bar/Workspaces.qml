pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

ButtonMouseArea {
    id: root

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    WorkspaceModel {
        id: wsModel
        monitor: root.monitor
    }

    property bool vertical: Config.options.bar.vertical
    property bool superPressAndHeld: false // Relevant modifications at bottom of file

    property real workspaceButtonWidth: 26
    property real activeWorkspaceMargin: 2
    property real activeWorkspaceSize: workspaceButtonWidth - activeWorkspaceMargin * 2
    property real workspaceIconSize: workspaceButtonWidth * 0.69
    property real workspaceIconSizeShrinked: workspaceButtonWidth * 0.55
    property real workspaceIconOpacityShrinked: 1
    property real workspaceIconMarginShrinked: -4
    property int workspaceIndexInGroup: (monitor?.activeWorkspace?.id - 1) % wsModel.shownCount
    property real specialTextSize: workspaceButtonWidth * 0.5

    // One icon per app: a workspace grows by one icon step per distinct app on it, so every app on it shows (not only the biggest
    // window). Positions come from the running offsets below instead of index * workspaceButtonWidth.
    readonly property bool multiIcons: Config.options?.bar.workspaces.showAppIcons ?? false
    property real workspaceIconStep: NumberUtils.roundToEven(workspaceIconSize) + 3
    // Distinct icons per shown workspace, left to right as the windows are laid out
    property var workspaceApps: {
        const windows = HyprlandData.windowList;
        return Array.from({ length: wsModel.shownCount }, (_, i) => {
            const wsId = wsModel.getWorkspaceIdAt(i);
            const icons = [];
            windows.filter(w => w.workspace.id === wsId)
                .sort((a, b) => (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]))
                .forEach(w => {
                    const icon = AppSearch.guessIcon(w.class);
                    if (!icons.includes(icon)) icons.push(icon);
                });
            return icons;
        });
    }
    property var workspaceLengths: workspaceApps.map(icons => workspaceButtonWidth + (multiIcons ? Math.max(0, icons.length - 1) * workspaceIconStep : 0))
    property var workspaceOffsets: workspaceLengths.reduce((acc, len) => acc.concat(acc[acc.length - 1] + len), [0])
    function lengthAt(index: int): real {
        return workspaceLengths[Math.max(0, Math.min(index, workspaceLengths.length - 1))] ?? workspaceButtonWidth;
    }
    // Start of the (fractional, for animations) index; positionAt(i + 1) is the end of workspace i
    function positionAt(index: real): real {
        const n = workspaceLengths.length;
        if (index <= 0) return 0;
        if (index >= n) return workspaceOffsets[n] ?? 0;
        const i = Math.floor(index);
        return workspaceOffsets[i] + (index - i) * workspaceLengths[i];
    }

    Layout.alignment: vertical ? Qt.AlignHCenter : Qt.AlignVCenter
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical
    readonly property real barThickness: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    implicitWidth: vertical ? barThickness : occupiedIndicators.implicitWidth
    implicitHeight: vertical ? occupiedIndicators.implicitHeight : barThickness

    property real specialBlur: (wsModel.specialWorkspaceActive && !containsMouse) ? 1 : 0
    Behavior on specialBlur {
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }

    // Interactions
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.BackButton
    hoverEnabled: true
    property int hoverIndex: {
        const position = root.vertical ? mouseY : mouseX;
        for (let i = 0; i < root.workspaceLengths.length; i++)
            if (position < root.workspaceOffsets[i + 1]) return i;
        return root.workspaceLengths.length - 1;
    }

    function switchWorkspaceToHovered() {
        Hyprland.dispatch(`hl.dsp.focus({workspace = ${wsModel.getWorkspaceIdAt(hoverIndex)}})`);
    }

    function toggleSpecial() {
        Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
    }

    onPressed: mouse => {
        if (mouse.button == Qt.LeftButton)
            switchWorkspaceToHovered();
        else if (mouse.button == Qt.RightButton)
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        else if (mouse.button == Qt.BackButton) 
            toggleSpecial()
    }
    onWheel: event => {
        if (event.angleDelta.y < 0)
            Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
        else if (event.angleDelta.y > 0)
            Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
    }

    // Indications
    Item {
        id: regularWorkspaces
        anchors.fill: parent

        scale: 1 - 0.08 * root.specialBlur
        layer.smooth: true
        layer.enabled: root.specialBlur > 0
        layer.effect: MultiEffect {
            brightness: -0.1 * root.specialBlur
            blurEnabled: true
            blur: root.specialBlur
            blurMax: 32
        }

        /////////////////// Occupied indicators ///////////////////
        StyledRectangle {
            id: occupiedIndicatorsBg
            anchors.fill: parent
            contentLayer: StyledRectangle.ContentLayer.Group
            color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
            visible: false
        }

        WorkspaceLayout {
            id: occupiedIndicators
            anchors.centerIn: parent

            layer.enabled: true
            visible: false

            Repeater {
                model: wsModel.shownCount
                delegate: Item {
                    id: wsBg
                    required property int index
                    readonly property int wsId: wsModel.getWorkspaceIdAt(index)
                    property bool currentOccupied: wsModel.occupied[index] && wsId != wsModel.fakeWorkspace
                    property bool previousOccupied: index > 0 && wsModel.occupied[index - 1] && (wsId - 1) != wsModel.fakeWorkspace
                    property bool nextOccupied: index < wsModel.shownCount - 1 && wsModel.occupied[index + 1] && (wsId + 1) != wsModel.fakeWorkspace
                    readonly property real length: root.lengthAt(index)
                    implicitWidth: root.vertical ? root.workspaceButtonWidth : length
                    implicitHeight: root.vertical ? length : root.workspaceButtonWidth

                    // The idea: over-stretch to occupied sides, animate this for a smooth transition.
                    //           masking already prevents weird overlaps
                    Pill {
                        property real undirectionalWidth: root.workspaceButtonWidth * wsBg.currentOccupied
                        property real undirectionalLength: (wsBg.length + root.workspaceButtonWidth * (0.5 * wsBg.previousOccupied + 0.5 * wsBg.nextOccupied)) * currentOccupied
                        property real undirectionalOffset: !wsBg.currentOccupied ? 0.5 * wsBg.length : -0.5 * wsBg.previousOccupied * root.workspaceButtonWidth
                        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                        x: root.vertical ? 0 : undirectionalOffset
                        y: root.vertical ? undirectionalOffset : 0
                        implicitWidth: root.vertical ? undirectionalWidth : undirectionalLength
                        implicitHeight: root.vertical ? undirectionalLength : undirectionalWidth

                        Behavior on undirectionalWidth {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                        Behavior on undirectionalLength {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                        Behavior on undirectionalOffset {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        MaskMultiEffect {
            id: occupiedIndicatorsMultiEffect
            z: 1
            anchors.centerIn: parent
            implicitWidth: occupiedIndicators.implicitWidth
            implicitHeight: occupiedIndicators.implicitHeight
            source: occupiedIndicatorsBg
            maskSource: occupiedIndicators
        }

        /////////////////// Active indicator ///////////////////
        TrailingIndicator {
            id: activeIndicator
            anchors.fill: parent
            z: 2

            index: root.workspaceIndexInGroup
        }

        /////////////////// Hover ///////////////////
        TrailingIndicator {
            id: interactionIndicator
            z: 3
            index: root.containsMouse ? root.hoverIndex : root.workspaceIndexInGroup
            color: "transparent"
            StateOverlay {
                id: hoverOverlay
                anchors.fill: interactionIndicator.indicatorRectangle
                radius: root.activeWorkspaceSize / 2
                hover: root.containsMouse
                press: root.containsPress
                drag: true // There are too many layers so we need to force this to be a lil more opaque
                contentColor: Appearance.colors.colPrimary
            }
        }

        /////////////////// Numbers ///////////////////
        WorkspaceLayout {
            id: numbersGrid
            z: 4
            layer.enabled: true // For the masking

            Repeater {
                model: wsModel.shownCount
                delegate: NumberWorkspaceItem {}
            }
        }
        Colorizer {
            z: 5
            anchors.fill: numbersGrid
            colorizationColor: Appearance.colors.colOnPrimary
            sourceColor: Appearance.colors.colOnSecondaryContainer

            source: activeIndicator
            maskEnabled: true
            maskSource: numbersGrid

            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        /////////////////// App icons ///////////////////
        WorkspaceLayout {
            id: appsGrid
            z: 6

            Repeater {
                model: wsModel.shownCount
                delegate: WorkspaceItem {
                    id: wsApp
                    readonly property var icons: root.workspaceApps[index] ?? []

                    // One icon per distinct app, in a row (a column on a vertical bar). They fade out for the numbers while SUPER is held.
                    Grid {
                        anchors.centerIn: parent
                        columns: root.vertical ? 1 : Math.max(1, wsApp.icons.length)
                        spacing: root.workspaceIconStep - NumberUtils.roundToEven(root.workspaceIconSize)
                        opacity: (root.multiIcons && !root.superPressAndHeld) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        Repeater {
                            model: wsApp.icons
                            delegate: Item {
                                id: iconSlot
                                required property var modelData
                                implicitWidth: NumberUtils.roundToEven(root.workspaceIconSize)
                                implicitHeight: implicitWidth

                                AppIcon {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    visible: false // Prevent dupe: the colorizer already copies the icon
                                    source: Quickshell.iconPath(iconSlot.modelData, "image-missing")
                                    implicitSize: iconSlot.implicitWidth
                                }

                                Circle {
                                    id: iconMask
                                    visible: false
                                    layer.enabled: true
                                    diameter: appIcon.implicitSize
                                }

                                Loader { // Somehow putting this multieffect in a loader prevents it from not showing up
                                    anchors.fill: appIcon
                                    sourceComponent: Colorizer {
                                        implicitWidth: appIcon.implicitWidth
                                        implicitHeight: appIcon.implicitHeight
                                        colorizationColor: Appearance.m3colors.darkmode ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                                        colorization: Config.options.bar.workspaces.monochromeIcons ? 0.8 : 0.5
                                        brightness: 0
                                        source: appIcon

                                        maskEnabled: true
                                        maskSource: iconMask
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FadeLoader {
        anchors.centerIn: parent
        shown: wsModel.specialWorkspaceActive
        scale: 0.8 + 0.2 * root.specialBlur

        opacity: root.specialBlur
        Behavior on opacity {} // Don't animate, as specialBlur is already animated

        sourceComponent: Pill {
            anchors.centerIn: parent
            property real undirectionalWidth: root.activeWorkspaceSize
            property real undirectionalLength: {
                const base = root.workspaceButtonWidth * Math.min(1.35, wsModel.shownCount); // Who tf only configures only 2 workspaces shown anyway?
                if (root.vertical)
                    return base;
                return specialWsText.implicitWidth + undirectionalWidth;
            }
            color: Appearance.colors.colPrimary

            implicitWidth: root.vertical ? undirectionalWidth : undirectionalLength
            implicitHeight: root.vertical ? undirectionalLength : undirectionalWidth

            StyledText {
                id: specialWsText
                anchors.centerIn: parent
                text: (!root.vertical ? wsModel.specialWorkspaceName : "S")
                color: Appearance.colors.colOnPrimary
                font.pixelSize: root.specialTextSize
            }

            Behavior on undirectionalLength {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
        }
    }

    /////////////////// Super key press handling ///////////////////
    Timer {
        id: superPressAndHeldTimer
        interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
        repeat: false
        onTriggered: {
            root.superPressAndHeld = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                return;
            if (GlobalStates.superDown)
                superPressAndHeldTimer.restart();
            else {
                superPressAndHeldTimer.stop();
                root.superPressAndHeld = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() {
            superPressAndHeldTimer.stop();
        }
    }

    component WorkspaceLayout: Box {
        anchors {
            top: !root.vertical ? parent.top : undefined
            bottom: !root.vertical ? parent.bottom : undefined
            left: root.vertical ? parent.left : undefined
            right: root.vertical ? parent.right : undefined
        }

        rowSpacing: 0
        columnSpacing: 0
        vertical: root.vertical
    }

    component WorkspaceItem: Item {
        required property int index
        readonly property int wsId: wsModel.getWorkspaceIdAt(index)
        implicitWidth: root.vertical ? root.barThickness : root.lengthAt(index)
        implicitHeight: root.vertical ? root.lengthAt(index) : root.barThickness
    }

    component NumberWorkspaceItem: WorkspaceItem {
        id: wsNum
        property bool hasBiggestWindow: !!wsModel.biggestWindow[index]
        property int wsId: wsModel.getWorkspaceIdAt(index)
        property color contentColor: (wsModel.occupied[wsNum.index] && wsId !== wsModel.fakeWorkspace) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1Inactive
        property bool showingNumbers: {
            if (root.superPressAndHeld)
                return true;
            if (GlobalStates.screenLocked)
                return false;
            if (Config.options?.bar.workspaces.alwaysShowNumbers && (!Config.options?.bar.workspaces.showAppIcons || !wsNum.hasBiggestWindow))
                return true;
            return false;
        }

        FadeLoader {
            // The dot sits under the icons; with several it would show between them
            shown: !wsNum.showingNumbers && !(root.multiIcons && !root.superPressAndHeld && root.workspaceApps[wsNum.index]?.length > 0)
            anchors.centerIn: parent
            Circle {
                anchors.centerIn: parent
                diameter: root.workspaceButtonWidth * 0.18
                color: wsNum.contentColor
            }
        }
        FadeLoader {
            shown: wsNum.showingNumbers
            anchors.centerIn: parent
            StyledText {
                anchors.centerIn: parent
                font {
                    pixelSize: Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2)
                    family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : defaultFont
                }
                color: wsNum.contentColor
                text: Config.options?.bar.workspaces.numberMap[wsNum.wsId - 1] || wsNum.wsId
            }
        }
    }

    component TrailingIndicator: Item {
        id: trailingIndicator
        anchors.fill: parent
        required property int index
        property alias indicatorRectangle: indicatorRect
        property alias color: indicatorRect.color

        property var indexPair: AnimatedTabIndexPair {
            id: idxPair
            index: trailingIndicator.index
        }

        StyledRectangle {
            id: indicatorRect

            anchors {
                verticalCenter: root.vertical ? undefined : parent.verticalCenter
                horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            }

            property real indicatorPosition: root.positionAt(Math.min(idxPair.idx1, idxPair.idx2)) + root.activeWorkspaceMargin
            property real indicatorLength: root.positionAt(Math.max(idxPair.idx1, idxPair.idx2) + 1) - root.positionAt(Math.min(idxPair.idx1, idxPair.idx2)) - 2 * root.activeWorkspaceMargin
            property real indicatorThickness: root.activeWorkspaceSize

            contentLayer: StyledRectangle.ContentLayer.Group
            radius: indicatorThickness / 2
            color: Appearance.colors.colPrimary

            x: root.vertical ? null : indicatorPosition
            y: root.vertical ? indicatorPosition : null
            implicitWidth: root.vertical ? indicatorThickness : indicatorLength
            implicitHeight: root.vertical ? indicatorLength : indicatorThickness
        }
    }
}
