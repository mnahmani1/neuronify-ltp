import QtQuick 2.0
import Neuronify 1.0

import ".."
import "../style"

Edge {
    objectName: "MeterEdge"
    filename: "edges/MeterEdge.qml"

    // Color assigned to the inner visual element
    Rectangle {
        anchors.fill: parent
        color: "#AAAAAA"
        visible: true
        radius: 2
    }
}
