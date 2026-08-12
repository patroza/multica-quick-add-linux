import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Multica Quick Add — Quickshell layer-shell panel (Tim-style).
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
    readonly property color chip: "#22222e"

    property var bootstrap: ({
            ok: false,
            workspaces: [],
            projects: [],
            agents: [],
            squads: [],
            selection: ({}),
            draft: ""
        })
    property var workspaceModel: []
    property var projectModel: ["No project"]
    property var createdByModel: []
    property string statusText: ""
    property bool statusIsError: true
    // Separate busy flags so bootstrap cannot unlock an in-flight send
    property bool bootstrapBusy: false
    property bool submitBusy: false
    property bool busy: bootstrapBusy || submitBusy
    property int bootGen: 0
    property int submitGen: 0
    property string submitText: ""
    property bool applyingSelection: false
    property bool readyOnce: false
    property bool revealPending: false
    property string lastDraft: ""
    property string pendingWorkspaceId: ""

    function homeBin(name) {
        const home = Quickshell.env("HOME") || "";
        return home + "/.local/bin/" + name;
    }

    function draftPath() {
        const home = Quickshell.env("HOME") || "";
        const state = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state");
        return state + "/multica-quick-add/draft.txt";
    }

    function focusPrompt() {
        Qt.callLater(() => {
            if (promptField)
                promptField.forceActiveFocus();
        });
    }

    function modelKey(list) {
        return (list || []).join("\u0001");
    }

    function anyComboPopupOpen() {
        return workspaceBox.popup.visible || projectBox.popup.visible || createdByBox.popup.visible;
    }

    function handleEscape() {
        if (anyComboPopupOpen()) {
            workspaceBox.popup.close();
            projectBox.popup.close();
            createdByBox.popup.close();
            focusPrompt();
            return;
        }
        hidePanel();
    }

    function revealPanel() {
        if (!panel.visible)
            panel.visible = true;
        root.revealPending = false;
        focusPrompt();
    }

    function showPanel() {
        if (panel.visible) {
            focusPrompt();
            return;
        }
        if (root.readyOnce && root.bootstrap.ok) {
            if (promptField)
                promptField.text = root.lastDraft;
            if (!root.submitBusy)
                statusText = "";
            revealPanel();
            reloadBootstrap(true, "");
            return;
        }
        root.revealPending = true;
        reloadBootstrap(false, "");
    }

    function hidePanel() {
        // Save draft; do NOT clear submitBusy — an in-flight send must finish cleanly
        const text = promptField ? promptField.text : "";
        if (!root.submitBusy) {
            root.lastDraft = text;
            saveDraft(text);
            if (promptField)
                promptField.text = "";
            statusText = "";
            statusIsError = true;
        } else {
            // Keep draft of what was being sent; UI can reopen with lastDraft
            root.lastDraft = root.submitText || text;
            saveDraft(root.lastDraft);
            if (promptField)
                promptField.text = "";
        }
        panel.visible = false;
        root.revealPending = false;
        root.bootstrapBusy = false;
    }

    function saveDraft(text) {
        draftSaveProc.pendingText = text || "";
        draftSaveProc.running = false;
        Qt.callLater(() => {
            draftSaveProc.stdinEnabled = true;
            draftSaveProc.running = true;
        });
    }

    function clearDraft() {
        draftClearProc.running = false;
        Qt.callLater(() => {
            draftClearProc.running = true;
        });
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

    // quiet=true: background refresh; workspaceId optional catalog target
    function reloadBootstrap(quiet, workspaceId) {
        const isQuiet = quiet === true;
        const ws = workspaceId || "";
        if (!isQuiet && !root.readyOnce)
            setStatus("Loading…", false);
        if (!isQuiet)
            root.bootstrapBusy = true;
        bootGen += 1;
        const gen = bootGen;
        bootstrapProc.quiet = isQuiet;
        bootstrapProc.running = false;
        Qt.callLater(() => {
            if (gen !== root.bootGen)
                return;
            let cmd = ["/usr/bin/env", "-u", "BASH_ENV", homeBin("mqa-bootstrap")];
            if (ws)
                cmd = cmd.concat(["--workspace-id", ws]);
            bootstrapProc.command = cmd;
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

        root.applyingSelection = true;

        const nextWs = workspaces.map(w => w.name || w.id);
        const nextProj = ["No project"].concat(projects.map(p => p.title || p.id));
        const nextCb = agents.map(a => "Agent · " + (a.name || a.id)).concat(squads.map(s => "Squad · " + (s.name || s.id)));

        if (modelKey(root.workspaceModel) !== modelKey(nextWs))
            root.workspaceModel = nextWs;
        if (modelKey(root.projectModel) !== modelKey(nextProj))
            root.projectModel = nextProj;
        if (modelKey(root.createdByModel) !== modelKey(nextCb))
            root.createdByModel = nextCb;

        let wi = 0;
        for (let i = 0; i < workspaces.length; i++) {
            if (workspaces[i].id === sel.workspace_id) {
                wi = i;
                break;
            }
        }
        wi = Math.min(wi, Math.max(0, root.workspaceModel.length - 1));

        let pi = 0;
        if (sel.project_id) {
            for (let j = 0; j < projects.length; j++) {
                if (projects[j].id === sel.project_id) {
                    pi = j + 1;
                    break;
                }
            }
        }
        pi = Math.min(pi, Math.max(0, root.projectModel.length - 1));

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
        ci = Math.min(ci, Math.max(0, root.createdByModel.length - 1));

        Qt.callLater(() => {
            workspaceBox.currentIndex = wi;
            projectBox.currentIndex = pi;
            createdByBox.currentIndex = ci;
            root.applyingSelection = false;
        });
    }

    function persistSelection() {
        if (root.applyingSelection || !root.bootstrap.ok || root.submitBusy)
            return;
        const ws = selectedWorkspaceId();
        if (!ws)
            return;
        const proj = selectedProjectId();
        const cb = selectedCreatedBy();
        const bin = root.homeBin("multica-quick-add");
        let cmd = ["/usr/bin/env", "-u", "BASH_ENV", bin, "--no-notify", "--set-workspace-id", ws, "--set-project-id", proj || ""];
        if (cb.kind === "squad" && cb.id)
            cmd = cmd.concat(["--set-squad-id", cb.id]);
        else if (cb.kind === "agent" && cb.id)
            cmd = cmd.concat(["--set-agent-id", cb.id]);
        persistProc.command = cmd;
        persistProc.running = false;
        Qt.callLater(() => {
            persistProc.running = true;
        });
    }

    function onWorkspaceActivated() {
        if (root.applyingSelection || root.submitBusy)
            return;
        const ws = selectedWorkspaceId();
        if (!ws)
            return;
        // Never persist stale project/agent under a newly selected workspace.
        // Reload catalog for this workspace first; selection restore uses saved per-ws state.
        root.pendingWorkspaceId = ws;
        setStatus("Loading workspace…", false);
        root.bootstrapBusy = true;
        // Clear dependent models immediately so we cannot submit wrong IDs
        root.applyingSelection = true;
        root.projectModel = ["No project"];
        root.createdByModel = [];
        projectBox.currentIndex = 0;
        createdByBox.currentIndex = 0;
        Qt.callLater(() => {
            root.applyingSelection = false;
        });
        // Persist workspace only (empty project/agent until catalog lands)
        const bin = root.homeBin("multica-quick-add");
        persistProc.command = ["/usr/bin/env", "-u", "BASH_ENV", bin, "--no-notify", "--set-workspace-id", ws, "--set-project-id", ""];
        persistProc.running = false;
        Qt.callLater(() => {
            persistProc.running = true;
        });
        reloadBootstrap(false, ws);
    }

    function submit() {
        if (root.submitBusy || root.bootstrapBusy)
            return;
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
        root.submitBusy = true;
        root.submitGen += 1;
        const gen = root.submitGen;
        root.submitText = prompt;
        setStatus("Sending…", false);
        const proj = selectedProjectId();
        const bin = root.homeBin("multica-quick-add");
        // "--" so prompts starting with "-" are never parsed as flags
        let cmd = ["/usr/bin/env", "-u", "BASH_ENV", bin, "--no-notify", "--workspace-id", ws, "--project-id", proj || ""];
        if (cb.kind === "squad")
            cmd = cmd.concat(["--squad-id", cb.id]);
        else
            cmd = cmd.concat(["--agent-id", cb.id]);
        cmd = cmd.concat(["--", prompt]);
        submitProc.generation = gen;
        submitProc.command = cmd;
        submitProc.running = false;
        Qt.callLater(() => {
            if (submitProc.generation === gen)
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
        onActivated: root.focusPrompt()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.handleEscape();
                event.accepted = true;
            }
        }

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

        function ping(): string {
            return "ok";
        }

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
        property bool quiet: false
        running: false
        command: ["true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.bootstrapBusy = false;
                const raw = text.trim();
                if (!raw) {
                    if (!bootstrapProc.quiet)
                        root.setStatus("Bootstrap returned empty output", true);
                    if (root.revealPending)
                        root.revealPanel();
                    return;
                }
                try {
                    const data = JSON.parse(raw);
                    root.bootstrap = data;
                    if (!data.ok) {
                        root.setStatus(data.message || data.error || "Not logged in", true);
                        if (!bootstrapProc.quiet) {
                            root.workspaceModel = [];
                            root.projectModel = ["No project"];
                            root.createdByModel = [];
                        }
                    } else {
                        if (!root.submitBusy)
                            root.setStatus("", false);
                        root.applySelectionToCombos();
                        // Do not clobber in-memory draft while a send is in flight
                        if (!root.submitBusy && typeof data.draft === "string") {
                            if (!root.lastDraft)
                                root.lastDraft = data.draft;
                        }
                        if (promptField && !root.submitBusy && (!promptField.text || promptField.text.length === 0)) {
                            if (root.lastDraft && root.lastDraft.length > 0)
                                promptField.text = root.lastDraft;
                        }
                        if (!(data.workspaces || []).length)
                            root.setStatus("No workspaces — check multica auth", true);
                        else if (!(data.agents || []).length && !(data.squads || []).length)
                            root.setStatus("No agents/squads in workspace", true);
                        root.readyOnce = true;
                        root.pendingWorkspaceId = "";
                    }
                    if (root.revealPending)
                        root.revealPanel();
                    else if (panel.visible)
                        root.focusPrompt();
                } catch (e) {
                    if (!bootstrapProc.quiet)
                        root.setStatus("Failed to parse Multica data", true);
                    if (root.revealPending)
                        root.revealPanel();
                }
            }
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
        onExited: code => {
            root.bootstrapBusy = false;
            if (code !== 0 && !root.statusText && !bootstrapProc.quiet && !root.submitBusy)
                root.setStatus("Bootstrap failed (is multica logged in?)", true);
            if (root.revealPending && code !== 0)
                root.revealPanel();
        }
    }

    Component.onCompleted: reloadBootstrap(true, "")

    Process {
        id: persistProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
    }

    Process {
        id: submitProc
        property int generation: 0
        running: false
        command: ["true"]
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (submitProc.generation !== root.submitGen)
                    return;
                if (text && text.trim())
                    root.setStatus(text.trim().replace(/^error:\s*/i, ""), true);
            }
        }
        onExited: code => {
            if (submitProc.generation !== root.submitGen)
                return;
            root.submitBusy = false;
            if (code === 0) {
                const sent = root.submitText;
                notifyProc.command = ["notify-send", "--app-name=Multica Quick Add", "Sent", sent.substring(0, 120)];
                notifyProc.running = false;
                Qt.callLater(() => {
                    notifyProc.running = true;
                });
                // Only clear UI text if it still matches what we sent (or panel is hidden)
                if (promptField && (promptField.text.trim() === sent || !panel.visible))
                    promptField.text = "";
                root.lastDraft = "";
                root.clearDraft();
                root.setStatus("", false);
                panel.visible = false;
                root.revealPending = false;
                root.submitText = "";
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

    Process {
        id: draftSaveProc
        property string pendingText: ""
        running: false
        command: ["bash", "-c", "umask 077; mkdir -m 700 -p \"$(dirname \"$1\")\" && cat > \"$1.tmp\" && if [ ! -s \"$1.tmp\" ]; then rm -f \"$1.tmp\" \"$1\"; else chmod 600 \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"; fi", "bash", root.draftPath()]
        stdinEnabled: true
        onStarted: {
            draftSaveProc.write(draftSaveProc.pendingText);
            draftSaveProc.stdinEnabled = false;
        }
    }

    Process {
        id: draftClearProc
        running: false
        command: ["rm", "-f", root.draftPath()]
    }

    // Layer-shell overlay: floats above windows on niri/Hyprland; OnDemand keyboard focus.
    // Full-width transparent strip with centered card + click-outside dismiss.
    PanelWindow {
        id: panel
        visible: false
        color: "transparent"
        implicitHeight: 360
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "multica-quick-add"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        anchors {
            top: true
            left: true
            right: true
        }

        margins {
            top: 0
        }

        // Click outside the card → dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.hidePanel()
        }

        Item {
            id: card
            width: 720
            height: 268
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 96

            // Stop click-through so typing/combos work
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
                onPressed: {}
            }

            // Soft outer glow
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
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.handleEscape();
                        event.accepted = true;
                    }
                }

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
                                text: root.submitBusy ? "Sending…" : (root.bootstrapBusy ? "Loading…" : "⌘/Ctrl+Enter to send · Esc to dismiss · Enter for newline")
                                color: root.textDim
                                font.pixelSize: 11
                                font.family: "Inter, system-ui, sans-serif"
                            }
                        }
                    }

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
                                enabled: !root.submitBusy

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        root.handleEscape();
                                        event.accepted = true;
                                        return;
                                    }
                                    const submitMod = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.SuperModifier);
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && submitMod) {
                                        root.submit();
                                        event.accepted = true;
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        DarkCombo {
                            id: workspaceBox
                            model: root.workspaceModel
                            enabled: !root.busy && root.workspaceModel.length > 0
                            Layout.preferredWidth: 1
                            Layout.fillWidth: true
                            onActivated: {
                                root.onWorkspaceActivated();
                                root.focusPrompt();
                            }
                        }

                        DarkCombo {
                            id: projectBox
                            model: root.projectModel
                            Layout.preferredWidth: 1
                            Layout.fillWidth: true
                            onActivated: {
                                root.persistSelection();
                                root.focusPrompt();
                            }
                        }

                        DarkCombo {
                            id: createdByBox
                            model: root.createdByModel
                            enabled: !root.busy && root.createdByModel.length > 0
                            Layout.preferredWidth: 1.2
                            Layout.fillWidth: true
                            onActivated: {
                                root.persistSelection();
                                root.focusPrompt();
                            }
                        }

                        Button {
                            id: sendBtn
                            text: root.submitBusy ? "…" : "Send"
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
}
