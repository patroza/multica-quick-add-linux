import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Multica Quick Add — Quickshell floating panel (Tim-style, dark glass).
// Daemon: qs -c multica-quick-add -n -d
// Toggle: qs -c multica-quick-add ipc call panel toggle

ShellRoot {
    id: root

    readonly property color bg: "#12121a"
    readonly property color bgElevated: "#1a1a24"
    readonly property color border: "#2e2e3a"
    readonly property color borderFocus: "#585b70"
    readonly property color text: "#e4e4ef"
    readonly property color textDim: "#6c6c80"
    readonly property color accent: "#89b4fa"
    readonly property color danger: "#f38ba8"
    readonly property color success: "#a6e3a1"
    readonly property color chip: "#22222e"

    property var bootstrap: ({
            ok: false,
            workspaces: [],
            projects: [],
            agents: [],
            squads: [],
            selection: ({})
        })
    property var workspaceModel: []
    property var projectModel: ["No project"]
    property var createdByModel: []
    property string statusText: ""
    property bool statusIsError: true
    property bool busy: false
    property int bootGen: 0

    function homeBin(name) {
        const home = Quickshell.env("HOME") || "";
        return home + "/.local/bin/" + name;
    }

    function showPanel() {
        // Order matters: never throw before reloadBootstrap.
        panel.visible = true;
        reloadBootstrap();
        Qt.callLater(() => {
            if (promptField)
                promptField.forceActiveFocus();
        });
    }

    function hidePanel() {
        panel.visible = false;
        promptField.text = "";
        statusText = "";
        statusIsError = true;
        busy = false;
    }

    function togglePanel() {
        if (panel.visible)
            hidePanel();
        else
            showPanel();
    }

    function setStatus(msg, isError) {
        statusText = msg || "";
        statusIsError = isError !== false;
    }

    function reloadBootstrap() {
        busy = true;
        setStatus("Loading…", false);
        bootGen += 1;
        const gen = bootGen;
        // Restart process reliably (same-frame false→true is flaky).
        bootstrapProc.running = false;
        Qt.callLater(() => {
            if (gen !== root.bootGen)
                return;
            bootstrapProc.command = ["/usr/bin/env", "-u", "BASH_ENV", homeBin("mqa-bootstrap")];
            bootstrapProc.running = true;
        });
    }

    function selectedWorkspaceId() {
        const list = root.bootstrap.workspaces || [];
        const i = workspaceBox.currentIndex;
        if (i < 0 || i >= list.length)
            return "";
        return list[i].id || "";
    }

    function selectedProjectId() {
        const list = root.bootstrap.projects || [];
        const i = projectBox.currentIndex;
        if (i <= 0)
            return "";
        return list[i - 1].id || "";
    }

    function selectedCreatedBy() {
        const agents = root.bootstrap.agents || [];
        const squads = root.bootstrap.squads || [];
        const i = createdByBox.currentIndex;
        if (i < 0)
            return ({
                    kind: "",
                    id: ""
                });
        if (i < agents.length)
            return ({
                    kind: "agent",
                    id: agents[i].id,
                    name: agents[i].name
                });
        const si = i - agents.length;
        if (si >= 0 && si < squads.length)
            return ({
                    kind: "squad",
                    id: squads[si].id,
                    name: squads[si].name
                });
        return ({
                kind: "",
                id: ""
            });
    }

    function applySelectionToCombos() {
        const sel = root.bootstrap.selection || {};
        const workspaces = root.bootstrap.workspaces || [];
        const projects = root.bootstrap.projects || [];
        const agents = root.bootstrap.agents || [];
        const squads = root.bootstrap.squads || [];

        // Reassign via empty first so ComboBox refreshes reliably.
        root.workspaceModel = [];
        root.projectModel = ["No project"];
        root.createdByModel = [];

        root.workspaceModel = workspaces.map(w => w.name || w.id);
        root.projectModel = ["No project"].concat(projects.map(p => p.title || p.id));
        root.createdByModel = agents.map(a => "Agent · " + (a.name || a.id)).concat(squads.map(s => "Squad · " + (s.name || s.id)));

        let wi = 0;
        for (let i = 0; i < workspaces.length; i++) {
            if (workspaces[i].id === sel.workspace_id) {
                wi = i;
                break;
            }
        }
        workspaceBox.currentIndex = wi;

        let pi = 0;
        if (sel.project_id) {
            for (let j = 0; j < projects.length; j++) {
                if (projects[j].id === sel.project_id) {
                    pi = j + 1;
                    break;
                }
            }
        }
        projectBox.currentIndex = pi;

        let ci = 0;
        if (sel.created_by_kind === "agent" && sel.created_by_id) {
            for (let a = 0; a < agents.length; a++) {
                if (agents[a].id === sel.created_by_id) {
                    ci = a;
                    break;
                }
            }
        } else if (sel.created_by_kind === "squad" && sel.created_by_id) {
            for (let s = 0; s < squads.length; s++) {
                if (squads[s].id === sel.created_by_id) {
                    ci = agents.length + s;
                    break;
                }
            }
        }
        createdByBox.currentIndex = Math.min(ci, Math.max(0, root.createdByModel.length - 1));
    }

    function submit() {
        const prompt = promptField.text.trim();
        if (!prompt) {
            setStatus("Type an issue first", true);
            return;
        }
        const ws = selectedWorkspaceId();
        const cb = selectedCreatedBy();
        if (!ws) {
            setStatus(root.bootstrap.ok ? "Pick a workspace" : "Not logged in — run multica login", true);
            return;
        }
        if (!cb.id) {
            setStatus("Pick an agent or squad", true);
            return;
        }
        busy = true;
        setStatus("Sending…", false);
        const proj = selectedProjectId();
        const bin = root.homeBin("multica-quick-add");
        let cmd = ["/usr/bin/env", "-u", "BASH_ENV", bin, "--no-notify", "--workspace-id", ws, "--project-id", proj || ""];
        if (cb.kind === "squad")
            cmd = cmd.concat(["--squad-id", cb.id]);
        else
            cmd = cmd.concat(["--agent-id", cb.id]);
        cmd.push(prompt);
        submitProc.command = cmd;
        submitProc.running = false;
        Qt.callLater(() => {
            submitProc.running = true;
        });
    }

    component DarkCombo: ComboBox {
        id: combo
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        enabled: !root.busy
        font.pixelSize: 13
        font.family: "Inter, system-ui, sans-serif"

        background: Rectangle {
            implicitHeight: 36
            radius: 10
            color: combo.down || combo.hovered ? Qt.lighter(root.chip, 1.08) : root.chip
            border.width: combo.activeFocus ? 1 : 0
            border.color: root.borderFocus
        }

        contentItem: Text {
            leftPadding: 12
            rightPadding: combo.indicator.width + 10
            text: combo.displayText
            font: combo.font
            color: combo.enabled ? root.text : root.textDim
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        indicator: Text {
            x: combo.width - width - 12
            y: (combo.height - height) / 2
            text: "▾"
            color: root.textDim
            font.pixelSize: 11
        }

        popup: Popup {
            y: combo.height + 4
            width: combo.width
            implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
            padding: 4

            background: Rectangle {
                radius: 12
                color: root.bgElevated
                border.color: root.border
                border.width: 1
            }

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator {}
            }
        }

        delegate: ItemDelegate {
            width: combo.width - 8
            height: 34
            highlighted: combo.highlightedIndex === index

            contentItem: Text {
                text: modelData
                color: root.text
                font.pixelSize: 13
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
            }

            background: Rectangle {
                radius: 8
                color: parent.highlighted ? "#2a2a3a" : "transparent"
            }
        }
    }

    IpcHandler {
        target: "panel"

        function toggle(): string {
            root.togglePanel();
            return panel.visible ? "open" : "closed";
        }

        function open(): string {
            root.showPanel();
            return "open";
        }

        function close(): string {
            root.hidePanel();
            return "closed";
        }
    }

    Process {
        id: bootstrapProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.busy = false;
                const raw = text.trim();
                if (!raw) {
                    root.setStatus("Bootstrap returned empty output", true);
                    return;
                }
                try {
                    const data = JSON.parse(raw);
                    root.bootstrap = data;
                    if (!data.ok) {
                        root.setStatus(data.message || data.error || "Not logged in", true);
                        root.workspaceModel = [];
                        root.projectModel = ["No project"];
                        root.createdByModel = [];
                    } else {
                        root.setStatus("", false);
                        root.applySelectionToCombos();
                        if (!(data.workspaces || []).length)
                            root.setStatus("No workspaces — check multica auth", true);
                        else if (!(data.agents || []).length && !(data.squads || []).length)
                            root.setStatus("No agents/squads in workspace", true);
                    }
                } catch (e) {
                    root.setStatus("Failed to parse Multica data", true);
                }
            }
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
        onExited: code => {
            root.busy = false;
            if (code !== 0 && !root.statusText)
                root.setStatus("Bootstrap failed (is multica logged in?)", true);
        }
    }

    Process {
        id: submitProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text && text.trim())
                    root.setStatus(text.trim().replace(/^error:\s*/i, ""), true);
            }
        }
        onExited: code => {
            root.busy = false;
            if (code === 0) {
                const msg = promptField.text.trim();
                notifyProc.command = ["notify-send", "--app-name=Multica Quick Add", "Sent", msg.substring(0, 120)];
                notifyProc.running = false;
                Qt.callLater(() => {
                    notifyProc.running = true;
                });
                promptField.text = "";
                root.setStatus("", false);
                root.hidePanel();
            } else if (!root.statusText) {
                root.setStatus("Send failed", true);
            }
        }
    }

    Process {
        id: notifyProc
        running: false
        command: ["true"]
    }

    FloatingWindow {
        id: panel
        title: "Multica Quick Add"
        visible: false
        implicitWidth: 720
        implicitHeight: 268
        minimumSize: Qt.size(560, 220)
        color: "transparent"

        onClosed: root.hidePanel()

        // Soft outer glow / shadow stack
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 20
            color: "#40000000"
            y: 3
            z: -1
        }

        Rectangle {
            id: chrome
            anchors.fill: parent
            radius: 18
            color: root.bg
            border.color: root.border
            border.width: 1

            // subtle top highlight
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                radius: 18
                color: "#22ffffff"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 8
                        color: "#1e3a5f"
                        border.color: "#2a4a70"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "M"
                            color: root.accent
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Quick Add"
                            color: root.text
                            font.pixelSize: 14
                            font.bold: true
                            font.family: "Inter, system-ui, sans-serif"
                        }

                        Text {
                            text: root.busy ? "Working…" : "⌘/Ctrl+Enter to send · Esc to dismiss · Enter for newline"
                            color: root.textDim
                            font.pixelSize: 11
                            font.family: "Inter, system-ui, sans-serif"
                        }
                    }
                }

                // Prompt card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 88
                    radius: 14
                    color: root.bgElevated
                    border.color: promptField.activeFocus ? root.borderFocus : root.border
                    border.width: 1

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        TextArea {
                            id: promptField
                            placeholderText: "Describe an issue…"
                            wrapMode: TextEdit.Wrap
                            color: root.text
                            placeholderTextColor: root.textDim
                            font.pixelSize: 17
                            font.family: "Inter, system-ui, sans-serif"
                            background: null
                            selectByMouse: true
                            padding: 10
                            topPadding: 10
                            leftPadding: 12
                            rightPadding: 12
                            bottomPadding: 10

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.hidePanel();
                                    event.accepted = true;
                                    return;
                                }
                                // Enter = newline. Submit only with Ctrl/Cmd/Super+Enter
                                // (Toshy: Cmd often surfaces as Meta/Super or Ctrl depending on remap).
                                const submitMod = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.SuperModifier);
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && submitMod) {
                                    root.submit();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // Pickers + send
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    DarkCombo {
                        id: workspaceBox
                        model: root.workspaceModel
                        enabled: !root.busy && root.workspaceModel.length > 0
                        Layout.preferredWidth: 1
                        Layout.fillWidth: true
                    }

                    DarkCombo {
                        id: projectBox
                        model: root.projectModel
                        Layout.preferredWidth: 1
                        Layout.fillWidth: true
                    }

                    DarkCombo {
                        id: createdByBox
                        model: root.createdByModel
                        enabled: !root.busy && root.createdByModel.length > 0
                        Layout.preferredWidth: 1.2
                        Layout.fillWidth: true
                    }

                    Button {
                        id: sendBtn
                        text: root.busy ? "…" : "Send"
                        enabled: !root.busy
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 36
                        onClicked: root.submit()

                        contentItem: Text {
                            text: sendBtn.text
                            font.pixelSize: 13
                            font.bold: true
                            font.family: "Inter, system-ui, sans-serif"
                            color: sendBtn.enabled ? "#0b1020" : root.textDim
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 10
                            color: !sendBtn.enabled ? root.chip : (sendBtn.down ? "#6a9ad8" : (sendBtn.hovered ? "#9ac0fb" : root.accent))
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    color: root.statusIsError ? root.danger : root.textDim
                    font.pixelSize: 12
                    font.family: "Inter, system-ui, sans-serif"
                    visible: root.statusText.length > 0
                    elide: Text.ElideRight
                }
            }
        }
    }
}
