import QtQuick 2.0

import QtQuick.Layouts 1.1
import QtCharts 2.1
import QtGraphicalEffects 1.0

import Neuronify 1.0

import ".."
import "../edges"
import "../hud"
import "../paths"
import "../tools"
import "../style"

/*!
\qmltype Voltmeter
\inqmlmodule Neuronify
\ingroup neuronify-meters
\brief Reads the voltage of the neurons and shows a trace plot

Neurons can connect to the voltmeter. When they do, the voltmeter shows their voltage trace
as a function of time. Each neuron gets spesific color in the voltmeter plot. To each voltmeter
there is an associated \l{VoltmeterControls} item.
*/

Node {
    id: voltmeterRoot
    objectName: "voltmeter"
    filename: "meters/Voltmeter.qml"
    square: true
    name: "Voltmeter"

    property var connectionPlots: []
    property var colors: ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3",
        "#ff7f00", "#a65628", "#f781bf", "#999999"]

    property int currentSeries: 0

    property real timeFactor: 1000
    property real voltageFactor: 1000

    property real timeRange: 100.0e-3

    property real timeSinceLastUpdate: 0
    property real lastUpdateTime: 0

    property alias minimumValue:  dummyAxisY.min
    property alias maximumValue:  dummyAxisY.max

    property real minimumTime: (time - timeRange) * timeFactor
    property real maximumTime: time * timeFactor

    property double fontSize : 14

    property real maximumPointCount: {
        if(Qt.platform.os === "android" || Qt.platform.os === "ios") {
            return 120.0
        } else {
            return 240.0
        }
    }

    property real time: 0.0
    property real realTime: 0.0
    property int numberOfEdges: 0

    // Height of the drawn spike marker, in volts. DISPLAY ONLY: this neuron
    // model is integrate-and-fire (Cm dV/dt = I_leak + I_syn + I_inj with a
    // threshold-and-reset rule), so it does not model voltage-gated Na+/K+
    // conductances and has no action-potential waveform. Spike amplitude is
    // therefore not a measurable quantity here — only spike times, rates and
    // the sub-threshold trajectory are. +40 mV is used because it sits in the
    // physiological range and stays inside a sensibly scaled y-axis.
    property real spikeDisplayPeak: 40.0e-3

    // ── User-definable axes / gradations ───────────────────────────────
    // timeRange (above) is the width of the x-axis window, in seconds.
    // The grid divisions determine how many gradation lines/labels are drawn.
    property bool showGrid: true
    property int gridDivisionsX: 4
    property int gridDivisionsY: 4

    // ── Data recording for CSV export ──────────────────────────────────
    // The plotted LineSeries only retains the visible window (ChartScroller
    // discards older points), so recording keeps its own buffer of samples.
    // Rows are [timeMs, v1, v2, ...] with one column per connected neuron.
    property bool recording: false
    property bool recordingFull: false
    property int recordedCount: 0
    property int maximumSamples: 200000
    property var recordBuffer: []

    // The counter is only updated every 100 samples while running (updating it
    // per-sample would repaint the panel thousands of times a second), so make
    // it exact whenever recording starts or stops.
    onRecordingChanged: recordedCount = recordBuffer.length

    function clearRecording() {
        recordBuffer = []
        recordedCount = 0
        recordingFull = false
    }

    // Column name for a connected neuron: its label if set, else Neuron_N.
    function seriesName(index) {
        var cp = connectionPlots[index]
        var n = cp ? cp.connection.itemB : null
        var raw = (n && n.label && n.label.length > 0) ? n.label : ("Neuron_" + (index + 1))
        return String(raw).replace(/[",\n\r]/g, " ").trim()
    }

    // Builds a plain CSV: header row + one row per sample.
    // Wide format (one column per neuron) so traces can be compared directly
    // in Excel / R / pandas without reshaping.
    // Columns are [time_ms, <name>_mV, <name>_spike, ...] — one voltage and one
    // spike column per neuron. spike is 1 on the sample where the neuron fired,
    // 0 otherwise, so spike counts / ISIs / firing rates can be computed directly.
    function csvText() {
        var header = ["time_ms"]
        for(var c = 0; c < connectionPlots.length; c++) {
            header.push(seriesName(c) + "_mV")
            header.push(seriesName(c) + "_spike")
        }
        var lines = [header.join(",")]
        for(var r = 0; r < recordBuffer.length; r++) {
            var row = recordBuffer[r]
            var cells = []
            for(var k = 0; k < row.length; k++) {
                var v = row[k]
                if(v === null || v === undefined || isNaN(v)) {
                    cells.push("")
                } else if(k === 0) {
                    cells.push(v.toFixed(3))          // time_ms
                } else if((k - 1) % 2 === 1) {
                    cells.push(String(v))             // spike flag: 0 / 1
                } else {
                    cells.push(v.toFixed(4))          // voltage_mV
                }
            }
            lines.push(cells.join(","))
        }
        return lines.join("\n") + "\n"
    }

    function exportCsv(fileUrl) {
        return FileIO.writeSynchronously(fileUrl, csvText())
    }

    controls: Component {
        MeterControls {
            meter: voltmeterRoot
            engine: voltmeterEngine
            sliderMinimum: -250
            sliderMaximum: 250
            unit: "mV"
            meterType: "Voltmeter"
            dataToolsEnabled: true   // axis scaling + CSV recording/export
        }
    }
    width: 320
    height: 240
    color: Style.meter.background

    snapToCenter: false
    preferredEdge: MeterEdge {}

    canReceiveConnections: false

    engine: NodeEngine {
        id: voltmeterEngine
        onStepped: {
            if((realTime - lastUpdateTime) > timeRange / maximumPointCount) {
                time = realTime
                lastUpdateTime = realTime
                // Collect (and clear) the fire flags alongside the plotted sample,
                // so a spike is attributed to exactly one sample.
                var spikes = []
                for(var i in voltmeterRoot.connectionPlots) {
                    var connectionPlot = voltmeterRoot.connectionPlots[i]
                    var plot = connectionPlot.plot
                    var neuron = connectionPlot.connection.itemB
                    if(neuron) {
                        if(neuron.voltage) {
                            plot.addPoint(time * timeFactor, neuron.voltage * voltageFactor)
                        }
                    }
                    spikes.push(connectionPlot.spiked ? 1 : 0)
                    connectionPlot.spiked = false
                }

                // Capture the same sample into the CSV recording buffer.
                if(voltmeterRoot.recording && !voltmeterRoot.recordingFull) {
                    var row = [time * timeFactor]
                    for(var j = 0; j < voltmeterRoot.connectionPlots.length; j++) {
                        var nb = voltmeterRoot.connectionPlots[j].connection.itemB
                        row.push((nb && nb.voltage !== undefined)
                                 ? nb.voltage * voltageFactor : NaN)
                        row.push(spikes[j])
                    }
                    voltmeterRoot.recordBuffer.push(row)
                    // Throttle the UI counter: updating it every sample would
                    // repaint the properties panel thousands of times a second.
                    if(voltmeterRoot.recordBuffer.length % 100 === 0) {
                        voltmeterRoot.recordedCount = voltmeterRoot.recordBuffer.length
                    }
                    if(voltmeterRoot.recordBuffer.length >= voltmeterRoot.maximumSamples) {
                        voltmeterRoot.recordedCount = voltmeterRoot.recordBuffer.length
                        voltmeterRoot.recordingFull = true
                        voltmeterRoot.recording = false
                    }
                }
            }
            realTime += dt
        }
    }

    savedProperties: PropertyGroup {
        property alias width: voltmeterRoot.width
        property alias height: voltmeterRoot.height
        property alias maximumValue: voltmeterRoot.maximumValue
        property alias minimumValue: voltmeterRoot.minimumValue
        property alias timeRange: voltmeterRoot.timeRange
        property alias showGrid: voltmeterRoot.showGrid
        property alias gridDivisionsX: voltmeterRoot.gridDivisionsX
        property alias gridDivisionsY: voltmeterRoot.gridDivisionsY
    }


    onEdgeAdded: {
        numberOfEdges +=1
        var item = chartViewComponent.createObject(chartContainer);
        var plot = item.plot;
        var firePlot = item.firePlot;

        var neuron = edge.itemB;
        item.label = Qt.binding(function(){
            return neuron.label;
        });
        item.lineColor = Qt.binding(function(){
            return neuron.color;
//            return "#CEB6EE"
        });
        item.showAxis = true
        item.showAxisLabel = true

        for(var i in connectionPlots) { // loop over all old plots
            var connectionPlot = connectionPlots[i]
            connectionPlot.item.showAxis = false
            connectionPlot.item.showAxisLabel = false
        }

        var newList = connectionPlots

        var connectionPlot = {
            item: item,
            connection: edge,
            plot: plot,
            firePlot: firePlot,
            neuron: neuron,
            // Set on each fire event, consumed and cleared by the next sample.
            // This is what makes spikes recoverable from the CSV: in an
            // integrate-and-fire model the membrane potential resets at
            // threshold, so the voltage column alone never shows a spike.
            spiked: false,
            neuronFired: function() {
                connectionPlot.spiked = true
                // Draw a spike MARKER: a triangle from the current membrane
                // potential up to spikeDisplayPeak and back. The peak is a
                // display constant, not a modelled value — this is an
                // integrate-and-fire neuron, so it has no action-potential
                // waveform and its amplitude carries no information.
                // (Previously this drew to +1000 mV, which overshot every
                // possible y-axis and made spikes look unbounded.)
                var t = time * timeFactor
                var v = neuron.voltage * voltageFactor
                firePlot.addPoint(t - 1e-1, v)
                firePlot.addPoint(t, voltmeterRoot.spikeDisplayPeak * voltageFactor)
                firePlot.addPoint(t + 1e-1, v)
            }
        }

        neuron.fired.connect(connectionPlot.neuronFired);

        newList.push(connectionPlot);
        connectionPlots = newList

    }

    onEdgeRemoved: {
        numberOfEdges -=1
        for(var i in connectionPlots) {
            var connectionPlot = connectionPlots[i]
            var connectionOther = connectionPlot.connection
            if(connectionOther === edge) {
                connectionPlot.neuron.fired.disconnect(connectionPlot.neuronFired);
                connectionPlot.item.destroy();
                connectionPlots.splice(i, 1);
                break
            }
        }
        currentSeries -= 1
        if(connectionPlots.length > 0){
            connectionPlots[connectionPlots.length -1 ].item.showAxis = true
            connectionPlots[connectionPlots.length -1 ].item.showAxisLabel = true
        }
    }


    Rectangle {
        id: background
        anchors.fill: parent
        color: parent.color
//        border.color: Style.meter.border.color
//        border.width: Style.meter.border.width
        smooth: true
        antialiasing: true
        visible: false

    }

    ItemShadow {
        anchors.fill: background
        source: background
    }

    ValueAxis {
        id: dummyAxisY
        min: -100.0e-3 * voltageFactor
        max: 50.0e-3 * voltageFactor
        gridVisible: false
        labelsVisible: false
        lineVisible: false
        tickCount: 2
    }

    ColumnLayout{
        id: chartContainer
        anchors.fill: parent

    }

    Component{
        id: chartViewComponent

        Item{
            id: chartItem
            property Plot plot: series
            property Plot firePlot: fireSeries
            property string label: ""
            property bool showAxis: false
            property bool showAxisLabel: false
            property color lineColor: "red"

            Layout.fillWidth: true
            Layout.fillHeight: true
            width: 1
            height: 1

            // ── Axis titles ────────────────────────────────────────────
            Text{
                id: ylabel
                // Rotated text pivots about its centre, so its horizontal
                // extent is centred on x + width/2. Place that column at x≈11.
                x: 11 - width / 2
                anchors.verticalCenter: chartView.verticalCenter
                rotation: 270
                text: "V [mV]"
                visible: chartItem.showAxisLabel && chartView.plotArea.height > width
                font.pixelSize: voltmeterRoot.fontSize
            }

            Text{
                id: xlabel
                anchors{
                    horizontalCenter: chartView.horizontalCenter
                    bottom: chartView.bottom
                    bottomMargin: 1
                }

                text: chartItem.showAxisLabel ? "t [ms]" : ""
                font.pixelSize: voltmeterRoot.fontSize
            }

            // ── Gradation grid ─────────────────────────────────────────
            // Drawn as plain Rectangles positioned from chartView.plotArea
            // rather than via QtCharts gridVisible/labelsVisible, which
            // trigger the axis-label performance regression (QTBUG-59040).
            // ChartView's background is transparent, so this shows through
            // beneath the traces.
            Item {
                id: gridOverlay
                anchors.fill: parent
                visible: voltmeterRoot.showGrid

                Repeater {   // horizontal lines → voltage gradations
                    model: voltmeterRoot.gridDivisionsY + 1
                    Rectangle {
                        color: (index === 0 || index === voltmeterRoot.gridDivisionsY)
                               ? "#b0bec5" : "#dde3ea"
                        height: 1
                        x: chartView.plotArea.x
                        width: chartView.plotArea.width
                        y: chartView.plotArea.y + chartView.plotArea.height
                           * index / Math.max(1, voltmeterRoot.gridDivisionsY)
                    }
                }

                Repeater {   // vertical lines → time gradations
                    model: voltmeterRoot.gridDivisionsX + 1
                    Rectangle {
                        color: (index === 0 || index === voltmeterRoot.gridDivisionsX)
                               ? "#b0bec5" : "#dde3ea"
                        width: 1
                        y: chartView.plotArea.y
                        height: chartView.plotArea.height
                        x: chartView.plotArea.x + chartView.plotArea.width
                           * index / Math.max(1, voltmeterRoot.gridDivisionsX)
                    }
                }
            }

            // ── Gradation labels (only on the axis-bearing subplot) ────
            Repeater {   // voltage values, top → bottom
                model: chartItem.showAxis ? voltmeterRoot.gridDivisionsY + 1 : 0
                Text {
                    property real frac: index / Math.max(1, voltmeterRoot.gridDivisionsY)
                    text: (voltmeterRoot.maximumValue
                           - (voltmeterRoot.maximumValue - voltmeterRoot.minimumValue) * frac).toFixed(0)
                    font.pixelSize: voltmeterRoot.fontSize - 2
                    color: "#37474f"
                    horizontalAlignment: Text.AlignRight
                    x: 20
                    width: Math.max(0, chartView.plotArea.x - 26)
                    y: chartView.plotArea.y + chartView.plotArea.height * frac - height / 2
                }
            }

            Repeater {   // time values, left → right
                model: chartItem.showAxis ? voltmeterRoot.gridDivisionsX + 1 : 0
                Text {
                    property real frac: index / Math.max(1, voltmeterRoot.gridDivisionsX)
                    text: (voltmeterRoot.minimumTime
                           + (voltmeterRoot.maximumTime - voltmeterRoot.minimumTime) * frac).toFixed(0)
                    font.pixelSize: voltmeterRoot.fontSize - 2
                    color: "#37474f"
                    x: chartView.plotArea.x + chartView.plotArea.width * frac - width / 2
                    y: chartView.plotArea.y + chartView.plotArea.height + 3
                }
            }

            Text{
                id: titleText
                anchors{
                    top: chartView.top
                    topMargin: 2
                    horizontalCenter: chartView.horizontalCenter

                }

                text: label
                font.pixelSize: voltmeterRoot.fontSize

            }

            ChartView {
                id: chartView
                anchors.fill: parent
                legend.visible: false
                smooth: true
                antialiasing: true
                backgroundColor: "transparent"
                enabled: false // disables mouse input
                // Reserve a gutter for the gradation labels. The left gutter is
                // kept on every subplot so stacked traces stay aligned; only the
                // axis-bearing subplot needs the taller bottom strip.
                margins.top: 16
                margins.bottom: chartItem.showAxis ? 30 : 6
                margins.left: 58
                margins.right: 12

                Plot {
                    id: series
                    axisX: axisX
                    axisY: axisY
                    timeRange: voltmeterRoot.timeRange * timeFactor
                    color: chartItem.lineColor
                    width: 3.0
                }

                Plot {
                    id: fireSeries
                    axisX: axisX
                    axisY: axisY
                    timeRange: series.timeRange
                    color: chartItem.lineColor
                    width: 3.0
                }

                ValueAxis {
                    id: axisX
                    min: voltmeterRoot.minimumTime
                    max: voltmeterRoot.maximumTime
                    tickCount: 2 // IMPORTANT: Needs to be low because something gets
                    // recalculated everytime min/max changes and tickCount depends on this
                    gridVisible: false
                    labelsVisible: false
                    lineVisible: showAxis
                    visible: false // IMPORTANT: Due to a bug in Qt Charts/Qt Graphics View,
                    // performance is degraded with time when text changes
                    // https://bugreports.qt.io/browse/QTBUG-59040
                }

                ValueAxis {
                    id: axisY
                    min: voltmeterRoot.minimumValue
                    max: voltmeterRoot.maximumValue
                    tickCount: 2
                    gridVisible: false
                    labelsVisible: false
                    lineVisible: showAxis
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        color: Style.text.color
        visible: voltmeterRoot.connectionPlots.length < 1
        text: "Connect to neuron to see voltage"
    }

    ResizeRectangle {}

    Connector {
        color: Style.meter.border.color
//        visible: parent.selected || numberOfEdges < 1
    }
}
