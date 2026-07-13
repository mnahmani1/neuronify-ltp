import QtQuick 2.5
import QtQuick.Controls 2.1
import QtQuick.Dialogs 1.0
import QtQuick.Layouts 1.1
import QtQuick.Particles 2.0
import QtQuick.Window 2.1
import QtCharts 2.1
import QtMultimedia 5.5
import Qt.labs.settings 1.0
import Neuronify 1.0
import CuteVersioning 1.0
import QtGraphicalEffects 1.0

import "qrc:/qml/hud"
import "qrc:/qml/style"
import "qrc:/qml/io"
import "qrc:/qml/tools"
import "qrc:/qml/controls"

Rectangle {
    id: root

    signal simulationLoaded
    signal backgroundClicked

    property alias workspace: workspace
    property alias graphEngine: graphEngine
    property alias fileManager: fileManager
    property alias shaderEffectItem: workspaceFlickable
    property var selectedEntities: []
    property var draggedEntity: undefined
    property var copiedNeurons: []
    property real currentTimeStep: 0.0
    property real time: 0.0
    property var activeObject: null
    property var undoList: []
    property var redoList: []
    property var currentUndoState
    readonly property bool undoRecordingEnabled: undoRecordingDepth === 0
    property int undoRecordingDepth: 0
    readonly property bool paused: root.playbackSpeed <= 0.0
    readonly property bool running: applicationActive && !paused && !autoPause
    property string clickMode: "selection"
    property real highestZ: 0.0
    property bool snappingEnabled: false
    property real snapGridSize: snappingEnabled ? 32.0 : 1.0
    property real playbackSpeed: 1.0
    property bool advanced: false
    property int latestZ: 0
    property bool autoPause: false
    property bool hasUnsavedChanges: true
    property var copiedState

    property bool applicationActive: {
        if(Qt.platform.os === "android" || Qt.platform.os === "ios") {
            return Qt.application.state === Qt.ApplicationActive;
        } else {
            return true;
        }
    }

    width: 1280
    height: 900
    color: "#f7fbff"
    antialiasing: true
    smooth: true
    focus: true

    Component.onCompleted: {
        Style.playbackSpeed = root.playbackSpeed
    }

    onPlaybackSpeedChanged: {
        Style.playbackSpeed = root.playbackSpeed
    }

    /* -----------------------------
       State Management Functions
       ----------------------------- */

    function loadSimulation(fileUrl) {
        var code = fileManager.read(fileUrl)
        if(!code) {
            console.error("Load state got empty contents.")
            return
        }
        reloadState(code)
    }

    function reloadState(simulationString) {
        var data = JSON.parse(simulationString)
        deleteEverything()
        loadState(data)
        hasUnsavedChanges = false
        undoList.length = 0
        redoList.length = 0
    }

    function loadState(data) {
        if(!data.nodes || !data.edges) {
            console.warn("No nodes or edges in simulation data.")
            return
        }

        undoRecordingDepth += 1
        var createdNodes = []

        for(var nIndex = 0; nIndex < data.nodes.length; nIndex++) {
            var nodeProps = data.nodes[nIndex]
            var entity = createEntity(nodeProps.filename, nodeProps.savedProperties)
            if(entity) createdNodes.push(entity)
        }

        for(var eIndex = 0; eIndex < data.edges.length; eIndex++) {
            var edgeProps = data.edges[eIndex]
            var fromIndex = parseInt(edgeProps.from)
            var toIndex = parseInt(edgeProps.to)
            if(createdNodes[fromIndex] && createdNodes[toIndex]) {
                connectEntities(createdNodes[fromIndex], createdNodes[toIndex], edgeProps.filename, edgeProps.savedProperties)
            }
        }

        undoRecordingDepth -= 1
        simulationLoaded()
        return createdNodes
    }

    /* -----------------------------
       Node & Edge Management
       ----------------------------- */

    // Apply a saved node properties dict onto a freshly created node. createObject
    // only applies flat top-level keys (x, y, label, inhibitory); the nested "engine"
    // group (threshold, resistance, capacitance, restingPotential, ...) must be applied
    // here. Runs after createObject, i.e. after the node's Component.onCompleted has
    // reset properties to defaults, so restored values are not clobbered. Non-scalar
    // values inside engine (dynamic state) are skipped for safety.
    function applyNodeProperties(entity, props) {
        for (var key in props) {
            if (key === "filename" || key === "simulator" || key === "dragProxy") continue
            var value = props[key]
            if (value !== null && typeof value === "object") {
                var sub = entity[key]
                if (sub) {
                    for (var subKey in value) {
                        var subVal = value[subKey]
                        if (subVal !== null && typeof subVal === "object") continue
                        try { sub[subKey] = subVal } catch(e) {}
                    }
                }
                continue
            }
            try { entity[key] = value } catch(e2) {}
        }
    }

    function createEntity(fileUrl, properties) {
        var component = Qt.createComponent(fileUrl)
        if(component.status !== Component.Ready) {
            console.error("Could not create component: " + fileUrl + " error: " + component.errorString())
            return null
        }

        properties = properties || {}
        properties.simulator = root
        properties.dragProxy = dragProxy

        var entity = component.createObject(neuronLayer, properties)
        if(!entity) {
            console.error("Failed to create entity from component " + fileUrl)
            return null
        }

        // Restore nested engine config (and any other saved node properties) that
        // createObject cannot set through initial-property assignment.
        applyNodeProperties(entity, properties)

        stateChange()
        undoRecordingDepth += 1

        entity.clicked.connect(clickedEntity)
        entity.clicked.connect(raiseToTop)
        entity.dragStarted.connect(raiseToTop)
        entity.receivedDrop.connect(function(from) {
            connectEntities(from, entity)
        })

        graphEngine.addNode(entity)
        hasUnsavedChanges = true
        undoRecordingDepth -= 1
        return entity
    }

    function connectEntities(itemA, itemB, filename, properties) {
        if(itemA === itemB || connectionExists(itemA, itemB) || !itemB.canReceiveConnections) return null

        stateChange()
        undoRecordingDepth += 1

        var connectionComponent = filename ? Qt.createComponent(filename)
                                : (itemA.preferredEdge ? itemA.preferredEdge : Qt.createComponent("Edge.qml"))

        var connection = connectionComponent.createObject(connectionLayer)
        if (!connection)
            return null

        connection.itemA = itemA
        connection.itemB = itemB
        connection.isPlaced = true

        connection.playbackSpeed = root.playbackSpeed

        // Restore saved edge properties (LTP settings + engine synapse params).
        // `properties` is the edge's savedProperties dict from the file; it is
        // undefined for freshly drawn edges, which correctly keep their defaults.
        if (properties) {
            applyEdgeProperties(connection, properties)
        }

        connection.clicked.connect(function(c) {
            deselectAll()
            activeObject = c
            c.selected = true
            latestZ -= 1
            c.z = latestZ
            focus = true
        })

        latestZ -= 1
        connection.z = latestZ
        graphEngine.addEdge(connection)
        hasUnsavedChanges = true
        undoRecordingDepth -= 1
        return connection
    }

    // Apply a saved edge properties dict (from a file) back onto a connection.
    // Handles the nested "engine" group (synapse tau/delay/current, etc.) and the
    // flat edge-level settings (LTP configuration). Unknown or read-only keys are
    // skipped defensively so older/newer file formats never break loading.
    function applyEdgeProperties(connection, props) {
        // Engine keys that are CONFIGURATION (safe to restore). Dynamic runtime
        // state (linear, exponential, triggers, time) is intentionally excluded:
        // restoring e.g. triggers (saved as {}) would replace the working array
        // and break the running engine.
        var engineConfigKeys = ["tau", "maximumCurrent", "delay", "alphaFunction"]
        for (var key in props) {
            if (key === "filename" || key === "from" || key === "to") continue
            var value = props[key]
            if (key === "engine") {
                if (connection.engine && value && typeof value === "object") {
                    for (var i = 0; i < engineConfigKeys.length; i++) {
                        var ek = engineConfigKeys[i]
                        if (value[ek] !== undefined) {
                            try { connection.engine[ek] = value[ek] } catch(e) {}
                        }
                    }
                }
                continue
            }
            // Only flat scalar settings remain (LTP config); skip any other nested objects.
            if (value !== null && typeof value === "object") continue
            try { connection[key] = value } catch(e2) {}
        }
    }

    function connectionExists(itemA, itemB) {
        for(var index = 0; index < graphEngine.edges.length; index++) {
            var existing = graphEngine.edges[index]
            if(existing.itemA === itemA && existing.itemB === itemB) {
                return true
            }
        }
        return false
    }

    /* -----------------------------
       Selection / Interaction
       ----------------------------- */

    function clickedEntity(entity, mouse) {
        if(clickMode === "selection") {
            if(activeObject) activeObject.selected = false
            deselectAll()
            selectedEntities = [entity]
            entity.selected = true
            activeObject = entity
        } else if(clickMode === "connectMultipleFromThis") {
            connectEntities(activeObject, entity)
        } else if(clickMode === "connectMultipleToThis") {
            connectEntities(entity, activeObject)
        }
        root.focus = true
    }

    function deselectAll() {
        selectedEntities.length = 0
        activeObject = null

        for(var i = 0; i < graphEngine.nodes.length; i++) {
            if(graphEngine.nodes[i]) graphEngine.nodes[i].selected = false
        }

        for(var j = 0; j < graphEngine.edges.length; j++) {
            if(graphEngine.edges[j]) graphEngine.edges[j].selected = false
        }
    }

    function raiseToTop(node) {
        highestZ += 1.0
        node.z = highestZ
    }

    /* -----------------------------
       Workspace Clearing
       ----------------------------- */

    function deleteEverything() {
        // Snapshot to plain JS arrays first — the C++ QmlListProperty changes
        // length as we remove items, which would crash index-based iteration.
        // Use removeEdge/removeNode (not destroy): they call deleteLater() AND
        // clear the node from m_nodes/m_edges so graphEngine.nodes.length is 0
        // when loadState() starts populating it again.  Without this, old
        // dangling pointers remain in the C++ list alongside the new nodes,
        // causing NodeWrapper::clear() to crash in deselectAll().
        var edgesToDelete = []
        for(var k = 0; k < graphEngine.edges.length; k++) edgesToDelete.push(graphEngine.edges[k])
        for(var m = 0; m < edgesToDelete.length; m++) {
            if(edgesToDelete[m]) graphEngine.removeEdge(edgesToDelete[m])
        }

        var nodesToDelete = []
        for(var n = 0; n < graphEngine.nodes.length; n++) nodesToDelete.push(graphEngine.nodes[n])
        for(var p = 0; p < nodesToDelete.length; p++) {
            if(nodesToDelete[p]) graphEngine.removeNode(nodesToDelete[p])
        }

        selectedEntities = []
        activeObject = null
    }

    function deleteSelected() {
        if (!activeObject) return
        if (activeObject.isEdge) {
            graphEngine.removeEdge(activeObject)
            activeObject.destroy()
        } else {
            var node = activeObject
            for (var i = graphEngine.edges.length - 1; i >= 0; i--) {
                var e = graphEngine.edges[i]
                if (e.itemA === node || e.itemB === node) {
                    graphEngine.removeEdge(e)
                    e.destroy()
                }
            }
            graphEngine.removeNode(node)
            node.destroy()
        }
        activeObject = null
        stateChange()
    }

    function open(simulation) {
        if (!simulation) return
        // .neuronify files are SQLite databases; NeuronifyFile::open() already
        // extracted the simulation JSON into simulation.data. Prefer that over
        // re-reading the raw file as text (which would be unparseable binary).
        if (simulation.data) {
            reloadState(simulation.data)
            return
        }
        if (simulation.file) {
            loadSimulation(simulation.file)
        }
    }

    function save(simulation, callback) {
        if (!simulation || !simulation.file) return

        // .neuronify files are SQLite databases. Write them via NeuronifyFile
        // (the SQLite writer) so they can be reopened by NeuronifyFile.open().
        // The previous path wrote plain JSON text, which the SQLite-based open
        // path could not read back.
        var state = fileManager.serializeState()
        if (!state) {
            console.error("save: could not serialize state, aborting")
            return
        }
        var jsonString = JSON.stringify(state, null, 4)
        var name = (simulation.name && simulation.name.length > 0)
                    ? simulation.name : "Neuronify simulation"
        var description = simulation.description ? simulation.description : ""

        function writeFile(grabResult) {
            var ok = (grabResult !== undefined)
                ? NeuronifyFile.save(simulation.file, name, description, jsonString, grabResult)
                : NeuronifyFile.save(simulation.file, name, description, jsonString)
            if (ok) hasUnsavedChanges = false
            if (callback) callback()
        }

        // Capture a thumbnail for the file (as the original format stores one),
        // then write. If the grab can't be scheduled, save without a screenshot.
        var scheduled = root.grabToImage(function(result) { writeFile(result) })
        if (!scheduled) {
            writeFile(undefined)
        }
    }

    /* -----------------------------
       Graph Engine & Workspace
       ----------------------------- */

    GraphEngine { id: graphEngine }

    Timer {
        id: simulationTimer
        interval: 1
        repeat: true
        running: root.running
        onTriggered: graphEngine.step(0.001 * root.playbackSpeed)
    }


    Rectangle { id: workspaceBackground; anchors.fill: workspaceFlickable; color: "#fafcfe" }

    Item {
        id: workspaceFlickable
        anchors.fill: parent
        antialiasing: true
        clip: true

        // Background: pan, zoom, background clicks.
        // Defined first so nodes (inside workspace) sit on top.
        MouseArea {
            id: workspaceMouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            hoverEnabled: true

            property point lastPanPos
            property bool panActive: false

            onWheel: {
                if (wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0) {
                    // Trackpad two-finger scroll → pan
                    workspace.x += wheel.pixelDelta.x
                    workspace.y += wheel.pixelDelta.y
                } else {
                    // Mouse wheel → zoom toward cursor
                    var factor = wheel.angleDelta.y > 0 ? 1.1 : (1.0 / 1.1)
                    var newScale = Math.max(0.1, Math.min(4.0, workspace.scale * factor))
                    var oldScale = workspace.scale
                    var cx = wheel.x
                    var cy = wheel.y
                    workspace.scale = newScale
                    workspace.x = cx - (cx - workspace.x) * (newScale / oldScale)
                    workspace.y = cy - (cy - workspace.y) * (newScale / oldScale)
                }
                wheel.accepted = true
            }

            onPressed: {
                lastPanPos = Qt.point(mouse.x, mouse.y)
                panActive = false
                if (mouse.button === Qt.LeftButton) {
                    deselectAll()
                    root.backgroundClicked()
                    root.focus = true
                }
                mouse.accepted = true
            }

            onPositionChanged: {
                var dx = mouse.x - lastPanPos.x
                var dy = mouse.y - lastPanPos.y
                if (!panActive && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                    panActive = true
                }
                if (panActive) {
                    workspace.x += dx
                    workspace.y += dy
                }
                lastPanPos = Qt.point(mouse.x, mouse.y)
            }
        }

        // Accept drops from the creation toolbar
        DropArea {
            id: workspaceDropArea
            anchors.fill: parent
            keys: ["lol"]
            onDropped: {
                var creationItem = drop.source ? drop.source.creationItem : null
                if (!creationItem || !creationItem.source) return
                var pos = mapToItem(neuronLayer, drop.x, drop.y)
                // Suppress undo serialization while the drag event is still
                // being delivered — iterating graphEngine.nodes during an
                // active drag crashes in QV4's iterator (same guard loadState uses).
                undoRecordingDepth += 1
                createEntity(creationItem.source, {x: pos.x - 36, y: pos.y - 36})
                undoRecordingDepth -= 1
                stateChange()
            }
        }

        // Pinch-to-zoom for touch / trackpad
        PinchArea {
            id: pinchArea
            anchors.fill: parent
            property real startScale: 1.0
            property real startX: 0
            property real startY: 0

            onPinchStarted: {
                startScale = workspace.scale
                startX = workspace.x
                startY = workspace.y
            }
            onPinchUpdated: {
                var newScale = Math.max(0.1, Math.min(4.0, pinch.scale * startScale))
                var cx = pinch.center.x
                var cy = pinch.center.y
                workspace.scale = newScale
                workspace.x = cx - (cx - startX) * (newScale / startScale)
                workspace.y = cy - (cy - startY) * (newScale / startScale)
            }
        }

        // Workspace: nodes and edges live here so they zoom/pan together.
        Item {
            id: workspace
            x: 0
            y: 0
            width: 3840
            height: 2160
            scale: 1.0
            transformOrigin: Item.TopLeft

            Item { id: connectionLayer; anchors.fill: parent }
            Item { id: neuronLayer;    anchors.fill: parent }
        }

        // Drag proxy kept for API compatibility
        Item { id: dragProxy; property point previousPosition; property point gridPosition }
    }

    FileManager { id: fileManager; graphEngine: graphEngine; workspace: workspace }

    /* -----------------------------
       Undo / Redo / State Change
       ----------------------------- */

    function stateChange() {
        hasUnsavedChanges = true;
        if(undoRecordingEnabled) {
            try {
                undoList.push(fileManager.serializeState());
            } catch(e) {}
            redoList.length = 0
        }
    }

    function undo() {
        if (undoList.length < 2) return
        redoList.push(undoList.pop())
        var state = JSON.parse(undoList[undoList.length - 1])
        undoRecordingDepth += 1
        deleteEverything()
        loadState(state)
        undoRecordingDepth -= 1
    }

    function redo() {
        if (redoList.length === 0) return
        var entry = redoList.pop()
        undoList.push(entry)
        var state = JSON.parse(entry)
        undoRecordingDepth += 1
        deleteEverything()
        loadState(state)
        undoRecordingDepth -= 1
    }
}
