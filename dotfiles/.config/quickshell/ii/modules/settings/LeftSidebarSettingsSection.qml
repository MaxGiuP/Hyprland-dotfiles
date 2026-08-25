import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "left_panel_open"
    title: Translation.tr("Left sidebar")

    ConfigSwitch {
        buttonIcon: "translate"
        text: Translation.tr('Enable translator')
        checked: Config.options.sidebar.translator.enable
        onCheckedChanged: {
            Config.options.sidebar.translator.enable = checked;
        }
    }

    ContentSubsection {
        title: Translation.tr("Corner open")
        tooltip: Translation.tr("Allows you to open sidebars by clicking or hovering screen corners regardless of bar position")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.sidebar.cornerOpen.enable
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.enable = checked;
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "highlight_mouse_cursor"
            text: Translation.tr("Hover to trigger")
            checked: Config.options.sidebar.cornerOpen.clickless
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.clickless = checked;
            }

            StyledToolTip {
                text: Translation.tr("When this is off you'll have to click")
            }
        }

        Row {
            ConfigSwitch {
                enabled: !Config.options.sidebar.cornerOpen.clickless
                text: Translation.tr("Force hover open at absolute corner")
                checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked;
                }

                StyledToolTip {
                    text: Translation.tr("When the previous option is off and this is on,\nyou can still hover the corner's end to open sidebar,\nand the remaining area can be used for volume/brightness scroll")
                }
            }

            ConfigSpinBox {
                icon: "arrow_cool_down"
                text: Translation.tr("with vertical offset")
                value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                from: 0
                to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value;
            }
        }
    }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "vertical_align_bottom"
                text: Translation.tr("Place at bottom")
                checked: Config.options.sidebar.cornerOpen.bottom
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.bottom = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Place the corners to trigger at the bottom")
                }
            }
            ConfigSwitch {
                buttonIcon: "unfold_more_double"
                text: Translation.tr("Value scroll")
                checked: Config.options.sidebar.cornerOpen.valueScroll
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.valueScroll = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Brightness and volume")
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Visualize region")
            checked: Config.options.sidebar.cornerOpen.visualize
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.visualize = checked;
            }
        }

        ConfigRow {
            ConfigSpinBox {
                icon: "arrow_range"
                text: Translation.tr("Region width")
                value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                from: 1
                to: 300
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.cornerOpen.cornerRegionWidth = value;
                }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Region height")
                value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                from: 1
                to: 300
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.cornerOpen.cornerRegionHeight = value;
                }
            }
        }
    }
}
