import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// The whole bar silhouette is drawn here by a fragment shader (shaders/bar_morph.frag). At rest it is the plain rounded bar.
// While music plays (cava reads the system audio) the bar gives way a few pixels at the top and its top and bottom edges become
// smooth waves that stay inside the bar's own box. Everything winds down while the mouse is over the bar so it stays clickable.
// Installed into the end-4 shell's BarContent.qml by install_bar.sh, which also makes the bar's own rectangle transparent.
Item {
    id: root
    required property Item bar  // the bar background rectangle

    // ---- input: system audio ---------------------------------------------------------------------------------------------------------
    property real out: 0       // overall level 0..1
    property var bands: new Array(24).fill(0)
    property real phase: 0
    Process {
        running: true
        command: ["cava", "-p", Quickshell.shellPath("modules/ii/bar/cava_morph.conf")]
        stdout: SplitParser {
            onRead: line => {
                const b = line.split(";").filter(x => x.length).map(x => Math.min(1, parseFloat(x) / 100));
                if (b.length < 4 || b.some(isNaN)) return;
                root.bands = b;
                root.out = b.reduce((a, x) => a + x, 0) / b.length;
            }
        }
    }
    Timer { interval: 500; running: true; repeat: true; onTriggered: styleView.reload() }

    // ---- the wave --------------------------------------------------------------------------------------------------------------------
    // The drive is one number sampled every 40ms and sent outwards from the centre of the bar, so the edge shows its recent past.
    property var hist: new Array(8).fill(0)
    readonly property real drive: Math.min(1, out * 2.4)
    property real driveS: 0  // the drive, eased, so the wave never jumps
    property real sub: 0     // how far we are into the current 40ms sample (the wave is interpolated between samples, so it scrolls smoothly)
    property real pushedAt: Date.now()
    Timer {
        interval: 40; running: root.out > 0.012 || root.driveS > 0.01; repeat: true
        onTriggered: { root.hist = [root.driveS].concat(root.hist.slice(0, root.hist.length - 1)); root.pushedAt = Date.now(); }
    }
    HoverHandler { id: hover; parent: root.bar }
    property real calm: hover.hovered ? 0 : 1  // mouse over the bar: wind down
    Behavior on calm { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    readonly property real musicW: Math.min(1, out * 14)  // music playing: show the spectrum instead of the history
    property real music: musicW
    Behavior on music { NumberAnimation { duration: 120 } }
    function histAt(u) {
        const p = Math.max(0, Math.abs(u - 0.5) * 2 * (hist.length - 2) - sub), i = Math.floor(p), f = p - i;
        return hist[i] * (1 - f) + hist[i + 1] * f;
    }
    function bandAt(u) {
        const p = Math.abs(u - 0.5) * 2 * (bands.length - 1), i = Math.min(bands.length - 2, Math.floor(p)), f = p - i;
        return (bands[i] * (1 - f) + bands[i + 1] * f) * 2.2;
    }
    readonly property real breath: 0.02 * (0.7 + 0.3 * Math.sin(phase * 0.7))  // never fully still
    function amp(u) { return (Math.max(0.03, (1 - music) * histAt(u) + music * bandAt(u)) + breath) * calm; }

    // ---- colours ---------------------------------------------------------------------------------------------------------------------
    readonly property var palette: ["#5b8def", "#7aa2f7", "#8f86e8", "#7aa2f7"]
    function colAt(p) {  // colour at position p (0..1, wraps) of the palette
        const x = (((p % 1) + 1) % 1) * (palette.length - 1), i = Math.floor(x), f = x - i;
        const a = Qt.color(palette[i]), b = Qt.color(palette[Math.min(palette.length - 1, i + 1)]);
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1);
    }
    readonly property real drift: phase * 0.012  // the colours slowly flow along the bar

    // ---- the picture -----------------------------------------------------------------------------------------------------------------
    x: bar.x
    y: bar.y
    width: bar.width
    readonly property real extraMax: 8  // px below the bar the shape may grow into (the gap above the windows)
    height: bar.height + extraMax
    readonly property real activity: Math.min(1, driveS + musicW * 0.8)  // 0 when quiet
    property real shown: activity
    Behavior on shown { NumberAnimation { duration: 140 } }
    // 0 = the plain bar, 1 = the bar is morphing: the bar's own shadow and border must be gone whatever the wave amplitude is
    property real morphing: Math.min(1, shown * 2)
    Behavior on morphing { NumberAnimation { duration: 160 } }
    property real tintK: 0.2 * shown
    Behavior on tintK { NumberAnimation { duration: 220 } }
    readonly property color bg: Appearance.colors.colLayer0
    readonly property color border: Appearance.colors.colLayer0Border
    readonly property bool drawn: Config.options.bar.showBackground
    property real level: 0  // 0..1: how far the shape has morphed (activity, hover calm)
    readonly property real squeezeMax: 5  // px the top edge gives way at most
    readonly property real centerShift: squeezeMax * level / 2  // the shape's middle moves down by this much: the bar's sections follow it so icons and text stay centred
    // which look: the name in ~/.config/bar-morph/style (siri, liquid, bars, aurora, ripple, calm); bar_style.sh <name> changes it live
    readonly property var styleNames: ["siri", "liquid", "bars", "aurora", "ripple", "calm"]
    property int styleIndex: 4  // ripple is the default
    readonly property var reachFactor: [0.75, 1.0, 0.8, 0.4, 0.9, 0.5]  // how much of the room below each style uses
    FileView { id: styleView; path: Quickshell.env("HOME") + "/.config/bar-morph/style"; printErrors: false
        onLoaded: { const i = root.styleNames.indexOf(styleView.text().trim()); root.styleIndex = i >= 0 ? i : 4; } }
    property var bandVals: new Array(16).fill(0)
    property real lastFrame: Date.now()

    // Frame-rate independent smoothing: the same feel at 10, 30 or 60 fps.
    function ease(rate, dt) { return 1 - Math.exp(-rate * dt); }

    Timer {
        // 30fps while music plays and no frames at all when the bar is flat: every frame makes the compositor redraw (and blur) the whole bar.
        interval: 33; repeat: true
        running: root.out > 0.012 || root.shown > 0.01 || root.driveS > 0.01 || root.level > 0.02
        onTriggered: {
            const now = Date.now(), dt = Math.min(0.1, (now - root.lastFrame) / 1000);
            root.lastFrame = now;
            root.driveS += (root.drive - root.driveS) * root.ease(32, dt);
            root.sub = Math.min(1, (now - root.pushedAt) / 40);
            root.phase += dt * (0.8 + root.driveS * 1.2);
            root.level = root.shown * 0.9 * root.calm;
            const b = [];
            for (let i = 0; i < 16; i++) b.push(Math.min(1, root.amp(i / 15) * 0.9));
            root.bandVals = b;
        }
    }

    Rectangle {  // fallback if the shader could not be loaded: the plain bar, never an invisible one
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.bar.height
        visible: root.drawn && fx.status === ShaderEffect.Error  // only on a reported error: on this setup status never reads Compiled, and a fallback that stays on is a plain bar under the shader
        color: root.bg
        radius: root.bar.radius
        border.width: root.bar.border.width
        border.color: root.border
    }
    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: root.drawn
        property vector2d dims: Qt.vector2d(width, height)
        property real radius: root.bar.radius
        property real squeeze: root.squeezeMax * root.level
        property real reachB: root.extraMax * root.level * root.reachFactor[root.styleIndex]
        property real extraMax: root.extraMax
        property real time: root.phase
        property real tint: root.tintK
        property real rimMix: root.shown * 0.85
        property real borderMix: root.bar.border.width > 0 ? 1 - root.morphing : 0
        property real drift: root.drift
        property real style: root.styleIndex
        property color bg: root.bg
        property color border: root.border
        property color p0: root.colAt(0.0)
        property color p1: root.colAt(0.25)
        property color p2: root.colAt(0.5)
        property color p3: root.colAt(0.75)
        property real b0: root.bandVals[0]
        property real b1: root.bandVals[1]
        property real b2: root.bandVals[2]
        property real b3: root.bandVals[3]
        property real b4: root.bandVals[4]
        property real b5: root.bandVals[5]
        property real b6: root.bandVals[6]
        property real b7: root.bandVals[7]
        property real b8: root.bandVals[8]
        property real b9: root.bandVals[9]
        property real b10: root.bandVals[10]
        property real b11: root.bandVals[11]
        property real b12: root.bandVals[12]
        property real b13: root.bandVals[13]
        property real b14: root.bandVals[14]
        property real b15: root.bandVals[15]
        fragmentShader: "bar_morph.frag.qsb"
    }
}
