import QtQuick 2.6
import QtQuick.Controls 2.1

import "qrc:/qml/style"

Item {
    property string title
    property StackView stackView: null
    default property alias _data: column.data

    // These are *implicit* sizes on purpose. The properties panel's Loader sizes
    // itself from item.implicitWidth/implicitHeight and then resizes the page to
    // match; reading an explicit width here instead left the panel one load
    // behind, so the first neuron you clicked got the previous page's width.
    implicitWidth: 320
    // Grow to fit the controls rather than clipping them (the properties panel
    // sizes itself to this item and clips the overflow). 320 stays the minimum,
    // so existing, shorter panels are unaffected. column.implicitHeight is
    // derived from the children, so this does not feed back into the anchors.
    implicitHeight: Math.max(320, column.implicitHeight + 48)

    Column {
        id: column
        anchors {
            fill: parent
            margins: 24
        }

        spacing: Style.spacing
    }
}
