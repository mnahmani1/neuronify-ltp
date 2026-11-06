import QtQuick 2.7
import QtCharts 2.1
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.1
import QtQuick.Layouts 1.1

import Neuronify 1.0

Item {
    id: root

    property var chart
    property var series
    property alias text: label.text
    property alias value: slider.value

    property var next: null
    property alias field: thresholdField
    property bool ready: false

    /*!
      Emitted only when the *user* moves this control — dragging the handle,
      nudging it with the keyboard, or typing in the field.

      `value` also moves on its own: refresh() recomputes the slider's range
      from the chart's geometry, and QQuickSlider clamps its value into the new
      range. Those self-inflicted changes used to run straight back into the
      neuron through the two-way bindings in NeuronDashboard, so merely opening
      or re-laying-out the properties panel silently rewrote the neuron's reset
      potential. The visible symptom was the neuron icon turning grey — that is
      the "inhibited" overlay, switched on because the reset potential had been
      moved above the membrane voltage (with the scene paused the voltage never
      moves again, so the grey stayed). Write-backs are now driven by this
      signal instead of by value changes.
    */
    signal userChanged(real newValue)

    /*!
      Emitted when the slider's range has been recomputed and its value may
      therefore have been clamped to something the model never asked for. The
      owner responds by pushing the model's value back in.
    */
    signal syncRequested()

    function refresh() {
        dummySlider.value = 1
        var maxPoint = dummySlider.handle.mapToItem(chart, 0, dummySlider.handle.height / 2)
        var max = chart.mapToValue(maxPoint, series).y
        dummySlider.value = 0
        var minPoint = dummySlider.handle.mapToItem(chart, 0, dummySlider.handle.height / 2)
        var min = chart.mapToValue(minPoint, series).y
        if(max > min) {
            slider.to = max
            slider.from = min
            ready = true
            // Changing the range can clamp the value; ask the owner to put the
            // model's value back rather than letting the clamp stand.
            syncRequested()
        }
    }

    implicitWidth: Math.max(label.implicitWidth, fieldMetrics.width)

    onWidthChanged: refresh()
    onHeightChanged: refresh()
    Component.onCompleted: refresh()

    Connections {
        target: chart
        onWidthChanged: refresh()
        onHeightChanged: refresh()
        onXChanged: refresh()
        onYChanged: refresh()
    }

    Label {
        id: label
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
    }

    Slider {
        id: dummySlider
        visible: false
        anchors.fill: slider
        orientation: Qt.Vertical
    }

    Slider {
        id: slider
        anchors {
            top: label.bottom
            bottom: thresholdField.top
            horizontalCenter: parent.horizontalCenter
        }

        orientation: Qt.Vertical
        onValueChanged: {
            rect.update()
        }
        // moved() fires only for user input (drag or keyboard), never when the
        // value changes because the range was recomputed.
        onMoved: root.userChanged(slider.value)
        // Settle the handle when the drag ends. The owner may have clamped
        // what it accepted (a reset potential cannot go above the threshold),
        // in which case the handle has run past where the model actually is.
        onPressedChanged: if(!pressed) root.syncRequested()
        value: 0.5
        hoverEnabled: true

        Rectangle {
            id: rect

            x: -1000
            y: slider.handle.y + slider.handle.height / 2 - height / 2
            width: 2000
            height: 3
            color: {
                var col = Material.accent
                return Qt.rgba(col.r, col.g, col.b, 0.2)
            }

            opacity: slider.hovered || thresholdField.activeFocus ? 1.0 : 0.0
            z: -1

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    TextMetrics {
        id: fieldMetrics
        font: thresholdField.font
        text: "-00.00"
    }

    TextField {
        id: thresholdField
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        horizontalAlignment: Text.AlignHCenter
//        validator: DoubleValidator {
//            decimals: 1
//        }asfasgasd
        KeyNavigation.tab: next

        onEditingFinished: {
            slider.value = Number(text)
            root.userChanged(slider.value)
        }
        Binding {
            target: thresholdField
            property: "text"
            value: root.value.toFixed(1)
        }
    }
}
