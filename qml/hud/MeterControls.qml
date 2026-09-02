import QtQuick 2.0
import QtQuick.Controls 2.1
import QtQuick.Layouts 1.1
import Qt.labs.platform 1.0 as Platform

import Neuronify 1.0

import ".."
import "../controls"
import "../style"

/*!
    \qmltype MeterControls
    \inqmlmodule Neuronify
    \ingroup neuronify-hud
    \brief Contains the user controls for the meters.

    The meter control panel contains:
\list
 \li  A "connect to all"-button which connects the meter to all existing neurons.
 \li  A "disconnect from all"-button which disconnects the meter from all neurons it currently is connected to.
 \li  Sliders for setting the minimum and maximum values.
\endlist
*/

PropertiesPage {
    id: meterControlsRoot
    property NodeEngine engine
    property Item meter
    property double sliderMinimum: -250
    property double sliderMaximum: 250
    property string unit: ""
    property string meterType: ""
    // Enables the axis-scaling and CSV recording sections. Off by default so
    // other meters (e.g. RatePlot) keep their original, simpler panel.
    property bool dataToolsEnabled: false

    title: meterType

    onMeterChanged: {
        if(!meterControlsRoot.meter) {
            return
        }

    }

    BoundSlider {
        target: meter
        property: "minimumValue"
        text: "Minimum " + meterControlsRoot.meterType
        unit: meterControlsRoot.unit
        minimumValue: meterControlsRoot.sliderMinimum
        maximumValue: meterControlsRoot.sliderMaximum
    }

    BoundSlider {
        target: meter
        property: "maximumValue"
        text: "Maximum " + meterControlsRoot.meterType
        unit: meterControlsRoot.unit
        minimumValue: meterControlsRoot.sliderMinimum
        maximumValue: meterControlsRoot.sliderMaximum
    }

    // ── Axis scaling / gradations ──────────────────────────────────────
    // Every slider here also accepts a typed value, so an exact range can be
    // dialled in (e.g. 40 ms span, 5 divisions) for reproducible figures.
    Text {
        visible: meterControlsRoot.dataToolsEnabled
        text: "Axis scaling"
        font.bold: true
        font.pixelSize: 14
        color: "#0d47a1"
    }

    BoundSlider {
        visible: meterControlsRoot.dataToolsEnabled
        target: meter
        property: "timeRange"
        text: "Time span"
        unit: "ms"
        minimumValue: 10e-3
        maximumValue: 2000e-3
        unitScale: 1e-3
        stepSize: 10e-3
        precision: 0
    }

    BoundSlider {
        visible: meterControlsRoot.dataToolsEnabled
        target: meter
        property: "gridDivisionsY"
        text: "Voltage divisions"
        minimumValue: 1
        maximumValue: 10
        stepSize: 1
        precision: 0
    }

    BoundSlider {
        visible: meterControlsRoot.dataToolsEnabled
        target: meter
        property: "gridDivisionsX"
        text: "Time divisions"
        minimumValue: 1
        maximumValue: 10
        stepSize: 1
        precision: 0
    }

    SwitchControl {
        visible: meterControlsRoot.dataToolsEnabled
        target: meter
        property: "showGrid"
        checkedText: "Show gridlines"
    }

    // ── Data recording / CSV export ────────────────────────────────────
    Text {
        visible: meterControlsRoot.dataToolsEnabled
        text: "Data recording"
        font.bold: true
        font.pixelSize: 14
        color: "#0d47a1"
    }

    Text {
        visible: meterControlsRoot.dataToolsEnabled
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        color: (meter && meter.recordingFull) ? "#c62828" : "#555555"
        text: {
            if(!meter) return ""
            if(meter.recordingFull)
                return "Buffer full — " + meter.recordedCount
                       + " samples. Export or clear to continue."
            return (meter.recording ? "Recording… " : "Stopped — ")
                   + meter.recordedCount + " samples captured."
        }
    }

    Flow {
        visible: meterControlsRoot.dataToolsEnabled
        width: parent ? parent.width : 0
        spacing: 6

        Button {
            text: (meter && meter.recording) ? "Stop" : "Record"
            enabled: meter ? !meter.recordingFull : false
            onClicked: if(meter) meter.recording = !meter.recording
        }
        Button {
            text: "Clear"
            enabled: meter ? meter.recordedCount > 0 : false
            onClicked: if(meter) meter.clearRecording()
        }
        Button {
            text: "Export CSV"
            enabled: meter ? meter.recordedCount > 0 : false
            onClicked: csvDialog.open()
        }
    }

    Platform.FileDialog {
        id: csvDialog
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: ["CSV files (*.csv)"]
        defaultSuffix: "csv"
        onAccepted: {
            if(meterControlsRoot.meter) {
                meterControlsRoot.meter.exportCsv(file)
            }
        }
    }

//    ConnectMultipleControl {
//        toEnabled: false
//        node: meter
//    }

//    ResetControl {
//        engine: meterControlsRoot.engine
//    }
}

