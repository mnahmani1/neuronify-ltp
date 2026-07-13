import QtQuick 2.0
import Neuronify 1.0

import ".."
import "../controls"
import "../hud"

Edge {
    id: root
    objectName: "ImmediateFireSynapse"
    filename: "edges/ImmediateFireSynapse.qml"

    engine: EdgeEngine {
        id: engine

        // Output is reset every step
        onStepped: {
            currentOutput = 0.0;
        }

        // LTP tracking is handled automatically in C++ via EdgeEngine::receiveFireEvent()
        onReceivedFire: {
            currentOutput = 1e6;
        }
    }

    property Component controls: Component {
        LtpSynapseDashboard {
            edge: root
        }
    }
}
