import QtQuick
import Quickshell
import qs.app
import qs.Commons
import qs.components

// Render harness for the version-picker design options (owner, 2026-11-27).
//
// Mockups only: it paints the two redesign options over a dimmed list, like the
// real panel, and saves one PNG per scenario with grabToImage. It does not
// import components/VersionPicker.qml, does not open a panel and synthesizes no
// input: the hover/switch states are plain bindings.
//
// KH_MOCK    B-default · B-hover-row · B-hover-icon · A-off · A-on · A-hover-row
// KH_CAPTURE folder where <KH_MOCK>.png is written
//
// Run through tests/mockups/run.js.
ShellRoot {
    Window {
        id: win

        // The real panel width the picker is drawn at.
        width: 560
        height: 380
        visible: true
        color: Colors.background

        readonly property string scenario: Quickshell.env("KH_MOCK") || "B-default"
        readonly property bool optionB: win.scenario.charAt(0) === "B"
        readonly property string captureDir: Quickshell.env("KH_CAPTURE") || ""

        // ── The list behind the card: only context, dimmed by the scrim ──────
        Column {
            id: backdrop
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: Style.spacing.huge
            }

            Repeater {
                model: [
                    { badge: "Ch. 71", title: "Capítulo 71", date: "Apr 1, 2026" },
                    { badge: "Ch. 70", title: "Capítulo 70", date: "Mar 24, 2026" },
                    { badge: "Ch. 69", title: "Capítulo 69", date: "Mar 17, 2026" },
                    { badge: "Ch. 68", title: "Capítulo 68", date: "Mar 10, 2026" },
                    { badge: "Ch. 67", title: "Capítulo 67", date: "Mar 3, 2026" },
                    { badge: "Ch. 66.1", title: "Capítulo 66.1", date: "Apr 21, 2026" },
                    { badge: "Ch. 66", title: "Capítulo 66", date: "Apr 9, 2026" }
                ]

                delegate: Item {
                    id: backdropRow
                    required property var modelData
                    width: win.width
                    height: Style.space(46)

                    Rectangle {
                        x: Style.spacing.xxl
                        y: Style.spacing.md
                        width: Style.space(48)
                        height: Style.space(20)
                        radius: Style.cornerRadius
                        color: Colors.surface_container_high

                        StyledText {
                            anchors.centerIn: parent
                            text: backdropRow.modelData.badge
                            font.pixelSize: Style.font.caption
                            color: Colors.on_surface_variant
                        }
                    }

                    StyledText {
                        x: Style.space(72)
                        y: Style.spacing.md
                        text: backdropRow.modelData.title
                        font.pixelSize: Style.font.bodySmall
                        color: Colors.on_surface_variant
                        opacity: 0.55
                    }

                    StyledText {
                        x: Style.space(72)
                        y: Style.space(26)
                        text: backdropRow.modelData.date
                        font.pixelSize: Style.font.caption
                        color: Colors.on_surface_variant
                        opacity: 0.35
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(18)
                        y: Style.space(16)
                        text: "›"
                        font.pixelSize: Style.font.bodySmall
                        color: Colors.on_surface_variant
                        opacity: 0.4
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(42)
                        y: Style.space(16)
                        text: "↓"
                        font.pixelSize: Style.font.bodySmall
                        color: Colors.on_surface_variant
                        opacity: 0.4
                    }
                }
            }
        }

        // Same scrim the picker draws: background at 0.86.
        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha(Colors.background, 0.86)
        }

        Loader {
            anchors.centerIn: parent
            sourceComponent: win.optionB ? cardB : cardA
        }

        Component {
            id: cardB
            MockCardB {
                rowHovered: win.scenario === "B-hover-row"
                iconHovered: win.scenario === "B-hover-icon"
                tooltipVisible: win.scenario === "B-hover-icon"
            }
        }

        Component {
            id: cardA
            MockCardA {
                rowHovered: win.scenario === "A-hover-row"
                toggleOn: win.scenario === "A-on"
            }
        }

        Timer {
            interval: 800
            running: true
            onTriggered: {
                if (win.captureDir === "") {
                    Qt.quit()
                    return
                }
                win.contentItem.grabToImage(function(result) {
                    const file = win.captureDir + "/" + win.scenario + ".png"
                    if (result.saveToFile(file))
                        console.log("CAPTURED " + file)
                    else
                        console.log("CAPTURE FAILED " + file)
                    Qt.quit()
                })
            }
        }
    }
}
