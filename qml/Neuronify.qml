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
        // Seed the undo stack with the state as loaded. undoList holds snapshots
        // with the *current* state on top, so without this baseline entry the
        // first edit leaves only one entry and undo() (which needs a previous
        // state to return to) silently did nothing.
        resetUndoHistory()
    }

    // Start an undo history whose only entry is the workspace as it stands now.
    function resetUndoHistory() {
        undoList.length = 0
        redoList.length = 0
        var snapshot = snapshotState()
        if(snapshot) undoList.push(snapshot)
    }

    // One undo entry: the whole workspace as a JSON string. It has to be a
    // string, not the object serializeState() returns — undo()/redo() parse
    // these back with JSON.parse(), and parsing an object stringifies it to
    // "[object Object]" first, so every undo threw a SyntaxError and did
    // nothing. Returns null when the state could not be serialized.
    function snapshotState() {
        try {
            var state = fileManager.serializeState()
            if(!state) return null
            return JSON.stringify(state)
        } catch(e) {
            return null
        }
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
        // Snapshot after the node exists. Recording before the change pushed the
        // *previous* state, which put undo one step behind: every undo jumped
        // back two edits instead of one.
        stateChange()
        return entity
    }

    function connectEntities(itemA, itemB, filename, properties) {
        if(itemA === itemB || connectionExists(itemA, itemB) || !itemB.canReceiveConnections) return null

        undoRecordingDepth += 1

        var connectionComponent = filename ? Qt.createComponent(filename)
                                : (itemA.preferredEdge ? itemA.preferredEdge : Qt.createComponent("Edge.qml"))

        var connection = connectionComponent.createObject(connectionLayer)
        if (!connection) {
            // Must unwind the guard, or undo recording stays off for good.
            undoRecordingDepth -= 1
            return null
        }

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
            // setSelection, not a bare deselectAll + flag: selectedEntities has
            // to hold the edge too or Cut/Copy/Delete would not see it.
            setSelection([c])
            latestZ -= 1
            c.z = latestZ
            focus = true
        })

        latestZ -= 1
        connection.z = latestZ
        graphEngine.addEdge(connection)
        hasUnsavedChanges = true
        undoRecordingDepth -= 1
        // Snapshot after the edge exists (see createEntity).
        stateChange()
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

    // Shift / Ctrl / Cmd extend a selection rather than replacing it. Cmd is
    // Qt.MetaModifier on macOS and Ctrl is Qt.ControlModifier everywhere else,
    // so accept any of the three and the platform question goes away.
    readonly property int multiSelectModifiers: Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier

    function isMultiSelect(mouse) {
        return mouse !== undefined && mouse !== null
                && (mouse.modifiers & multiSelectModifiers) !== 0
    }

    function isSelected(entity) {
        return entity !== null && entity !== undefined
                && selectedEntities.indexOf(entity) >= 0
    }

    // Replace the selection with `list`. Always assigns a *new* array to
    // selectedEntities: mutating the existing one in place would not notify
    // the bindings that watch it.
    function setSelection(list) {
        deselectAll()
        var next = []
        for(var i = 0; i < list.length; i++) {
            var entity = list[i]
            if(!entity || next.indexOf(entity) >= 0) continue
            entity.selected = true
            next.push(entity)
        }
        selectedEntities = next
        // Prefer a node as the active object -- that is what the properties
        // panel shows, and a rubber-band selection appends the edges last.
        var active = null
        for(var k = next.length - 1; k >= 0; k--) {
            if(!next[k].isEdge) { active = next[k]; break }
        }
        activeObject = active ? active : (next.length > 0 ? next[next.length - 1] : null)
    }

    function addToSelection(entity) {
        if(!entity || isSelected(entity)) {
            if(entity) activeObject = entity
            return
        }
        var next = selectedEntities.slice()
        next.push(entity)
        entity.selected = true
        selectedEntities = next
        activeObject = entity
    }

    function toggleSelection(entity) {
        if(!entity) return
        var index = selectedEntities.indexOf(entity)
        if(index < 0) {
            addToSelection(entity)
            return
        }
        var next = selectedEntities.slice()
        next.splice(index, 1)
        entity.selected = false
        selectedEntities = next
        activeObject = next.length > 0 ? next[next.length - 1] : null
    }

    // Every edge whose two endpoints are both in `nodes`. These travel with a
    // copy/cut and are shown as selected so the user can see what will move.
    function edgesWithin(nodes) {
        var result = []
        for(var i = 0; i < graphEngine.edges.length; i++) {
            var edge = graphEngine.edges[i]
            if(!edge) continue
            if(nodes.indexOf(edge.itemA) >= 0 && nodes.indexOf(edge.itemB) >= 0) {
                result.push(edge)
            }
        }
        return result
    }

    function selectAll() {
        var all = []
        for(var i = 0; i < graphEngine.nodes.length; i++) {
            if(graphEngine.nodes[i]) all.push(graphEngine.nodes[i])
        }
        setSelection(all.concat(edgesWithin(all)))
    }

    // Nodes only — edges are implied by their endpoints when copying.
    function selectedNodes() {
        var nodes = []
        for(var i = 0; i < selectedEntities.length; i++) {
            var entity = selectedEntities[i]
            if(entity && !entity.isEdge) nodes.push(entity)
        }
        if(nodes.length === 0 && activeObject && !activeObject.isEdge) {
            nodes.push(activeObject)
        }
        return nodes
    }

    function clickedEntity(entity, mouse) {
        if(clickMode === "selection") {
            if(isMultiSelect(mouse)) {
                toggleSelection(entity)
            } else if(selectedEntities.length > 1 && isSelected(entity)) {
                // Clicking a member of a group keeps the group intact (so it
                // can be dragged as one); only the active object moves.
                activeObject = entity
            } else {
                setSelection([entity])
            }
        } else if(clickMode === "connectMultipleFromThis") {
            connectEntities(activeObject, entity)
        } else if(clickMode === "connectMultipleToThis") {
            connectEntities(entity, activeObject)
        }
        root.focus = true
    }

    function deselectAll() {
        selectedEntities = []
        activeObject = null

        for(var i = 0; i < graphEngine.nodes.length; i++) {
            if(graphEngine.nodes[i]) graphEngine.nodes[i].selected = false
        }

        for(var j = 0; j < graphEngine.edges.length; j++) {
            if(graphEngine.edges[j]) graphEngine.edges[j].selected = false
        }
    }

    // Select every node whose bounds intersect the rectangle (given in
    // neuronLayer coordinates), plus the edges between them. `additive` keeps
    // whatever was already selected.
    function selectWithin(x1, y1, x2, y2, additive) {
        var left = Math.min(x1, x2), right = Math.max(x1, x2)
        var top = Math.min(y1, y2), bottom = Math.max(y1, y2)

        var hits = []
        for(var i = 0; i < graphEngine.nodes.length; i++) {
            var node = graphEngine.nodes[i]
            if(!node) continue
            if(node.x + node.width < left || node.x > right) continue
            if(node.y + node.height < top || node.y > bottom) continue
            hits.push(node)
        }

        var nodes = additive ? selectedNodes() : []
        for(var h = 0; h < hits.length; h++) {
            if(nodes.indexOf(hits[h]) < 0) nodes.push(hits[h])
        }
        setSelection(nodes.concat(edgesWithin(nodes)))
    }

    function raiseToTop(node) {
        highestZ += 1.0
        node.z = highestZ
    }

    /* -----------------------------
       Workspace Clearing
       ----------------------------- */

    function deleteEverything() {
        // A session recording holds references to the nodes/edges about to be
        // destroyed (and its column set would no longer match the workspace),
        // so end it before tearing the graph down.
        if(recording) stopRecording()
        clearRecording()

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

    // Deletes the whole selection (it used to delete only the active object,
    // which left the rest of a multi-selection behind).
    function deleteSelected() {
        var targets = selectedEntities.slice()
        if(targets.length === 0 && activeObject) targets = [activeObject]
        if(targets.length === 0) return

        // One undo entry for the whole operation, taken at the end.
        undoRecordingDepth += 1

        var edges = []
        var nodes = []
        for(var t = 0; t < targets.length; t++) {
            var target = targets[t]
            if(!target) continue
            if(target.isEdge) edges.push(target)
            else nodes.push(target)
        }

        // Edges first, and every edge touching a doomed node with them —
        // removing a node while an edge still points at it leaves the engine
        // holding a dangling pointer.
        for(var i = graphEngine.edges.length - 1; i >= 0; i--) {
            var edge = graphEngine.edges[i]
            if(!edge) continue
            if(edges.indexOf(edge) < 0
                    && nodes.indexOf(edge.itemA) < 0
                    && nodes.indexOf(edge.itemB) < 0) continue
            graphEngine.removeEdge(edge)
            edge.destroy()
        }

        for(var n = 0; n < nodes.length; n++) {
            graphEngine.removeNode(nodes[n])
            nodes[n].destroy()
        }

        selectedEntities = []
        activeObject = null
        undoRecordingDepth -= 1
        stateChange()
    }

    /* -----------------------------
       Clipboard (cut / copy / paste)
       -----------------------------

       The clipboard holds a serialized sub-graph in exactly the same format as
       a saved file, so paste reuses the loader: the selected nodes plus every
       edge whose two endpoints are both selected.
    */

    property real pasteOffset: 48.0

    function copy() {
        var nodes = selectedNodes()
        if(nodes.length === 0) return false
        var state = fileManager.serializeState(nodes)
        if(!state) {
            console.warn("copy: could not serialize the selection")
            return false
        }
        copiedState = JSON.stringify(state)
        return true
    }

    function cut() {
        if(!copy()) return
        deleteSelected()
    }

    function paste() {
        if(!copiedState) return
        var data
        try {
            data = JSON.parse(copiedState)
        } catch(e) {
            console.warn("paste: clipboard contents could not be parsed")
            return
        }
        if(!data.nodes || data.nodes.length === 0) return

        // Offset the copy so it does not land exactly on top of the original,
        // and keep moving it on every further paste so repeats cascade.
        for(var o = 0; o < data.nodes.length; o++) {
            var saved = data.nodes[o].savedProperties
            if(!saved) continue
            saved.x = (saved.x !== undefined ? saved.x : 0) + pasteOffset
            saved.y = (saved.y !== undefined ? saved.y : 0) + pasteOffset
        }
        copiedState = JSON.stringify(data)

        undoRecordingDepth += 1
        var created = []
        for(var i = 0; i < data.nodes.length; i++) {
            var nodeProps = data.nodes[i]
            // Deep copy: createEntity writes simulator/dragProxy into the dict
            // it is handed, which would otherwise end up back on the clipboard.
            var props = JSON.parse(JSON.stringify(nodeProps.savedProperties || {}))
            created.push(createEntity(nodeProps.filename, props))
        }
        for(var e = 0; e < data.edges.length; e++) {
            var edgeProps = data.edges[e]
            var from = created[parseInt(edgeProps.from)]
            var to = created[parseInt(edgeProps.to)]
            if(from && to) connectEntities(from, to, edgeProps.filename, edgeProps.savedProperties)
        }
        undoRecordingDepth -= 1

        var pasted = []
        for(var c = 0; c < created.length; c++) if(created[c]) pasted.push(created[c])
        setSelection(pasted.concat(edgesWithin(pasted)))
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
       Session recording (all meters + synapse weights -> one CSV)
       -----------------------------

       Samples on the simulation timer, so every column shares one timebase
       regardless of each voltmeter's display settings. Captures, per sample:
         - membrane voltage and a spike flag for every neuron watched by any
           voltmeter (spikes matter because integrate-and-fire resets at
           threshold, so the voltage column alone never shows one), and
         - the synaptic weight of every synapse, which is what makes an LTP
           learning curve quantifiable.
    */

    property bool recording: false
    property bool recordingFull: false
    property real recordInterval: 0.001      // simulation seconds between samples
    property int recordedCount: 0
    property int maximumSamples: 500000
    property var recordRows: []
    property var recordColumns: []
    property real recordElapsed: 0.0
    property real recordNextSample: 0.0
    property var spikeHandlers: []
    property var recordMetadata: null

    function sanitizeName(text) {
        return String(text).replace(/[",\n\r]/g, " ").replace(/\s+/g, "_").trim()
    }

    function nodeLabelOrIndex(node, fallbackPrefix) {
        if(!node) return "none"
        if(node.label && node.label.length > 0) return node.label
        var idx = graphEngine.nodeIndex(node)
        return fallbackPrefix + (idx >= 0 ? idx : "?")
    }

    // Snapshot of what to record. Taken once when recording starts so the
    // column set cannot change mid-run (adding a neuron mid-recording would
    // otherwise misalign the file).
    function buildRecordColumns() {
        var cols = []
        var vmIndex = 0
        for(var i = 0; i < graphEngine.nodes.length; i++) {
            var node = graphEngine.nodes[i]
            if(!node || node.objectName !== "voltmeter" || !node.connectionPlots) continue
            vmIndex += 1
            for(var j = 0; j < node.connectionPlots.length; j++) {
                var neuron = node.connectionPlots[j].connection.itemB
                if(!neuron) continue
                var base = "V" + vmIndex + "_" + sanitizeName(nodeLabelOrIndex(neuron, "n"))
                cols.push({ type: "voltage", name: base + "_mV", node: neuron })
                cols.push({ type: "spike", name: base + "_spike", node: neuron, spiked: false })
            }
        }
        var sIndex = 0
        for(var e = 0; e < graphEngine.edges.length; e++) {
            var edge = graphEngine.edges[e]
            if(!edge) continue
            if(edge.objectName !== "CurrentSynapse"
                    && edge.objectName !== "ImmediateFireSynapse") continue
            sIndex += 1
            var nameA = sanitizeName(nodeLabelOrIndex(edge.itemA, "n"))
            var nameB = sanitizeName(nodeLabelOrIndex(edge.itemB, "n"))
            cols.push({ type: "weight",
                        name: "S" + sIndex + "_" + nameA + "_to_" + nameB + "_weight",
                        edge: edge })
        }
        return cols
    }

    function startRecording() {
        stopRecording()
        recordColumns = buildRecordColumns()
        recordRows = []
        recordedCount = 0
        recordingFull = false
        recordElapsed = 0.0
        recordNextSample = 0.0

        var handlers = []
        for(var c = 0; c < recordColumns.length; c++) {
            var col = recordColumns[c]
            if(col.type !== "spike" || !col.node) continue
            var fn = (function(column) {
                return function() { column.spiked = true }
            })(col)
            col.node.fired.connect(fn)
            handlers.push({ node: col.node, fn: fn })
        }
        spikeHandlers = handlers
        // Snapshot the parameters this run was recorded under, for the sidecar.
        recordMetadata = buildMetadata()
        recording = true
    }

    function stopRecording() {
        for(var h = 0; h < spikeHandlers.length; h++) {
            try { spikeHandlers[h].node.fired.disconnect(spikeHandlers[h].fn) } catch(e) {}
        }
        spikeHandlers = []
        recording = false
        recordedCount = recordRows.length
    }

    function clearRecording() {
        recordRows = []
        recordedCount = 0
        recordingFull = false
        recordElapsed = 0.0
        recordNextSample = 0.0
    }

    function sampleRecording(dt) {
        if(!recording || recordingFull) return
        recordElapsed += dt
        if(recordElapsed < recordNextSample) return
        recordNextSample = recordElapsed + recordInterval

        var row = [recordElapsed * 1000.0]
        for(var c = 0; c < recordColumns.length; c++) {
            var col = recordColumns[c]
            if(col.type === "voltage") {
                row.push((col.node && col.node.voltage !== undefined)
                         ? col.node.voltage * 1000.0 : NaN)
            } else if(col.type === "spike") {
                row.push(col.spiked ? 1 : 0)
                col.spiked = false
            } else {
                row.push(col.edge ? col.edge.synapticWeight : NaN)
            }
        }
        recordRows.push(row)
        // Throttled counter: updating per sample would repaint the panel
        // thousands of times a second.
        if(recordRows.length % 100 === 0) recordedCount = recordRows.length
        if(recordRows.length >= maximumSamples) {
            recordingFull = true
            stopRecording()
        }
    }

    function sessionCsvText() {
        var header = ["time_ms"]
        for(var c = 0; c < recordColumns.length; c++) header.push(recordColumns[c].name)
        var lines = [header.join(",")]
        for(var r = 0; r < recordRows.length; r++) {
            var row = recordRows[r]
            var cells = []
            for(var k = 0; k < row.length; k++) {
                var v = row[k]
                if(v === null || v === undefined || isNaN(v)) { cells.push(""); continue }
                if(k === 0) { cells.push(v.toFixed(3)); continue }
                cells.push(recordColumns[k - 1].type === "spike"
                           ? String(v) : v.toFixed(4))
            }
            lines.push(cells.join(","))
        }
        return lines.join("\n") + "\n"
    }

    // Full parameter snapshot of the circuit, so a CSV stays attributable to
    // the conditions that produced it. Values are converted to the same units
    // the UI and the CSV use (mV, ms, nA).
    // Flattens an object's savedProperties PropertyGroups into a plain map.
    // Using the groups rather than reading properties directly picks up values
    // that live on child objects (e.g. a neuron's resistance is on its
    // LeakCurrent, not on the engine) and covers every node/edge type.
    function dumpSavedProperties(obj) {
        var out = {}
        if(!obj || !obj.savedProperties) return out
        for(var i in obj.savedProperties) {
            var props = obj.savedProperties[i].dump()
            for(var k in props) {
                var v = props[k]
                if(typeof v === "object" && v !== null) continue   // skip nested objects
                out[k] = v
            }
        }
        return out
    }

    function buildMetadata() {
        function mv(v)  { return (v === undefined || v === null) ? null : v * 1000.0 }
        function ms(v)  { return (v === undefined || v === null) ? null : v * 1000.0 }
        function na(v)  { return (v === undefined || v === null) ? null : v * 1e9 }
        function num(v) { return (v === undefined) ? null : v }

        var meta = {
            neuronify_version: (typeof Version !== "undefined") ? Version.identifier : "unknown",
            recorded_at: new Date().toISOString(),
            sampling: {
                interval_ms: recordInterval * 1000.0,
                playback_speed: playbackSpeed
            },
            units_note: "*_si values are raw SI base units (V, s, F, Ohm, A); named fields are converted to mV / ms / nA.",
            voltmeters: [],
            neurons: [],
            synapses: []
        }

        var vmIndex = 0
        for(var i = 0; i < graphEngine.nodes.length; i++) {
            var node = graphEngine.nodes[i]
            if(!node || node.objectName !== "voltmeter" || !node.connectionPlots) continue
            vmIndex += 1
            meta.voltmeters.push({
                index: vmIndex,
                time_span_ms: ms(node.timeRange),
                v_min_mV: num(node.minimumValue),
                v_max_mV: num(node.maximumValue),
                voltage_divisions: num(node.gridDivisionsY),
                time_divisions: num(node.gridDivisionsX)
            })
            for(var j = 0; j < node.connectionPlots.length; j++) {
                var n = node.connectionPlots[j].connection.itemB
                if(!n) continue
                var np = dumpSavedProperties(n.engine)
                meta.neurons.push({
                    column_prefix: "V" + vmIndex + "_" + sanitizeName(nodeLabelOrIndex(n, "n")),
                    label: n.label ? n.label : "",
                    type: n.filename ? n.filename : n.objectName,
                    inhibitory: (n.inhibitory === true),
                    threshold_mV: mv(np.threshold),
                    resting_potential_mV: mv(np.restingPotential),
                    initial_potential_mV: mv(np.initialPotential),
                    resistance_ohm: num(np.resistance),
                    capacitance_F: num(np.capacitance),
                    refractory_period_ms: ms(np.refractoryPeriod),
                    parameters_si: np
                })
            }
        }

        var sIndex = 0
        for(var e = 0; e < graphEngine.edges.length; e++) {
            var edge = graphEngine.edges[e]
            if(!edge) continue
            if(edge.objectName !== "CurrentSynapse"
                    && edge.objectName !== "ImmediateFireSynapse") continue
            sIndex += 1
            var ep = dumpSavedProperties(edge.engine)
            meta.synapses.push({
                column: "S" + sIndex + "_" + sanitizeName(nodeLabelOrIndex(edge.itemA, "n"))
                        + "_to_" + sanitizeName(nodeLabelOrIndex(edge.itemB, "n")) + "_weight",
                from: nodeLabelOrIndex(edge.itemA, "n"),
                to: nodeLabelOrIndex(edge.itemB, "n"),
                type: edge.objectName,
                maximum_current_nA: na(ep.maximumCurrent),
                delay_ms: ms(ep.delay),
                time_constant_ms: ms(ep.tau),
                ltp: {
                    enabled: (edge.ltpEnabled === true),
                    baseline_weight: num(edge.baselineWeight),
                    max_weight: num(edge.maxWeight),
                    learning_rate: num(edge.learningRate),
                    spike_window_s: num(edge.detectionWindow),
                    spike_threshold: num(edge.spikeThreshold),
                    forgetting_rate_per_s: num(edge.forgettingRate)
                },
                weight_at_start: num(edge.synapticWeight),
                parameters_si: ep
            })
        }
        return meta
    }

    function metadataJson() {
        var meta = recordMetadata
                 ? JSON.parse(JSON.stringify(recordMetadata))
                 : buildMetadata()
        meta.exported_at = new Date().toISOString()
        meta.sampling.samples = recordRows.length
        meta.sampling.duration_ms = recordRows.length > 0
                ? recordRows[recordRows.length - 1][0] : 0

        meta.columns = [{ name: "time_ms", kind: "time" }]
        for(var c = 0; c < recordColumns.length; c++) {
            meta.columns.push({ name: recordColumns[c].name, kind: recordColumns[c].type })
        }

        // Final weights let a reader see how far each synapse moved during the run.
        for(var k = 0; k < recordColumns.length; k++) {
            var col = recordColumns[k]
            if(col.type !== "weight" || !col.edge) continue
            for(var m = 0; m < meta.synapses.length; m++) {
                if(meta.synapses[m].column === col.name) {
                    meta.synapses[m].weight_at_export = col.edge.synapticWeight
                    break
                }
            }
        }
        return JSON.stringify(meta, null, 2) + "\n"
    }

    // Writes the CSV plus a "<name>.metadata.json" sidecar recording the
    // parameters the data was produced under.
    function exportSessionCsv(fileUrl) {
        var ok = FileIO.writeSynchronously(fileUrl, sessionCsvText())
        var metaUrl = String(fileUrl).replace(/\.csv$/i, "") + ".metadata.json"
        FileIO.writeSynchronously(metaUrl, metadataJson())
        return ok
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
        onTriggered: {
            var dt = 0.001 * root.playbackSpeed
            graphEngine.step(dt)
            // Sample after stepping so recorded values match the state the
            // meters are showing for this tick.
            sampleRecording(dt)
        }
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
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            // Hover must NOT be enabled: with it on, onPositionChanged fires on plain
            // cursor movement and pans the workspace, making everything follow the mouse.
            // Panning happens only during an actual click-drag (see onPositionChanged).
            hoverEnabled: false

            property point lastPanPos
            property bool panActive: false
            // Right-button drag zooms; the zoom stays anchored on the point the
            // drag started from so the scene does not slide out from under it.
            property bool zoomActive: false
            property point zoomAnchor
            // Shift / Ctrl / Cmd + drag on the background rubber-band selects.
            // Plain left-drag still pans, so the two never collide.
            property bool selectActive: false
            property point selectOrigin

            // Scale about (cx, cy) in this item's coordinates.
            function zoomBy(factor, cx, cy) {
                var oldScale = workspace.scale
                var newScale = Math.max(0.1, Math.min(4.0, oldScale * factor))
                if (newScale === oldScale) return
                workspace.scale = newScale
                workspace.x = cx - (cx - workspace.x) * (newScale / oldScale)
                workspace.y = cy - (cy - workspace.y) * (newScale / oldScale)
            }

            onWheel: {
                // Scrolling zooms, on a wheel and on a trackpad alike. It used to
                // pan on anything that reported a pixelDelta (every trackpad and
                // the Magic Mouse), which both duplicated the left-drag pan and
                // left those devices with no way to zoom at all.
                var factor
                if (wheel.pixelDelta.y !== 0) {
                    // Continuous: proportional to the gesture, but capped at 5%
                    // per event so one coarse event from a mouse driver or a
                    // momentum flick cannot jump the whole zoom range.
                    var step = Math.max(-0.05, Math.min(0.05, wheel.pixelDelta.y * 0.0025))
                    factor = Math.exp(step)
                } else {
                    factor = Math.pow(1.1, wheel.angleDelta.y / 120) // 10% per notch
                }
                zoomBy(factor, wheel.x, wheel.y)
                wheel.accepted = true
            }

            onPressed: {
                lastPanPos = Qt.point(mouse.x, mouse.y)
                panActive = false
                zoomActive = false
                selectActive = false
                if (mouse.button === Qt.RightButton) {
                    zoomActive = true
                    zoomAnchor = Qt.point(mouse.x, mouse.y)
                } else if (mouse.button === Qt.LeftButton) {
                    if (root.isMultiSelect(mouse)) {
                        selectActive = true
                        selectOrigin = Qt.point(mouse.x, mouse.y)
                        selectionBox.x = mouse.x
                        selectionBox.y = mouse.y
                        selectionBox.width = 0
                        selectionBox.height = 0
                        selectionBox.visible = true
                    } else {
                        deselectAll()
                        root.backgroundClicked()
                    }
                    root.focus = true
                }
                mouse.accepted = true
            }

            onReleased: {
                if (selectActive) {
                    selectionBox.visible = false
                    // The box is drawn in this item's coordinates; the nodes
                    // live inside the scaled/panned workspace, so map both
                    // corners across before testing them.
                    var a = mapToItem(neuronLayer, selectOrigin.x, selectOrigin.y)
                    var b = mapToItem(neuronLayer, mouse.x, mouse.y)
                    // A modifier-click with no drag should not wipe the
                    // selection, so ignore boxes that never opened up.
                    if (Math.abs(mouse.x - selectOrigin.x) > 3
                            || Math.abs(mouse.y - selectOrigin.y) > 3) {
                        root.selectWithin(a.x, a.y, b.x, b.y, true)
                    }
                }
                panActive = false
                zoomActive = false
                selectActive = false
            }

            onPositionChanged: {
                // Only act while a mouse button is actually held down (click-drag).
                // Without this guard, moving the cursor alone would drag the whole
                // workspace around. Zoom (onWheel) is unaffected.
                if (!pressed) return

                var dx = mouse.x - lastPanPos.x
                var dy = mouse.y - lastPanPos.y
                lastPanPos = Qt.point(mouse.x, mouse.y)

                if (zoomActive) {
                    // Push the mouse forward (up the screen, dy < 0) to zoom in,
                    // pull it back to zoom out.
                    zoomBy(Math.exp(-dy * 0.006), zoomAnchor.x, zoomAnchor.y)
                    return
                }

                if (selectActive) {
                    selectionBox.x = Math.min(selectOrigin.x, mouse.x)
                    selectionBox.y = Math.min(selectOrigin.y, mouse.y)
                    selectionBox.width = Math.abs(mouse.x - selectOrigin.x)
                    selectionBox.height = Math.abs(mouse.y - selectOrigin.y)
                    return
                }

                if (!panActive && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                    panActive = true
                }
                if (panActive) {
                    workspace.x += dx
                    workspace.y += dy
                }
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

        // Rubber-band selection box. Lives outside `workspace` so it is drawn
        // on top of the nodes and is not itself scaled by the zoom.
        Rectangle {
            id: selectionBox
            visible: false
            z: 100
            color: Qt.rgba(0.42, 0.68, 0.84, 0.18)
            border.color: Qt.rgba(0.25, 0.49, 0.72, 0.9)
            border.width: 1
            antialiasing: true
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
            var snapshot = snapshotState()
            if(snapshot) {
                undoList.push(snapshot)
                redoList.length = 0
            }
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
