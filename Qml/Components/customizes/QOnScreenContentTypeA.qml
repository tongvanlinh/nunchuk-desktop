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
import "../customizes"
import "../customizes/Texts"
import "../customizes/Buttons"
import "../../../localization/STR_QML.js" as STR

QOnScreenContent {
    signal nextClicked()
    signal prevClicked()
    property bool nextEnable: true
    bottomLeft: QButtonTextLink {
        width: 97
        height: 48
        label: STR.STR_QML_059
        onButtonClicked: {
            prevClicked()
        }
    }
    bottomRight: QTextButton {
        width: label.paintedWidth + 16*2
        height: 48
        label.text: STR.STR_QML_265
        label.font.pixelSize: 16
        type: eTypeE
        enabled: nextEnable
        onButtonClicked: {
            nextClicked()
        }
    }
}
