import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasma5support as Plasma5Support

ColumnLayout {
    Label {
        text: "Configure sua própria conta pelo login oficial do ChatGPT.\nA senha é digitada somente no navegador."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    Button {
        text: "Configurar conta / Remover credenciais"
        onClicked: {
            const path = decodeURIComponent(Qt.resolvedUrl("../code/backend.py").toString().replace(/^file:\/\//, ""));
            const quoted = "'" + path.replace(/'/g, "'\\''") + "'";
            runner.connectSource("/usr/bin/python3 -B " + quoted + " --configure");
        }
    }
    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName); }
    }
    Item { Layout.fillHeight: true }
}
