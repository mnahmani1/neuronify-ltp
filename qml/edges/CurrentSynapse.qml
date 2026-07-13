import QtQuick 2.0
import QtQuick.Controls 2.1
import QtQuick.Layouts 1.3
import QtQuick.Particles 2.0
import Neuronify 1.0

import ".."
import "../controls"
import "../hud"

Edge {
    id: root
    objectName: "CurrentSynapse"
    filename: "edges/CurrentSynapse.qml"
    name: "Current based synapse"

    engine: EdgeEngine {
        id: engine

        property bool isPlaced: false
        property bool alphaFunction
        property real tau
        property real maximumCurrent
        property real delay: 0.0

        property real time
        property real linear
        property real exponential
        property var triggers: []

        savedProperties: [
            PropertyGroup {
                property alias tau: engine.tau
                property alias maximumCurrent: engine.maximumCurrent
                property alias delay: engine.delay
                property alias alphaFunction: engine.alphaFunction
                property alias linear: engine.linear
                property alias exponential: engine.exponential
                property alias triggers: engine.triggers
            }
        ]

        function trigger() {
            if(alphaFunction) {
                linear = 0.0;
                exponential = Math.exp(1.0);
            } else {
                exponential = 1.0;
            }
        }

        onResettedDynamics: {
            linear = 0.0;
            exponential = 0.0;
            triggers.length = 0;
        }

        onResettedProperties: {
            tau = 2.0e-3
            maximumCurrent = 3.0e-9
            delay = 5.0e-3
            alphaFunction = false;
        }

        onStepped: {
            var weight = root.ltpEnabled ? root.synapticWeight / root.baselineWeight : 1.0
            if(alphaFunction) {
                currentOutput = maximumCurrent * linear * exponential * weight;
                linear += dt / tau;
            } else {
                currentOutput = maximumCurrent * exponential * weight;
            }
            exponential -= exponential * dt / tau;

            if(triggers.length > 0 && triggers[0] < time) {
                trigger();
                triggers.shift();
            }
            time += dt;
        }

        onReceivedFire: {
            // Only trigger if the edge has been placed in the scene
            if (!root.isPlaced) return;

            if(delay > 0.0) {
                triggers.push(time + delay);
            } else {
                trigger();
            }
            // LTP spike tracking is handled in C++ via receiveFireEvent()
        }
    }

    property Component controls: Component {
        Item {
            implicitWidth: 260
            implicitHeight: panelColumn.implicitHeight + 24

            ColumnLayout {
                id: panelColumn
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
                spacing: 8

                // ── Synapse modulation ─────────────────────────────
                Label { text: "Synapse"; font.pixelSize: 13; font.bold: true }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label {
                        text: "Current (nA): " + (root.engine.maximumCurrent * 1e9).toFixed(2)
                        font.pixelSize: 12
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0; to: 10e-9; stepSize: 0.1e-9
                        value: root.engine.maximumCurrent
                        onMoved: root.engine.maximumCurrent = value
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label {
                        text: "Delay (ms): " + (root.engine.delay * 1000).toFixed(1)
                        font.pixelSize: 12
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0; to: 0.05; stepSize: 0.001
                        value: root.engine.delay
                        onMoved: root.engine.delay = value
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label {
                        text: "Time const. (ms): " + (root.engine.tau * 1000).toFixed(1)
                        font.pixelSize: 12
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0.001; to: 0.05; stepSize: 0.001
                        value: root.engine.tau
                        onMoved: root.engine.tau = value
                    }
                }

                // ── Divider ────────────────────────────────────────
                Rectangle { Layout.fillWidth: true; height: 1; color: "#cccccc" }

                // ── LTP ────────────────────────────────────────────
                LtpSynapseDashboard {
                    edge: root
                    Layout.fillWidth: true
                }
            }
        }
    }
}
