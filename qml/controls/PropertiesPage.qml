import QtQuick 2.6
import QtQuick.Controls 2.1

import "qrc:/qml/style"

Item {
    property string title
    property StackView stackView: null
    default property alias _data: column.data

    width: 320
    // Grow to fit the controls rather than clipping them (the properties panel
    // sizes itself to this item and clips the overflow). 320 stays the minimum,
    // so existing, shorter panels are unaffected. column.implicitHeight is
    // derived from the children, so this does not feed back into the anchors.
    height: Math.max(320, column.implicitHeight + 48)

    Column {
        id: column
        anchors {
            fill: parent
            margins: 24
        }

        spacing: Style.spacing
    }
}
