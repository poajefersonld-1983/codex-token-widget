import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var snapshot: ({errors: [], loading: true})
    property bool busy: false
    property double now: Date.now() / 1000
    property string commandError: ""
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge, PlasmaCore.Types.RightEdge].indexOf(Plasmoid.location) !== -1
    readonly property bool stale: !snapshot.limits_checked_at || now - snapshot.limits_checked_at > 90
    readonly property string warning: !snapshot.configured && !snapshot.loading ? (commandError || (snapshot.errors || []).join("\n") || "Credenciais não configuradas.") : commandError || (snapshot.errors || []).join("\n")
        || (!snapshot.loading && stale ? "Dados desatualizados. Aguardando nova consulta." : "")
    readonly property string shortText: percent(snapshot.short_remaining)
    readonly property string weeklyText: percent(snapshot.weekly_remaining)
    readonly property string shortLabel: snapshot.short_label || "5h"

    Plasmoid.icon: "view-statistics"
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: "Monitor de tokens · Codex / ChatGPT"
    toolTipSubText: snapshot.loading ? "Conectando à conta…"
        : shortLabel + ": " + shortText + " disponível\nSemanal: " + weeklyText + " disponível\n"
          + (warning || "Clique para ver tokens e datas de renovação")
    toolTipTextFormat: Text.PlainText

    function percent(value) {
        return value === null || value === undefined ? "—" : Math.round(value) + "%";
    }

    function quote(value) {
        return "'" + value.replace(/'/g, "'\\''") + "'";
    }

    readonly property string backendPath: decodeURIComponent(Qt.resolvedUrl("../code/backend.py").toString().replace(/^file:\/\//, ""))
    readonly property string backendCommand: "/usr/bin/python3 -B " + quote(backendPath) + " --read"

    function configure() {
        executable.connectSource("/usr/bin/python3 -B " + quote(backendPath) + " --configure");
    }

    function refresh(force) {
        if (busy) return;
        busy = true;
        executable.connectSource(backendCommand + (force ? " --refresh" : ""));
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
            if (sourceName.endsWith(" --configure")) return;
            root.busy = false;
            try {
                if (data["exit code"] !== 0) throw new Error("backend");
                const result = JSON.parse(data.stdout);
                if (!result || typeof result !== "object" || Array.isArray(result)) throw new Error("format");
                root.snapshot = result;
                root.commandError = "";
            } catch (error) {
                root.commandError = "Não foi possível ler o monitor. Verifique Python 3 e Codex CLI.";
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now() / 1000;
            root.refresh();
        }
    }

    compactRepresentation: Item {
        id: compact
        Layout.minimumWidth: root.vertical ? 0 : 110
        Layout.preferredWidth: root.vertical ? 48 : 110
        Layout.minimumHeight: root.vertical ? 48 : 0
        Layout.preferredHeight: root.vertical ? 56 : 0
        Accessible.role: Accessible.Button
        Accessible.name: root.toolTipMainText
        Accessible.description: root.toolTipSubText

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: !root.vertical
                source: root.warning ? "dialog-warning" : "view-statistics"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
            }
            ColumnLayout {
                spacing: 0
                PC.Label {
                    text: root.shortLabel + " " + root.shortText
                    font: Kirigami.Theme.smallFont
                    color: root.stale || root.warning ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }
                PC.Label {
                    text: "7d " + root.weeklyText
                    font: Kirigami.Theme.smallFont
                    color: root.stale || root.warning ? Kirigami.Theme.neutralTextColor
                        : root.snapshot.weekly_remaining !== undefined && root.snapshot.weekly_remaining !== null && root.snapshot.weekly_remaining <= 20
                        ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 350
        Layout.preferredWidth: 390
        Layout.minimumHeight: 410
        Layout.preferredHeight: 470

        PC.ScrollView {
            id: details
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            contentWidth: availableWidth

            ColumnLayout {
                width: details.availableWidth
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Heading {
                    text: "Codex Token Monitor"
                    level: 2
                    Layout.fillWidth: true
                }
                PC.Label {
                    text: "Codex / ChatGPT · Plano " + (root.snapshot.plan || "—")
                    opacity: 0.7
                    Layout.fillWidth: true
                }
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing
                    PC.Label { text: "Tokens acumulados"; Layout.fillWidth: true }
                    PC.Label { text: root.snapshot.lifetime_tokens || "—"; font.bold: true }
                    PC.Label { text: "Último dia informado"; Layout.fillWidth: true }
                    PC.Label { text: root.snapshot.daily_tokens || "—"; font.bold: true }
                    PC.Label { text: root.snapshot.daily_date || "—"; opacity: 0.65; Layout.columnSpan: 2 }
                }
                PC.Label { text: "Limites disponíveis"; font.bold: true }
                Repeater {
                    model: root.snapshot.quotas || []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC.Label {
                            text: modelData.title + " · " + root.percent(modelData.remaining) + " disponível"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                        PC.ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: modelData.remaining === null ? 0 : modelData.remaining
                        }
                        PC.Label {
                            text: "Renova em " + modelData.resets
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                PC.Label {
                    text: "Créditos adicionais: " + (root.snapshot.credits || "não informado")
                    Layout.fillWidth: true
                }
                PC.Label {
                    text: "Os percentuais indicam o uso disponível no plano. Datas no horário local."
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                PC.Label {
                    text: root.snapshot.loading ? "Conectando à conta…" : root.snapshot.limits_checked_at
                        ? "Limites consultados às " + new Date(root.snapshot.limits_checked_at * 1000).toLocaleTimeString(Qt.locale(), "HH:mm:ss") + " · a cada 30 s"
                        : "Aguardando dados da conta · a cada 30 s"
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                PC.Label {
                    visible: root.warning.length > 0
                    text: root.warning
                    color: Kirigami.Theme.neutralTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    PC.Button {
                        text: "Configurar"
                        icon.name: "configure"
                        onClicked: root.configure()
                    }
                    PC.Button {
                        text: "Atualizar"
                        icon.name: "view-refresh"
                        enabled: !root.busy && !!root.snapshot.configured
                        onClicked: root.refresh(true)
                    }
                    PC.Button {
                        text: "Painel da conta"
                        icon.name: "internet-services"
                        onClicked: Qt.openUrlExternally("https://chatgpt.com/codex/settings/usage")
                    }
                }
            }
        }
    }
}
