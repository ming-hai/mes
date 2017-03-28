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
package com.qcadoo.mes.technologies;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import com.google.common.base.Optional;
import com.qcadoo.mes.technologies.constants.BarcodeOperationComponentFields;
import com.qcadoo.mes.technologies.constants.TechnologiesConstants;
import com.qcadoo.model.api.DataDefinition;
import com.qcadoo.model.api.DataDefinitionService;
import com.qcadoo.model.api.Entity;
import com.qcadoo.model.api.search.SearchRestrictions;

import java.util.Collections;

@Service
public class BarcodeOperationComponentService {

    @Autowired
    private DataDefinitionService dataDefinitionService;

    @Autowired
    private NamedParameterJdbcTemplate jdbcTemplate;

    public void createBarcodeOperationComponent(Entity order, final Entity operationComponent) {

        if (!checkIfBarcodeForOperationComponentExist(operationComponent)) {
            Entity barcodeOCEntity = getBarcodeOperationComponentDD().create();
            barcodeOCEntity.setField(BarcodeOperationComponentFields.OPERATION_COMPONENT, operationComponent);
            barcodeOCEntity.setField("order", order);
            Long number = jdbcTemplate.queryForObject("select nextval('technologies_barcodeoperationcomponent_number_seq')",
                    Collections.emptyMap(), Long.class);
            barcodeOCEntity.setField(BarcodeOperationComponentFields.CODE, number.toString());
            barcodeOCEntity.getDataDefinition().save(barcodeOCEntity);
        }
    }

    private boolean checkIfBarcodeForOperationComponentExist(Entity operationComponent) {
        if (getBarcodeOperationComponentDD().find()
                .add(SearchRestrictions.belongsTo(BarcodeOperationComponentFields.OPERATION_COMPONENT, operationComponent)).list()
                .getEntities().isEmpty()) {
            return false;
        }
        return true;
    }

    private DataDefinition getBarcodeOperationComponentDD() {
        return dataDefinitionService.get(TechnologiesConstants.PLUGIN_IDENTIFIER,
                TechnologiesConstants.MODEL_BARCODE_OPERATION_COMPONENT);
    }

    public String getCodeFromBarcodeForOperationComponet(final Entity operationComponent) {
        Entity barcode = getBarcodeOperationComponentDD().find()
                .add(SearchRestrictions.belongsTo(BarcodeOperationComponentFields.OPERATION_COMPONENT, operationComponent))
                .setMaxResults(1).uniqueResult();
        return barcode.getStringField(BarcodeOperationComponentFields.CODE);
    }

    public Optional<Entity> getOperationComponetForBarcode(final String code) {
        Entity barcode = getBarcodeOperationComponentDD().find()
                .add(SearchRestrictions.eq(BarcodeOperationComponentFields.CODE, code)).setMaxResults(1).uniqueResult();
        if (barcode == null) {
            return Optional.absent();
        }
        return Optional.fromNullable(barcode.getBelongsToField(BarcodeOperationComponentFields.OPERATION_COMPONENT));
    }
}
