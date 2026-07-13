import QtQuick 2.6
import QtQuick.Controls 2.1
import QtQuick.Layouts 1.3
import Neuronify 1.0

import "../controls"

Item {
    id: root

    property var edge: null

    implicitWidth: 260
    implicitHeight: column.implicitHeight + 24

    ColumnLayout {
        id: column
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 12
        }
        spacing: 8

        // ── Enable toggle ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Label { text: "LTP enabled"; Layout.fillWidth: true; font.pixelSize: 13 }
            Switch {
                id: ltpSwitch
                checked: edge ? edge.ltpEnabled : false
                onToggled: { if (edge) edge.ltpEnabled = checked }
            }
        }

        // ── Weight bar ─────────────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2

            Label {
                text: edge ? ("Synaptic weight: " + (edge.synapticWeight / edge.baselineWeight).toFixed(2) + " (norm.)") : ""
                font.pixelSize: 12
            }
            Rectangle {
                Layout.fillWidth: true
                height: 12
                radius: 6
                color: "#e0e0e0"
                Rectangle {
                    width: parent.width * (edge ? Math.min(1.0, (edge.synapticWeight - edge.baselineWeight) / (edge.maxWeight - edge.baselineWeight + 0.001)) : 0)
                    height: parent.height
                    radius: 6
                    color: "#1976d2"
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
        }

        // ── Max weight ─────────────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2
            Label { text: "Max weight: " + (edge ? edge.maxWeight.toFixed(1) : ""); font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 1.1; to: 10.0; stepSize: 0.1
                value: edge ? edge.maxWeight : 3.0
                onMoved: { if (edge) edge.maxWeight = value }
            }
        }

        // ── Learning rate ──────────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2
            Label { text: "Learning rate: " + (edge ? edge.learningRate.toFixed(3) : ""); font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 0.01; to: 0.5; stepSize: 0.01
                value: edge ? edge.learningRate : 0.1
                onMoved: { if (edge) edge.learningRate = value }
            }
        }

        // ── Detection window ───────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2
            Label { text: "Spike window (s): " + (edge ? edge.detectionWindow.toFixed(1) : ""); font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 0.1; to: 5.0; stepSize: 0.1
                value: edge ? edge.detectionWindow : 1.0
                onMoved: { if (edge) edge.detectionWindow = value }
            }
        }

        // ── Spike threshold ────────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2
            Label { text: "Spike threshold: " + (edge ? edge.spikeThreshold : ""); font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 1; to: 20; stepSize: 1
                value: edge ? edge.spikeThreshold : 3
                onMoved: { if (edge) edge.spikeThreshold = Math.round(value) }
            }
        }

        // ── Forgetting rate ────────────────────────────────
        ColumnLayout {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: {
                    if (!edge) return "Forgetting rate: "
                    var r = edge.forgettingRate
                    return "Forgetting rate: " + r.toFixed(2) + " /s"
                        + (r > 0 ? "  (τ≈" + (1 / r).toFixed(1) + "s)" : "  (off)")
                }
                font.pixelSize: 12
            }
            Slider {
                Layout.fillWidth: true
                from: 0.0; to: 1.0; stepSize: 0.01
                value: edge ? edge.forgettingRate : 0.2
                onMoved: { if (edge) edge.forgettingRate = value }
            }
        }

        // ── Reset button ───────────────────────────────────
        Button {
            visible: ltpSwitch.checked
            Layout.fillWidth: true
            text: "Reset weight"
            font.pixelSize: 12
            onClicked: {
                if (edge) edge.synapticWeight = edge.baselineWeight
            }
        }
    }
}
