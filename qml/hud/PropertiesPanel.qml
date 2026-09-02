import QtQuick 2.6
import QtQuick.Controls 2.1
import QtQuick.Controls 2.1
import QtQuick.Controls.Material 2.1
import QtQuick.Dialogs 1.2
import Qt.labs.platform 1.0 as Platform

import "../controls"
import "../hud"
import "../style"

Item {
    id: root

    signal resetDynamics
    signal resetProperties
    signal saveToOpened

    readonly property real offset: background.anchors.rightMargin + background.width

    property var workspace
    // The Neuronify root, so the Simulation page can drive session recording.
    property var simulator: null
    property Item activeObject: null
    property bool advanced
    property bool snappingEnabled

    width: loader.width
    height: loader.height

    Material.theme: Material.Light

    Rectangle {
        id: background
        anchors.fill: parent
        color: Material.background

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: false
            onClicked: {
                mouse.accepted = true
            }
            onPressed: {
                mouse.accepted = true
            }
            onReleased: {
                mouse.accepted = true
            }
            onWheel: {
                wheel.accepted = true
            }
        }
    }

    Loader {
        id: loader
        clip: true
        sourceComponent: activeObject && activeObject.controls ? activeObject.controls : simulationComponent
    }

    Component {
        id: simulationComponent
        // A bare PropertiesPage, like the other control panels. It was
        // previously wrapped in a PropertiesContainer, which is an Item with no
        // width/height whose children anchor to parent — so it collapsed to
        // 0x0 and this page never actually rendered.
        PropertiesPage {
                id: simulatonPage
                title: "Simulation"
                Button {
                    text: "Reset all dynamics"
                    onClicked: {
                        root.resetDynamics();
                    }
                }
                Button {
                    text: "Reset all properties"
                    onClicked: {
                        resetDialog.open();
                    }
                    MessageDialog {
                        id: resetDialog
                        text: "This will reset all properties for all items. Are you sure?"
                        standardButtons: StandardButton.Ok | StandardButton.Cancel
                        onAccepted: {
                            root.resetProperties();
                        }
                    }
                }
                CheckBox {
                    id: snapCheckBox
                    text: "Snap to grid"
                    checked: root.snappingEnabled
                    Binding {
                        target: root
                        property: "snappingEnabled"
                        value: snapCheckBox.checked
                    }
                    Binding {
                        target: snapCheckBox
                        property: "checked"
                        value: root.snappingEnabled
                    }
                }
                // ── Session recording ──────────────────────────────────
                // Records every voltmeter-monitored neuron (voltage + spikes)
                // and every synapse weight into a single time-aligned CSV.
                Text {
                    text: "Session recording"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#0d47a1"
                }

                Text {
                    width: parent ? parent.width : 0
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: (root.simulator && root.simulator.recordingFull)
                           ? "#c62828" : "#555555"
                    text: {
                        var s = root.simulator
                        if(!s) return ""
                        if(s.recordingFull)
                            return "Buffer full — " + s.recordedCount
                                   + " samples. Export or clear to continue."
                        if(s.recording)
                            return "Recording… " + s.recordedCount + " samples across "
                                   + s.recordColumns.length + " channels."
                        if(s.recordedCount > 0)
                            return "Stopped — " + s.recordedCount + " samples across "
                                   + s.recordColumns.length + " channels."
                        return "Captures all voltmeters and synapse weights to one CSV, plus a .metadata.json sidecar of the parameters used."
                    }
                }

                Flow {
                    width: parent ? parent.width : 0
                    spacing: 6

                    Button {
                        text: (root.simulator && root.simulator.recording)
                              ? "Stop" : "Record all"
                        enabled: root.simulator ? !root.simulator.recordingFull : false
                        onClicked: {
                            var s = root.simulator
                            if(!s) return
                            if(s.recording) s.stopRecording()
                            else s.startRecording()
                        }
                    }
                    Button {
                        text: "Clear"
                        enabled: root.simulator ? root.simulator.recordedCount > 0 : false
                        onClicked: if(root.simulator) root.simulator.clearRecording()
                    }
                    Button {
                        text: "Export CSV"
                        enabled: root.simulator ? root.simulator.recordedCount > 0 : false
                        onClicked: sessionCsvDialog.open()
                    }
                }

                Platform.FileDialog {
                    id: sessionCsvDialog
                    fileMode: Platform.FileDialog.SaveFile
                    nameFilters: ["CSV files (*.csv)"]
                    defaultSuffix: "csv"
                    onAccepted: {
                        if(root.simulator) root.simulator.exportSessionCsv(file)
                    }
                }

                Button {
                    visible: root.advanced
                    text: "Save to opened"
                    onClicked: {
                        root.saveToOpened();
                    }
                }
        }
    }

    Keys.onPressed: {
        if(event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
            if(stackView.depth > 1){
                stackView.pop();
            } else {
                revealed = false
            }
            event.accepted = true
        }
    }
}
