import QtQuick
import QtQuick.Layouts
import qs.app
import qs.services
import qs.Commons
import QtQuick.Controls

// Slim release banner at the top of a reader (S3, A4).
//
// It only reports what services/Updater.qml decided: the banner is visible
// while a newer numbered release exists and Later was not pressed. The Update
// button is offered only when the installed tree can really update (a clean
// `main` checkout); otherwise the second line names the reason (S4).
//
// Colours, spacing and radius come from the theme tokens, and every string
// travels through I18n (tools/lint-style.js and tools/lint-i18n.js stay quiet).
Rectangle {
    id: root

    // What `--reopen` gets after the update restarts Kisaru.
    property string panel: ""

    visible: Updater.visible
    implicitHeight: Style.space(44)
    color: Colors.surface_container_high

    function hint() {
        if (Updater.blocked === "reinstall") return KisaruI18n.t("update.reinstall")
        if (Updater.blocked === "not-main") return KisaruI18n.t("update.notMain")
        if (Updater.blocked === "dirty") return KisaruI18n.t("update.dirty")
        return ""
    }

    // One button recipe for both actions: the primary fill for Update, the
    // quiet container for Later.
    component BannerButton: Button {
        id: button

        property bool solid: false

        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.xs

        contentItem: StyledText {
            text: button.text
            font: button.font
            color: button.solid ? Colors.on_primary : Colors.on_surface
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: Style.cornerRadius
            color: button.solid ? Colors.primary : Colors.surface_container_low
        }
    }

    Divider {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        opacity: 0.5
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: Style.spacing.xl
            rightMargin: Style.spacing.xl
            topMargin: Style.spacing.sm
            bottomMargin: Style.spacing.sm
        }
        spacing: Style.spacing.md

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs

            StyledText {
                Layout.fillWidth: true
                text: KisaruI18n.t("update.available", { 1: Updater.latest })
                color: Colors.on_surface
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.hint() !== ""
                text: root.hint()
                color: Colors.on_surface_variant
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }
        }

        BannerButton {
            visible: Updater.canUpdate
            solid: true
            text: KisaruI18n.t("update.action")
            onClicked: Updater.launch(root.panel)
        }

        BannerButton {
            text: KisaruI18n.t("update.later")
            onClicked: Updater.dismiss()
        }
    }
}
