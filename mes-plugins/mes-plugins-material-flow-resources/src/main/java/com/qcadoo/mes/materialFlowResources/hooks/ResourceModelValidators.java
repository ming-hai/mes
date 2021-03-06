/**
 * ***************************************************************************
 * Copyright (c) 2010 Qcadoo Limited
 * Project: Qcadoo MES
 * Version: 1.4
 *
 * This file is part of Qcadoo.
 *
 * Qcadoo is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation; either version 3 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty
 * of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 * ***************************************************************************
 */
package com.qcadoo.mes.materialFlowResources.hooks;

import static com.qcadoo.mes.materialFlow.constants.LocationFields.TYPE;
import com.qcadoo.mes.materialFlowResources.PalletValidatorService;
import static com.qcadoo.mes.materialFlowResources.constants.ResourceFields.LOCATION;

import org.springframework.stereotype.Service;

import com.qcadoo.model.api.DataDefinition;
import com.qcadoo.model.api.Entity;
import org.springframework.beans.factory.annotation.Autowired;

@Service
public class ResourceModelValidators {
    
    public boolean validatesWith(final DataDefinition resourceDD, final Entity resource) {
        return checkIfLocationIsWarehouse(resourceDD, resource) && checkQuantities(resourceDD, resource) && checkPallet(resourceDD, resource);
    }
    
    public boolean checkIfLocationIsWarehouse(final DataDefinition resourceDD, final Entity resource) {
        Entity location = resource.getBelongsToField(LOCATION);

        if (location != null) {
            String type = location.getStringField(TYPE);

            if (!"02warehouse".equals(type)) {
                resource.addError(resourceDD.getField(LOCATION),
                        "materialFlowResources.validate.global.error.locationIsNotWarehouse");

                return false;
            }
        }

        return true;
    }

    public boolean checkQuantities(final DataDefinition resourceDD, final Entity resource) {
        // BigDecimal quantity = resource.getDecimalField(ResourceFields.QUANTITY);
        // BigDecimal reservedQuantity = resource.getDecimalField(ResourceFields.RESERVED_QUANTITY);
        // BigDecimal availableQuantity = resource.getDecimalField(ResourceFields.AVAILABLE_QUANTITY);
        // if (quantity == null || reservedQuantity == null || availableQuantity == null) {
        // resource.addGlobalError("materialFlow.error.correction.invalidQuantity");
        // return false;
        // }
        // if (availableQuantity.compareTo(quantity.subtract(reservedQuantity)) != 0) {
        // resource.addGlobalError("materialFlow.error.correction.invalidQuantity");
        // return false;
        // }
        return true;
    }
    
    @Autowired
    private PalletValidatorService palletValidatorService;

    private boolean checkPallet(DataDefinition resourceDD, Entity resource) {
        return palletValidatorService.validatePalletForResource(resource);
    }

}
