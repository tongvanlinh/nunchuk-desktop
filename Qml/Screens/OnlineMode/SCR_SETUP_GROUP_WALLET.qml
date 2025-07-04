/**************************************************************************
 * This file is part of the Nunchuk software (https://nunchuk.io/)        *
 * Copyright (C) 2020-2022 Enigmo								          *
 * Copyright (C) 2022 Nunchuk								              *
 *                                                                        *
 * This program is free software; you can redistribute it and/or          *
 * modify it under the terms of the GNU General Public License            *
 * as published by the Free Software Foundation; either version 3         *
 * of the License, or (at your option) any later version.                 *
 *                                                                        *
 * This program is distributed in the hope that it will be useful,        *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of         *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          *
 * GNU General Public License for more details.                           *
 *                                                                        *
 * You should have received a copy of the GNU General Public License      *
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.  *
 *                                                                        *
 **************************************************************************/
import QtQuick 2.4
import QtQuick.Controls 2.3
import QtGraphicalEffects 1.12
import HMIEVENTS 1.0
import EWARNING 1.0
import NUNCHUCKTYPE 1.0
import DataPool 1.0
import "../../Components/origins"
import "../../Components/customizes"
import "../../Components/customizes/Chats"
import "../../Components/customizes/Texts"
import "../../Components/customizes/Buttons"
import "../../Components/customizes/Signers"
import "../../Components/customizes/Wallets"
import "../../Components/customizes/Popups"
import "../../../localization/STR_QML.js" as STR

QScreen {
    property var newWalletInfo  : AppModel.newWalletInfo
    property var sandbox        : AppModel.newWalletInfo.sandbox
    property string flow_screen: sandbox.screenFlow
    readonly property var map_flow: [
        {screen: "setup-group-wallet",        screen_component: setup_group_Wallet},
        {screen: "review-wallet",             screen_component: review_wallet},
        {screen: "bsms-file-success",         screen_component: bsms_file_success},
        {screen: "register-wallet-hardware",  screen_component: register_wallet_hardware},
        {screen: "group-sandbox-setting",     screen_component: group_sandbox_setting},
        {screen: "sandbox-add-existing-key",  screen_component: group_sandbox_add_existing_key},
        {screen: "sandbox-intro-taproot",     screen_component: introTaproot},
        {screen: "sandbox-taproot-warning",   screen_component: taprootWarning},
        {screen: "sandbox-configure-value-keyset",   screen_component: configure_value_keyset},
        {screen: "value-keyset",              screen_component: valueKeyset},
    ]

    Loader {
        width: popupWidth
        height: popupHeight
        anchors.centerIn: parent
        sourceComponent: map_flow.find(function(e) {if (e.screen === flow_screen) return true; else return false}).screen_component
    }
    Component {
        id: setup_group_Wallet
        QSetupGroupWallet {

        }
    }
    Component {
        id: review_wallet
        QDraftWalletReviewWallet {
            onPrevClicked: sandbox.backScreen()
            onNextClicked: {
                var _input = {
                    type: "finalize-group-sandbox"
                }
                QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
            }
        }
    }
    Component {
        id: bsms_file_success
        QSaveYourWalletBSMSFile {
            onNextClicked: {
                var _input = {
                    type: "register-wallet-on-hardware"
                }
                QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
            }
        }
    }
    Component {
        id: register_wallet_hardware
        QRegisterWalletOnHardware {

        }
    }
    Component {
        id : group_sandbox_setting
        QGroupSandboxSetting {

        }
    }
    Component {
        id : group_sandbox_add_existing_key
        QSandboxAddAnExistingKey {

        }
    }
    Component {
        id : introTaproot
        QIntroductionTaprootAddress {
            onCloseClicked: closeTo(NUNCHUCKTYPE.CURRENT_TAB)
            onPrevClicked: sandbox.backScreen()
            onNextClicked: {
                var _input = {
                    type: "switch-to-taproot-warning-support"
                }
                QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
            }
        }
    }
    Component {
        id : taprootWarning
        QTaprootWarningSupport {
            onCloseClicked: closeTo(NUNCHUCKTYPE.CURRENT_TAB)
            onPrevClicked: sandbox.backScreen()
            onNextClicked: {
                var _input = {
                    type: "switch-to-enable-value-keyset"
                }
                QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
            }
        }
    }
    Component {
        id : valueKeyset
        QEnableValueKeyset {
            onCloseClicked: closeTo(NUNCHUCKTYPE.CURRENT_TAB)
            onPrevClicked: sandbox.backScreen()
            onNextClicked: {
                var _input = {}
                if (enableValueKeyset === "enable-value-keyset") {
                    newWalletInfo.enableValuekeyset = true
                    _input = {
                        type: "switch-to-configure-value-keyset"
                    }
                    QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
                }
                else {
                    newWalletInfo.enableValuekeyset = false
                    _input = {
                        type: "review-group-sandbox"
                    }
                    QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
                }
            }
        }
    }
    Component {
        id: configure_value_keyset
        QConfigureValueKeyset {
            onCloseClicked: closeTo(NUNCHUCKTYPE.CURRENT_TAB)
            onPrevClicked: sandbox.backScreen()
            onNextClicked: {
                var _input = {
                    type: "review-group-sandbox"
                }
                QMLHandle.sendEvent(EVT.EVT_SETUP_GROUP_WALLET_ENTER, _input)
            }
        }
    }

    Connections {
        target: sandbox
        onRecoverKeyError: {
            _error.open()
        }
    }

    QPopupInfo {
        id:_error
        title: STR.STR_QML_1668
        contentText: STR.STR_QML_1669
    }

    QPopupInfo {
        id:_waiting_for_other
        title: STR.STR_QML_1671
        contentText: STR.STR_QML_1672
        btnLabel: STR.STR_QML_596
    }
}
