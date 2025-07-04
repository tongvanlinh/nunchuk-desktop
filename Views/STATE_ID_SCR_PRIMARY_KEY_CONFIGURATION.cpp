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
#include "STATE_ID_SCR_PRIMARY_KEY_CONFIGURATION.h"
#include "Models/AppModel.h"
#include "Signers/QSignerManagement.h"
#include "bridgeifaces.h"
#include "Servers/Draco.h"
#include "localization/STR_CPP.h"

void SCR_PRIMARY_KEY_CONFIGURATION_Entry(QVariant msg) {}

void SCR_PRIMARY_KEY_CONFIGURATION_Exit(QVariant msg) {}

void EVT_PRIMARY_KEY_SIGN_IN_REQUEST_HANDLER(QVariant msg) {
    timeoutHandler(200, [msg]() {
        QMap<QString, QVariant> maps = msg.toMap();
        QSignerManagement::instance()->updatePrimaryKeyData(maps);
        QSignerManagement::instance()->loginPrimaryKey();
    });
}

void EVT_PRIMARY_KEY_CONFIGURATION_FINISHED_HANDLER(QVariant msg) {
    DBG_INFO;
    timeoutHandler(200, []() {
        AppModel::instance()->showToast(0, STR_CPP_106, EWARNING::WarningType::SUCCESS_MSG);
        AppModel::instance()->setPrimaryKey(Draco::instance()->Uid());
    });
}

void EVT_PRIMARY_KEY_SIGN_IN_SUCCEED_HANDLER(QVariant msg) {
    timeoutHandler(200, []() {
        QSignerManagement::instance()->loginPrimaryKeySuccess();
    });
}
