import QtQuick 2.0
import QtQuick.Particles 2.0
import Neuronify 1.0
import "paths"
import "hud"
import "edges"

EdgeBase {
    id: connectionRoot
    signal clicked(var connection)

    property Component controls: null

    // General properties
    property real playbackSpeed
    property string objectName: "edge"
    property string name: "Unnamed edge"
    property bool isEdge: true
    property string filename: "Edge.qml"
    property bool selected: false
    property bool valid: (itemA && itemB) ? true : false

    // NEW: manually placed flag
    property bool isPlaced: false

    // Base color of the edge
    property color edgeColor: valid ? itemA.color : "white"

    // LTP visualization helpers — 0.0 at baseline, 1.0 at maxWeight
    property real ltpStrength: (ltpEnabled && maxWeight > baselineWeight)
        ? Math.max(0.0, Math.min(1.0, (synapticWeight - baselineWeight) / (maxWeight - baselineWeight)))
        : 0.0
    property real baseThickness: 2.0
    property real edgeThickness: baseThickness + 4.0 * ltpStrength
    property color ltpColor: Qt.darker(edgeColor, 1.0 + 0.6 * ltpStrength)

    // Geometry
    property real diffx: valid ? itemA.connectionPoint.x - itemB.connectionPoint.x : 0
    property real diffy: valid ? itemA.connectionPoint.y - itemB.connectionPoint.y : 0
    property real length: Math.sqrt(diffx*diffx + diffy*diffy)
    property real angle: Math.atan2(diffy, diffx)*180/Math.PI
    property real cx: (valid && isPlaced) ? intersectX() : itemA.connectionPoint.x
    property real cy: (valid && isPlaced) ? intersectY() : itemA.connectionPoint.y


    readonly property alias startPoint: sCurve.startPoint
    readonly property alias endPoint: sCurve.endPoint

    savedProperties: [
        PropertyGroup {
            property alias filename: connectionRoot.filename
            property alias engine: connectionRoot.engine
        },
        // LTP configuration — persisted so a synapse keeps its learning/forgetting
        // settings across save and reload. (These are C++ Q_PROPERTYs on EdgeBase.)
        PropertyGroup {
            property alias ltpEnabled: connectionRoot.ltpEnabled
            property alias baselineWeight: connectionRoot.baselineWeight
            property alias maxWeight: connectionRoot.maxWeight
            property alias learningRate: connectionRoot.learningRate
            property alias detectionWindow: connectionRoot.detectionWindow
            property alias spikeThreshold: connectionRoot.spikeThreshold
            property alias forgettingRate: connectionRoot.forgettingRate
        }
    ]

    Component.onCompleted: {
        resetProperties()
        resetDynamics()
    }

    // Geometry helpers
    function intersectX() {
        var dx = Math.abs(diffx)
        var dy = Math.abs(diffy)
        var x = 0

        if (!itemB.square) {
            var offset = curved ? 10 * Math.cos((angle + 90) * Math.PI / 180) : 0.0
            return itemB.connectionPoint.x + (connectionSpot.width + itemB.radius) * diffx / length + offset
        }

        if (diffx <= 0 && diffy >= 0) {
            x = (dx >= dy) ? itemB.connectionPoint.x - (itemB.width/2 + connectionSpot.width)
                           : itemB.connectionPoint.x - (itemB.width/2 + connectionSpot.width)*dx/dy
        } else if (diffx >= 0 && diffy >= 0) {
            x = (dx >= dy) ? itemB.connectionPoint.x + (itemB.width/2 + connectionSpot.width)
                           : itemB.connectionPoint.x + (itemB.width/2 + connectionSpot.width)*dx/dy
        } else if (diffx >= 0 && diffy <= 0) {
            x = (dx >= dy) ? itemB.connectionPoint.x + (itemB.width/2 + connectionSpot.width)
                           : itemB.connectionPoint.x + (itemB.width/2 + connectionSpot.width)*dx/dy
        } else {
            x = (dx >= dy) ? itemB.connectionPoint.x - (itemB.width/2 + connectionSpot.width)
                           : itemB.connectionPoint.x - (itemB.width/2 + connectionSpot.width)*dx/dy
        }
        return x
    }

    function intersectY() {
        var dx = Math.abs(diffx)
        var dy = Math.abs(diffy)
        var y = 0

        if (!itemB.square) {
            var offset = curved ? 10 * Math.sin((angle + 90) * Math.PI / 180) : 0.0
            return itemB.connectionPoint.y + (connectionSpot.width + itemB.radius) * diffy / length + offset
        }

        if (diffx <= 0 && diffy >= 0) {
            y = (dx >= dy) ? itemB.connectionPoint.y + (itemB.height/2 + connectionSpot.width)*dy/dx
                           : itemB.connectionPoint.y + (itemB.height/2 + connectionSpot.width)
        } else if (diffx >= 0 && diffy >= 0) {
            y = (dx >= dy) ? itemB.connectionPoint.y + (itemB.height/2 + connectionSpot.width)*dy/dx
                           : itemB.connectionPoint.y + (itemB.height/2 + connectionSpot.width)
        } else if (diffx >= 0 && diffy <= 0) {
            y = (dx >= dy) ? itemB.connectionPoint.y - (itemB.height/2 + connectionSpot.width)*dy/dx
                           : itemB.connectionPoint.y - (itemB.height/2 + connectionSpot.width)
        } else {
            y = (dx >= dy) ? itemB.connectionPoint.y - (itemB.height/2 + connectionSpot.width)*dy/dx
                           : itemB.connectionPoint.y - (itemB.height/2 + connectionSpot.width)
        }
        return y
    }

    function setUniqueConnection(nodeA, nodeB) {
        var existing = connectionRoot.parent.findChildren(EdgeBase).filter(function(e) {
            return (e.itemA === nodeA && e.itemB === nodeB) ||
                   (e.itemA === nodeB && e.itemB === nodeA)
        })
        if(existing.length > 0) return false
        connectionRoot.itemA = nodeA
        connectionRoot.itemB = nodeB
        connectionRoot.isPlaced = true
        return true
    }

    BezierCurve {
        id: sCurve
        color: connectionRoot.selected ? "#08306b" : connectionRoot.ltpColor
        lineWidth: connectionRoot.edgeThickness
        startPoint: itemA ? Qt.point(itemA.connectionPoint.x, itemA.connectionPoint.y) : Qt.point(0,0)
        endPoint: Qt.point(cx, cy)
        controlPoint1: Qt.point(calculateControlPointX(), calculateControlPointY())
        controlPoint2: Qt.point(calculateControlPointX(), calculateControlPointY())

        function calculateControlPointX() {
            var dx = cx - startPoint.x
            var length = 20
            var x_0 = startPoint.x + dx/2
            return x_0 + (curved ? length*Math.cos((angle + 90) * Math.PI / 180) : 0)
        }

        function calculateControlPointY() {
            var dy = cy - startPoint.y
            var length = 20
            var y_0 = startPoint.y + dy/2
            return y_0 + (curved ? length*Math.sin((angle + 90) * Math.PI / 180) : 0)
        }
    }

    Rectangle {
        id: connectionSpot
        x: cx - width / 2
        y: cy - height / 2
        width: 12 + 4 * ltpStrength
        height: width
        radius: (itemA && itemA.inhibitory) ? width / 2 : 0
        rotation: angle + 45
        color: connectionRoot.selected ? "#08306b" : connectionRoot.ltpColor
        antialiasing: true
        smooth: true

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: connectionRoot.clicked(connectionRoot)
        }
    }
}
