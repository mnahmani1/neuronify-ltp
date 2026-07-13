import QtQuick 2.0
import "paths"

Item {
    id: root
    signal dropped(var connector)

    property Node _parent: parent

    property point attachmentPoint: Qt.point(parent.width / 2, parent.height / 2)
    property point initialPoint: Qt.point(parent.width , parent.height)
    property point offset: Qt.point(0.0, 0.0)

    property alias connectorWidth: connectorCircle.width
    property alias connectorHeight: connectorCircle.height

    property color color: "pink"
    property color connectorColor: color

    // dragInProgress keeps AnchorChanges active and Drag.active alive through
    // the release event — without this the circle snaps back before Drag.drop().
    property bool dragInProgress: false

    property bool childrenVisible: (_parent.selected ||
                                   connectorMouseArea.containsMouse ||
                                   dragInProgress)

    MouseArea {
        id: parentMouseArea
        parent: root.parent
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    SCurve {
        id: curve

        color: root.color
        parent: root.parent
        z: -1
        startPoint: root.attachmentPoint
        endPoint: {
            if(root.dragInProgress) {
                return Qt.point(connectorMouseArea.x + connectorCircle.x + connectorCircle.width / 2,
                                connectorMouseArea.y + connectorCircle.y + connectorCircle.height / 2)
            } else {
                return Qt.point(root.initialPoint.x + connectorMouseArea.width / 2, root.initialPoint.y + connectorMouseArea.height / 2)
            }
        }
        visible: root.childrenVisible
    }


    MouseArea {
        id: connectorMouseArea
        x: root.initialPoint.x
        y: root.initialPoint.y
        hoverEnabled: true
        width: 64
        height: width
        // No drag.target here: using drag.target causes Qt to call
        // QQuickDrag::cancel() on mouse release BEFORE onReleased fires,
        // which exits any DropArea and makes Drag.drop() return IgnoreAction.
        // Instead we update connectorCircle position manually in onPositionChanged.

        property point lastMouse
        property bool didDrag: false

        onPressed: {
            root.dragInProgress = true
            connectorCircle.Drag.active = true
            lastMouse = Qt.point(mouse.x, mouse.y)
            didDrag = false
        }

        onPositionChanged: {
            if (root.dragInProgress) {
                var dx = mouse.x - lastMouse.x
                var dy = mouse.y - lastMouse.y
                connectorCircle.x += dx
                connectorCircle.y += dy
                lastMouse = Qt.point(mouse.x, mouse.y)
                if (!didDrag && (dx*dx + dy*dy) > 4)
                    didDrag = true
            }
        }

        onReleased: {
            connectorCircle.Drag.drop()
            connectorCircle.Drag.active = false
            root.dragInProgress = false
        }

        onClicked: {
            if (!didDrag) {
                root.parent.clickedConnector(parent, mouse)
            }
        }

        Rectangle {
            id: connectorCircle

            property Node node: root._parent

            visible: root.childrenVisible
            width: 24
            height: width
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
            }
            Drag.keys: ["connector"]
            Drag.active: false
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            color: connectorColor
            border.color: "#f7fbff"
            border.width: 1.0
            radius: width

            states: State {
                when: root.dragInProgress
                AnchorChanges { target: connectorCircle; anchors.verticalCenter: undefined; anchors.horizontalCenter: undefined }
            }
        }
    }
}
