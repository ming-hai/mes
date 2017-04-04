--
-- ***************************************************************************
-- Copyright (c) 2010 Qcadoo Limited
-- Project: Qcadoo MES
-- Version: 1.4
--
-- This file is part of Qcadoo.
--
-- Qcadoo is free software; you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation; either version 3 of the License,
-- or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty
-- of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
-- See the GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
-- ***************************************************************************
--

-- This script is invoked when application starts with hbm2ddlAuto = create.

-- Qcadoo-model & Hibernate will automatically generate regular db table due to existence of warehouseStock.xml model,
-- we need to first drop this table, before create table view.

CREATE OR REPLACE FUNCTION drop_all_sequence() RETURNS VOID AS $$ DECLARE ROW record; BEGIN FOR ROW IN SELECT tablename, SUBSTRING(quote_ident(tablename) || '_id_seq' FROM 1 FOR 63) AS seq_name FROM pg_tables p INNER JOIN information_schema.columns c ON p.tablename = c.table_name WHERE c.table_schema = 'public' AND p.schemaname = 'public' AND c.column_name = 'id' AND data_type = 'bigint' LOOP EXECUTE 'ALTER TABLE ' || quote_ident(ROW.tablename) || ' ALTER COLUMN id DROP DEFAULT;';  END LOOP; FOR ROW IN (SELECT c.relname FROM pg_class c WHERE c.relkind = 'S') LOOP EXECUTE 'DROP SEQUENCE ' || row.relname || ';'; END LOOP; END; $$ LANGUAGE 'plpgsql'; 

SELECT * FROM drop_all_sequence();

DROP FUNCTION drop_all_sequence();


CREATE OR REPLACE FUNCTION update_sequence() RETURNS VOID AS $$ DECLARE ROW record; BEGIN FOR ROW IN SELECT tablename, SUBSTRING(quote_ident(tablename) || '_id_seq' FROM 1 FOR 63) AS seq_name FROM pg_tables p INNER JOIN information_schema.columns c ON p.tablename = c.table_name WHERE c.table_schema = 'public' AND p.schemaname = 'public' AND c.column_name = 'id' AND data_type = 'bigint' LOOP EXECUTE 'CREATE SEQUENCE ' || ROW.seq_name; EXECUTE 'ALTER TABLE ' || quote_ident(ROW.tablename) || ' ALTER COLUMN id SET DEFAULT nextval('''|| ROW.seq_name||''');';  EXECUTE 'SELECT setval(''' || ROW.seq_name || ''', COALESCE((SELECT MAX(id)+1 FROM ' || quote_ident(ROW.tablename) || '), 1), false);';  END LOOP; END; $$ LANGUAGE 'plpgsql';

SELECT * FROM update_sequence();

DROP FUNCTION update_sequence();


DROP TABLE IF EXISTS materialflowresources_warehousestock;

CREATE OR REPLACE FUNCTION create_warehouse_stock_view() RETURNS VOID AS $$ BEGIN IF EXISTS (SELECT * FROM information_schema.columns WHERE table_name = 'basic_parameter' AND column_name = 'tenantid') THEN CREATE OR REPLACE VIEW materialflowresources_warehousestock AS SELECT row_number() OVER () AS id, location_id, product_id, (SELECT SUM(warehouseminimalstate_warehouseminimumstate.minimumstate) FROM warehouseminimalstate_warehouseminimumstate WHERE warehouseminimalstate_warehouseminimumstate.product_id = materialflowresources_resource.product_id AND warehouseminimalstate_warehouseminimumstate.location_id = materialflowresources_resource.location_id) AS minimumstate, (SELECT COALESCE(SUM(deliveries_orderedproduct.orderedquantity), 0::numeric) AS sum FROM deliveries_orderedproduct, deliveries_delivery WHERE deliveries_orderedproduct.delivery_id = deliveries_delivery.id AND deliveries_delivery.location_id = materialflowresources_resource.location_id AND deliveries_delivery.active = true AND deliveries_orderedproduct.product_id = materialflowresources_resource.product_id AND deliveries_delivery.state IN ('01draft', '02prepared', '03duringCorrection', '05approved')) AS orderedquantity, SUM(quantity) AS quantity, tenantid FROM materialflowresources_resource GROUP BY tenantid, location_id, product_id; ELSE CREATE OR REPLACE VIEW materialflowresources_warehousestock AS SELECT row_number() OVER () AS id, location_id, product_id, (SELECT SUM(warehouseminimalstate_warehouseminimumstate.minimumstate) FROM warehouseminimalstate_warehouseminimumstate WHERE warehouseminimalstate_warehouseminimumstate.product_id = materialflowresources_resource.product_id AND warehouseminimalstate_warehouseminimumstate.location_id = materialflowresources_resource.location_id) AS minimumstate, (SELECT COALESCE(SUM(deliveries_orderedproduct.orderedquantity),0) AS sum FROM deliveries_orderedproduct, deliveries_delivery WHERE deliveries_orderedproduct.delivery_id = deliveries_delivery.id AND deliveries_delivery.active = true AND deliveries_delivery.location_id = materialflowresources_resource.location_id AND deliveries_orderedproduct.product_id = materialflowresources_resource.product_id AND deliveries_delivery.state IN ('01draft', '02prepared', '03duringCorrection', '05approved')) AS orderedquantity, SUM(quantity) AS quantity FROM materialflowresources_resource GROUP BY location_id, product_id; END IF; END; $$ LANGUAGE 'plpgsql';

SELECT create_warehouse_stock_view();

DROP FUNCTION create_warehouse_stock_view();


-- optymalizacja QCADOOCLS-4315

DROP TABLE IF EXISTS materialflowresources_warehousestocklistdto;

CREATE OR REPLACE VIEW materialflowresources_orderedquantity AS SELECT COALESCE(SUM(orderedproduct.orderedquantity), 0::numeric) AS orderedquantity, resource.id AS resource_id FROM materialflowresources_resource resource JOIN deliveries_orderedproduct orderedproduct ON (orderedproduct.product_id = resource.product_id) JOIN deliveries_delivery delivery ON (orderedproduct.delivery_id = delivery.id AND delivery.active = true AND delivery.location_id = resource.location_id AND (delivery.state::text = ANY (ARRAY['01draft'::character varying::text, '02prepared'::character varying::text, '03duringCorrection'::character varying::text, '05approved'::character varying::text]))) GROUP BY resource.id;

CREATE OR REPLACE VIEW materialflowresources_warehousestocklistdto_internal AS SELECT row_number() OVER () AS id, resource.location_id, resource.product_id::integer, SUM(resource.quantity) AS quantity, COALESCE(orderedquantity.orderedquantity, 0::numeric) AS orderedquantity, (SELECT SUM(warehouseminimalstate_warehouseminimumstate.minimumstate) AS sum FROM warehouseminimalstate_warehouseminimumstate WHERE warehouseminimalstate_warehouseminimumstate.product_id = resource.product_id AND warehouseminimalstate_warehouseminimumstate.location_id = resource.location_id) AS minimumstate FROM materialflowresources_resource resource LEFT JOIN materialflowresources_orderedquantity orderedquantity ON (orderedquantity.resource_id = resource.id) GROUP BY resource.location_id, resource.product_id, orderedquantity.orderedquantity;

CREATE OR REPLACE VIEW materialflowresources_warehousestocklistdto AS SELECT internal.*, location.number AS locationNumber, location.name AS locationName, product.number AS productNumber, product.name AS productName, product.unit AS productUnit FROM materialflowresources_warehousestocklistdto_internal internal JOIN materialflow_location location ON (location.id = internal.location_id) JOIN basic_product product ON (product.id = internal.product_id);

-- end


DROP TABLE IF EXISTS ordersupplies_materialrequirementcoveragedto;

CREATE OR REPLACE VIEW ordersupplies_materialrequirementcoveragedto AS SELECT id, number, coveragetodate, actualdate, generateddate, generatedby FROM ordersupplies_materialrequirementcoverage WHERE saved = true;

DROP TABLE IF EXISTS jointable_coverageorderhelper_orderdto;

DROP TABLE IF EXISTS ordersupplies_orderdto;

CREATE OR REPLACE VIEW ordersupplies_orderdto AS SELECT id, number, name, state FROM orders_order;

CREATE TABLE jointable_coverageorderhelper_orderdto (coverageorderhelper_id bigint NOT NULL, orderdto_id bigint NOT NULL, CONSTRAINT jointable_coverageorderhelper_orderdto_pkey PRIMARY KEY (coverageorderhelper_id, orderdto_id), CONSTRAINT jointable_coverageorderhelper_coverageorderhelper_fkey FOREIGN KEY (coverageorderhelper_id) REFERENCES ordersupplies_coverageorderhelper (id) DEFERRABLE);

---


DROP TABLE IF EXISTS orders_orderplanninglistdto;

CREATE OR REPLACE VIEW public.orders_orderplanninglistdto AS SELECT ordersorder.id, ordersorder.active, ordersorder.number, ordersorder.name, ordersorder.datefrom, ordersorder.dateto, ordersorder.startdate, ordersorder.finishdate, ordersorder.state, ordersorder.externalnumber, ordersorder.externalsynchronized, ordersorder.issubcontracted, ordersorder.plannedquantity, ordersorder.workplandelivered, ordersorder.ordercategory, COALESCE(ordersorder.amountofproductproduced, 0::numeric) AS amountofproductproduced, COALESCE(ordersorder.wastesquantity, 0::numeric) AS wastesquantity, COALESCE(ordersorder.remainingamountofproducttoproduce, 0::numeric) AS remainingamountofproducttoproduce, product.number AS productnumber, technology.number AS technologynumber, product.unit, productionline.number AS productionlinenumber, masterorder.number AS masterordernumber, division.name AS divisionname, division.number AS divisionnumber, COALESCE(ordersorder.plannedquantityforadditionalunit, ordersorder.plannedquantity) AS plannedquantityforadditionalunit, COALESCE(product.additionalunit, product.unit) AS unitforadditionalunit, company.number AS company FROM orders_order ordersorder JOIN basic_product product ON product.id = ordersorder.product_id LEFT JOIN technologies_technology technology ON technology.id = ordersorder.technology_id LEFT JOIN productionlines_productionline productionline ON productionline.id = ordersorder.productionline_id LEFT JOIN masterorders_masterorder masterorder ON masterorder.id = ordersorder.masterorder_id LEFT JOIN basic_division division ON division.id = technology.division_id LEFT JOIN basic_company company ON company.id = ordersorder.company_id;
-- end


-- subassemblies view

DROP TABLE IF EXISTS basic_subassemblylistdto;

CREATE OR REPLACE VIEW basic_subassemblyListDto AS SELECT s.id, s.active, s.number, s.name, workstation.number AS workstationNumber, s.type, workstationType.number AS workstationTypeNumber, DATE(s.productionDate) AS productionDate, DATE(event.maxDate) AS lastRepairsDate FROM basic_subassembly s LEFT JOIN basic_workstation workstation ON (s.workstation_id = workstation.id) JOIN basic_workstationType workstationType ON (s.workstationtype_id = workstationType.id) LEFT JOIN (SELECT subassembly_id AS subassemblyId, MAX(date) AS maxDate FROM cmmsmachineparts_plannedevent e WHERE e.state = '05realized' AND e.basedon = '01date' AND e.type = '02repairs' GROUP BY subassemblyId) event ON event.subassemblyId = s.id;

-- end


-- pallet terminal

DROP TABLE IF EXISTS goodfood_palletdto;

CREATE OR REPLACE VIEW goodfood_palletdto AS SELECT pallet.id AS id, staff.name AS palletContextOperatorName, staff.surname AS palletContextOperatorSurname, productionline.number AS productionLineNumber, masterorder.number AS masterOrderNumber, product.number AS productNumber, pallet.registrationDate AS registrationDate, pallet.sendDate AS sendDate, palletcontext.day AS palletContextDay, pallet.state AS state, pallet.ssccNumber AS ssccNumber, secondPallet.palletNumber AS secondPalletNumber, pallet.lastStateChangeFails AS lastStateChangeFails, pallet.active AS active, pallet.palletNumber AS palletNumber FROM goodfood_pallet pallet LEFT JOIN goodfood_palletcontext palletcontext ON pallet.palletcontext_id = palletcontext.id LEFT JOIN basic_staff staff ON palletcontext.operator_id = staff.id LEFT JOIN goodfood_label label ON pallet.label_id = label.id LEFT JOIN productionlines_productionline productionline ON label.productionline_id = productionline.id LEFT JOIN masterorders_masterorder masterorder ON label.masterorder_id = masterorder.id LEFT JOIN basic_product product ON masterorder.product_id = product.id LEFT JOIN goodfood_pallet secondPallet ON pallet.secondpallet_id = secondPallet.id;


DROP TABLE IF EXISTS goodfood_labeldto;

CREATE OR REPLACE VIEW goodfood_labeldto AS SELECT label.id AS id, staff.name AS palletContextOperatorName, staff.surname AS palletContextOperatorSurname, productionline.number AS productionLineNumber, masterorder.number AS masterOrderNumber, product.number AS productNumber, label.registrationDate AS registrationDate, label.state AS state, label.lastSsccNumber AS lastSsccNumber, label.active AS active FROM goodfood_label label LEFT JOIN goodfood_palletcontext palletcontext ON label.palletcontext_id = palletcontext.id LEFT JOIN basic_staff staff ON palletcontext.operator_id = staff.id LEFT JOIN productionlines_productionline productionline ON label.productionline_id = productionline.id LEFT JOIN masterorders_masterorder masterorder ON label.masterorder_id = masterorder.id LEFT JOIN basic_product product ON masterorder.product_id = product.id;

-- end


-- events views

DROP TABLE IF EXISTS cmmsmachineparts_plannedeventlistdto;

CREATE OR REPLACE VIEW cmmsmachineparts_plannedeventlistdto AS SELECT plannedevent.id AS id, plannedevent.number AS number, plannedevent.type AS type, plannedevent.description AS description, plannedevent.date::TIMESTAMP WITHOUT TIME ZONE AS date, plannedevent.counter AS counter, plannedevent.createUser AS createuser, plannedevent.createDate AS createdate, plannedevent.state AS state, context.id AS plannedeventcontext_id, sourcecost.id AS sourcecost_id, staff.name || ' ' || staff.surname AS ownername, factory.id::integer AS factory_id, factory.number AS factorynumber, division.id::integer AS division_id, division.number AS divisionnumber, workstation.id::integer AS workstation_id, workstation.number AS workstationnumber, subassembly.id::integer AS subassembly_id, subassembly.number AS subassemblynumber, company.id::integer AS company_id, productionline.number AS productionlinenumber FROM cmmsmachineparts_plannedevent plannedevent LEFT JOIN cmmsmachineparts_plannedeventcontext context ON plannedevent.plannedeventcontext_id = context.id LEFT JOIN cmmsmachineparts_sourcecost sourcecost ON plannedevent.sourcecost_id = sourcecost.id LEFT JOIN basic_staff staff ON plannedevent.owner_id = staff.id LEFT JOIN basic_factory factory ON plannedevent.factory_id = factory.id LEFT JOIN basic_division division ON plannedevent.division_id = division.id LEFT JOIN basic_workstation workstation ON plannedevent.workstation_id = workstation.id LEFT JOIN basic_subassembly subassembly ON plannedevent.subassembly_id = subassembly.id LEFT JOIN basic_company company ON plannedevent.company_id = company.id LEFT JOIN productionlines_productionline productionline ON plannedevent.productionline_id = productionline.id;


DROP TABLE IF EXISTS cmmsmachineparts_maintenanceeventlistdto;

CREATE OR REPLACE VIEW cmmsmachineparts_maintenanceeventlistdto AS SELECT maintenanceevent.id AS id, maintenanceevent.number AS number, maintenanceevent.type AS type, maintenanceevent.createuser AS createuser, maintenanceevent.createdate AS createdate, maintenanceevent.state AS state, maintenanceevent.description AS description, context.id AS maintenanceeventcontext_id, staff.name || ' ' || staff.surname AS personreceivingname, factory.id::integer AS factory_id, factory.number AS factorynumber, division.id::integer AS division_id, division.number AS divisionnumber, workstation.number AS workstationnumber, subassembly.number AS subassemblynumber, faultType.name AS faulttypename, productionline.number AS productionlinenumber FROM cmmsmachineparts_maintenanceevent maintenanceevent LEFT JOIN cmmsmachineparts_maintenanceeventcontext context ON maintenanceevent.maintenanceeventcontext_id = context.id LEFT JOIN basic_staff staff ON maintenanceevent.personreceiving_id = staff.id LEFT JOIN basic_factory factory ON maintenanceevent.factory_id = factory.id LEFT JOIN basic_division division ON maintenanceevent.division_id = division.id LEFT JOIN basic_workstation workstation ON maintenanceevent.workstation_id = workstation.id LEFT JOIN basic_subassembly subassembly ON maintenanceevent.subassembly_id = subassembly.id LEFT JOIN basic_faulttype faultType ON maintenanceevent.faulttype_id = faultType.id LEFT JOIN productionlines_productionline productionline ON maintenanceevent.productionline_id = productionline.id;

-- end


ALTER TABLE repairs_repairorder DROP COLUMN productiontracking_id;


-- production tracking

DROP TABLE IF EXISTS productioncounting_trackingoperationproductincomponentdto;

CREATE OR REPLACE VIEW productioncounting_trackingoperationproductincomponentdto AS SELECT trackingoperationproductincomponent.id AS id, productiontracking.id::integer AS productiontracking_id, product.id::integer AS product_id, product.number AS productnumber, product.unit AS productunit, CASE WHEN productiontracking.technologyoperationcomponent_id IS NULL THEN (SELECT SUM(productioncountingquantity_1.plannedquantity) AS sum) ELSE (SELECT SUM(productioncountingquantity_2.plannedquantity) AS sum) END AS plannedquantity, trackingoperationproductincomponent.usedquantity AS usedquantity, batch.number AS batchnumber FROM productioncounting_trackingoperationproductincomponent trackingoperationproductincomponent LEFT JOIN productioncounting_productiontracking productiontracking ON productiontracking.id = trackingoperationproductincomponent.productiontracking_id LEFT JOIN basic_product product ON product.id = trackingoperationproductincomponent.product_id LEFT JOIN advancedgenealogy_batch batch ON batch.id = trackingoperationproductincomponent.batch_id LEFT JOIN basicproductioncounting_productioncountingquantity productioncountingquantity_1 ON (productioncountingquantity_1.order_id = productiontracking.order_id AND productioncountingquantity_1.product_id = trackingoperationproductincomponent.product_id AND productioncountingquantity_1.role::text = '01used'::text) LEFT JOIN basicproductioncounting_productioncountingquantity productioncountingquantity_2 ON (productioncountingquantity_2.order_id = productiontracking.order_id AND productioncountingquantity_2.technologyoperationcomponent_id = productiontracking.technologyoperationcomponent_id AND productioncountingquantity_2.product_id = trackingoperationproductincomponent.product_id AND productioncountingquantity_2.role::text = '01used'::text) WHERE productiontracking.state NOT IN ('03declined'::text,'04corrected'::text) GROUP BY trackingoperationproductincomponent.id, productiontracking.id, product.id, product.number, product.unit, trackingoperationproductincomponent.usedquantity, productiontracking.technologyoperationcomponent_id, batch.number;


DROP TABLE IF EXISTS productioncounting_trackingoperationproductoutcomponentdto;

CREATE OR REPLACE VIEW productioncounting_trackingoperationproductoutcomponentdto AS SELECT trackingoperationproductoutcomponent.id AS id, productiontracking.id::integer AS productiontracking_id, product.id::integer AS product_id, product.number AS productnumber, product.unit AS productunit, CASE WHEN productiontracking.technologyoperationcomponent_id IS NULL THEN (SELECT SUM(productioncountingquantity_1.plannedquantity) AS sum) ELSE (SELECT SUM(productioncountingquantity_2.plannedquantity) AS sum) END AS plannedquantity, trackingoperationproductoutcomponent.usedquantity AS usedquantity, batch.number AS batchnumber FROM productioncounting_trackingoperationproductoutcomponent trackingoperationproductoutcomponent LEFT JOIN productioncounting_productiontracking productiontracking ON productiontracking.id = trackingoperationproductoutcomponent.productiontracking_id LEFT JOIN basic_product product ON product.id = trackingoperationproductoutcomponent.product_id LEFT JOIN advancedgenealogy_batch batch ON batch.id = trackingoperationproductoutcomponent.batch_id LEFT JOIN basicproductioncounting_productioncountingquantity productioncountingquantity_1 ON (productioncountingquantity_1.order_id = productiontracking.order_id AND productioncountingquantity_1.product_id = trackingoperationproductoutcomponent.product_id AND productioncountingquantity_1.role::text = '02produced'::text) LEFT JOIN basicproductioncounting_productioncountingquantity productioncountingquantity_2 ON (productioncountingquantity_2.order_id = productiontracking.order_id AND productioncountingquantity_2.technologyoperationcomponent_id = productiontracking.technologyoperationcomponent_id AND productioncountingquantity_2.product_id = trackingoperationproductoutcomponent.product_id AND productioncountingquantity_2.role::text = '02produced'::text) WHERE productiontracking.state NOT IN ('03declined'::text,'04corrected'::text) GROUP BY trackingoperationproductoutcomponent.id, productiontracking.id, product.id, product.number, product.unit, trackingoperationproductoutcomponent.usedquantity, productiontracking.technologyoperationcomponent_id, batch.number;


DROP TABLE IF EXISTS productioncounting_trackingoperationproductcomponentdto;

CREATE OR REPLACE VIEW productioncounting_trackingoperationproductcomponentdto AS SELECT row_number() OVER () AS id, trackingoperationproductcomponentdto.productiontracking_id::integer AS productiontracking_id, trackingoperationproductcomponentdto.product_id::integer AS product_id, trackingoperationproductcomponentdto.productnumber AS productnumber, trackingoperationproductcomponentdto.productunit AS productunit, trackingoperationproductcomponentdto.plannedquantity AS plannedquantity, trackingoperationproductcomponentdto.usedquantity AS usedquantity, trackingoperationproductcomponentdto.batchnumber FROM (SELECT trackingoperationproductincomponentdto.productiontracking_id, trackingoperationproductincomponentdto.product_id, trackingoperationproductincomponentdto.productnumber, trackingoperationproductincomponentdto.productunit, trackingoperationproductincomponentdto.plannedquantity, trackingoperationproductincomponentdto.usedquantity, trackingoperationproductincomponentdto.batchnumber FROM productioncounting_trackingoperationproductincomponentdto trackingoperationproductincomponentdto UNION SELECT trackingoperationproductoutcomponentdto.productiontracking_id, trackingoperationproductoutcomponentdto.product_id, trackingoperationproductoutcomponentdto.productnumber, trackingoperationproductoutcomponentdto.productunit, trackingoperationproductoutcomponentdto.plannedquantity, trackingoperationproductoutcomponentdto.usedquantity, trackingoperationproductoutcomponentdto.batchnumber FROM productioncounting_trackingoperationproductoutcomponentdto trackingoperationproductoutcomponentdto) trackingoperationproductcomponentdto;

-- end


-- #QCADOO-432

CREATE OR REPLACE FUNCTION generate_and_set_resource_number(_time timestamp) RETURNS text AS $$ DECLARE _pattern text; _year numeric;_sequence_name text; _sequence_value numeric; _tmp text; _seq text; _number text; BEGIN _pattern := '#year/#seq'; _year := EXTRACT(year FROM _time);_sequence_name := 'materialflowresources_resource_number_' || _year; SELECT sequence_name INTO _tmp FROM information_schema.sequences WHERE sequence_schema = 'public' AND sequence_name = _sequence_name; IF _tmp IS NULL THEN EXECUTE 'CREATE SEQUENCE ' || _sequence_name || ';'; END IF; SELECT nextval(_sequence_name) INTO _sequence_value;_seq := to_char(_sequence_value, 'fm00000'); IF _seq LIKE '%#%' THEN _seq := _sequence_value; END IF; _number := _pattern;_number := REPLACE(_number, '#year', _year::text); _number := REPLACE(_number, '#seq', _seq); RETURN _number; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_resource_number_trigger() RETURNS trigger AS $$ BEGIN NEW.number := generate_and_set_resource_number(NEW.time); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER materialflowresources_resource_trigger_number BEFORE INSERT ON materialflowresources_resource FOR EACH ROW EXECUTE PROCEDURE generate_and_set_resource_number_trigger();

-- end #QCADOO-432


-- end #QCADOO-433

CREATE OR REPLACE FUNCTION generate_document_number(_translated_type text) RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _number text; BEGIN _pattern := '#translated_type/#seq'; _sequence_name := 'materialflowresources_document_number_' || LOWER(_translated_type); SELECT sequence_name INTO _tmp FROM information_schema.sequences WHERE sequence_schema = 'public' AND sequence_name = _sequence_name; IF _tmp IS NULL THEN EXECUTE 'CREATE SEQUENCE ' || _sequence_name || ';'; END IF; SELECT nextval(_sequence_name) INTO _sequence_value; _seq := to_char(_sequence_value, 'fm00000'); IF _seq LIKE '%#%' THEN _seq := _sequence_value; END IF; _number := _pattern; _number := REPLACE(_number, '#translated_type', _translated_type); _number := REPLACE(_number, '#seq', _seq); RETURN _number; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_document_number_trigger() RETURNS trigger AS $$ BEGIN NEW.number := generate_document_number(NEW.number); IF NEW.name IS NULL THEN NEW.name := NEW.number; END IF; RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER materialflowresources_document_trigger_number BEFORE INSERT ON materialflowresources_document FOR EACH ROW EXECUTE PROCEDURE generate_and_set_document_number_trigger();

-- end #QCADOO-433


-- #GOODFOOD-1196

CREATE SEQUENCE cmmsmachineparts_maintenanceevent_number_seq;

CREATE OR REPLACE FUNCTION generate_maintenanceevent_number() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _number text; BEGIN _pattern := '#seq'; SELECT nextval('cmmsmachineparts_maintenanceevent_number_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); IF _seq LIKE '%#%' THEN _seq := _sequence_value; END IF; _number := _pattern; _number := REPLACE(_number, '#seq', _seq); RETURN _number; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_maintenanceevent_number_trigger() RETURNS trigger AS $$ BEGIN NEW.number := generate_maintenanceevent_number(); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER cmmsmachineparts_maintenanceevent_trigger_number BEFORE INSERT ON cmmsmachineparts_maintenanceevent FOR EACH ROW EXECUTE PROCEDURE generate_and_set_maintenanceevent_number_trigger();

-- end #GOODFOOD-1196


-- VIEW: technologies_technologydto

DROP TABLE IF EXISTS technologies_technologydto;

CREATE OR REPLACE VIEW technologies_technologydto AS SELECT technology.id, technology.name, technology.number, technology.externalsynchronized, technology.master, technology.state, product.number AS productnumber, product.globaltypeofmaterial AS productglobaltypeofmaterial, tg.number AS technologygroupnumber, division.name AS divisionname, product.name AS productname, technology.technologytype, technology.active, technology.standardPerformanceTechnology, tcontext.number as generatorName FROM technologies_technology technology LEFT JOIN basic_product product ON technology.product_id = product.id LEFT JOIN basic_division division ON technology.division_id = division.id LEFT JOIN technologies_technologygroup tg ON technology.technologygroup_id = tg.id LEFT JOIN technologiesgenerator_generatortechnologiesforproduct tgenn ON technology.id = tgenn.technology_id LEFT JOIN technologiesgenerator_generatorcontext tcontext ON tcontext.id = tgenn.generatorcontext_id;

-- end


-- VIEW: orders_orderdto

ALTER TABLE productflowthrudivision_warehouseissue DROP COLUMN order_id;

ALTER TABLE repairs_repairorder DROP COLUMN order_id;

DROP TABLE IF EXISTS orders_orderdto;

CREATE OR REPLACE VIEW orders_orderdto AS SELECT id, active, number, name, state, typeofproductionrecording FROM orders_order;

ALTER TABLE productflowthrudivision_warehouseissue ADD COLUMN order_id bigint;
ALTER TABLE productflowthrudivision_warehouseissue ADD CONSTRAINT warehouseissue_order_fkey FOREIGN KEY (order_id) REFERENCES orders_order (id) DEFERRABLE;

ALTER TABLE repairs_repairorder ADD COLUMN order_id bigint;
ALTER TABLE repairs_repairorder ADD CONSTRAINT repairdorder_order_fkey FOREIGN KEY (order_id) REFERENCES orders_order (id) DEFERRABLE;

-- end


-- VIEW: productflowthrudivision_producttoissuedt

CREATE OR REPLACE VIEW productflowthrudivision_producttoissuedto_internal AS SELECT row_number() OVER () AS id, resource.location_id, resource.product_id::integer AS product_id, sum(resource.quantity) AS quantity FROM materialflowresources_resource resource GROUP BY resource.location_id, resource.product_id;

DROP TABLE IF EXISTS productflowthrudivision_producttoissuedto;

CREATE OR REPLACE VIEW productflowthrudivision_producttoissuedto AS SELECT producttoissue.id, issue.number AS issuenumber, locationfrom.number AS locationfromnumber, locationto.number AS locationtonumber, o.number AS ordernumber, issue.orderstartdate, issue.state, product.number AS productnumber, product.name AS productname, producttoissue.demandquantity, o.plannedquantity AS orderquantity, round(producttoissue.demandquantity / o.plannedquantity, 5) AS quantityperunit, producttoissue.conversion as conversion, product.additionalunit as unitAdditional, producttoissue.issuequantity AS issuedquantity, CASE WHEN (producttoissue.demandquantity - producttoissue.issuequantity) < 0::numeric THEN 0::numeric ELSE producttoissue.demandquantity - producttoissue.issuequantity END AS quantitytoissue, CASE WHEN (producttoissue.demandquantity - producttoissue.issuequantity) < 0::numeric THEN 0::numeric ELSE round((producttoissue.demandquantity - producttoissue.issuequantity) * producttoissue.conversion) END AS quantityToIssueInAddUnit, CASE WHEN locationfrom.externalnumber IS NULL AND warehousestockfrom.quantity IS NULL THEN 0::numeric WHEN locationfrom.externalnumber IS NULL AND warehousestockfrom.quantity IS NOT NULL THEN warehousestockfrom.quantity WHEN locationfrom.externalnumber IS NOT NULL AND warehousestockfromexternal.locationsquantity IS NULL THEN 0::numeric WHEN locationfrom.externalnumber IS NOT NULL AND warehousestockfromexternal.locationsquantity IS NOT NULL THEN warehousestockfromexternal.locationsquantity ELSE warehousestockfrom.quantity END AS quantityinlocationfrom, CASE WHEN locationfrom.externalnumber IS NULL AND warehousestockto.quantity IS NULL THEN 0::numeric WHEN locationfrom.externalnumber IS NULL AND warehousestockto.quantity IS NOT NULL THEN warehousestockto.quantity WHEN locationfrom.externalnumber IS NOT NULL AND warehousestocktoexternal.locationsquantity IS NULL THEN 0::numeric WHEN locationfrom.externalnumber IS NOT NULL AND warehousestocktoexternal.locationsquantity IS NOT NULL THEN warehousestocktoexternal.locationsquantity ELSE warehousestockfrom.quantity END AS quantityinlocationto, product.unit, CASE WHEN producttoissue.demandquantity <= producttoissue.issuequantity THEN true ELSE false END AS issued, product.id AS productid, additionalcode.code AS additionalcode, storagelocation.number AS storagelocationnumber FROM productflowthrudivision_productstoissue producttoissue LEFT JOIN productflowthrudivision_warehouseissue issue ON producttoissue.warehouseissue_id = issue.id LEFT JOIN materialflow_location locationfrom ON issue.placeofissue_id = locationfrom.id LEFT JOIN materialflow_location locationto ON producttoissue.location_id = locationto.id LEFT JOIN materialflowresources_storagelocation storagelocation ON producttoissue.storagelocation_id = storagelocation.id LEFT JOIN orders_order o ON issue.order_id = o.id LEFT JOIN basic_product product ON producttoissue.product_id = product.id LEFT JOIN basic_additionalcode additionalcode ON producttoissue.additionalcode_id = additionalcode.id LEFT JOIN productflowthrudivision_producttoissuedto_internal warehousestockfrom ON warehousestockfrom.product_id = producttoissue.product_id AND warehousestockfrom.location_id = locationfrom.id LEFT JOIN productflowthrudivision_producttoissuedto_internal warehousestockto ON warehousestockto.product_id = producttoissue.product_id AND warehousestockto.location_id = locationto.id LEFT JOIN productflowthrudivision_productandquantityhelper warehousestockfromexternal ON warehousestockfromexternal.product_id = producttoissue.product_id AND warehousestockfromexternal.location_id = locationfrom.id LEFT JOIN productflowthrudivision_productandquantityhelper warehousestocktoexternal ON warehousestocktoexternal.product_id = producttoissue.product_id AND warehousestocktoexternal.location_id = locationto.id WHERE issue.state::text = ANY (ARRAY['01draft'::character varying::text, '02inProgress'::character varying::text]);

-- end


-- VIEW: materialflowresources_documentdto

DROP TABLE IF EXISTS materialflowresources_documentdto;

CREATE OR REPLACE VIEW materialflowresources_documentdto AS SELECT document.inBuffer,document.id AS id, document.number AS number, document.description AS description, document.name AS name, document.type AS type, document.time AS time, document.state AS state, document.active AS active, locationfrom.id::integer AS locationfrom_id, locationfrom.name AS locationfromname, locationto.id::integer AS locationto_id, locationto.name AS locationtoname, company.id::integer AS company_id, company.name AS companyname, securityuser.id::integer AS user_id, securityuser.firstname || ' ' || securityuser.lastname AS username, maintenanceevent.id::integer AS maintenanceevent_id, maintenanceevent.number AS maintenanceeventnumber, plannedevent.id::integer AS plannedevent_id, plannedevent.number AS plannedeventnumber, delivery.id::integer AS delivery_id, delivery.number AS deliverynumber, ordersorder.id::integer AS order_id, ordersorder.number AS ordernumber, suborder.id::integer AS suborder_id, suborder.number AS subordernumber FROM materialflowresources_document document LEFT JOIN materialflow_location locationfrom ON locationfrom.id = document.locationfrom_id LEFT JOIN materialflow_location locationto ON locationto.id = document.locationto_id LEFT JOIN basic_company company ON company.id = document.company_id LEFT JOIN qcadoosecurity_user securityuser ON securityuser.id = document.user_id LEFT JOIN cmmsmachineparts_maintenanceevent maintenanceevent ON maintenanceevent.id = document.maintenanceevent_id LEFT JOIN cmmsmachineparts_plannedevent plannedevent ON plannedevent.id = document.plannedevent_id LEFT JOIN deliveries_delivery delivery ON delivery.id = document.delivery_id LEFT JOIN orders_order ordersorder ON ordersorder.id = document.order_id LEFT JOIN subcontractorportal_suborder suborder ON suborder.id = document.suborder_id;

-- end


-- VIEW: materialflowresource_resourcestock

DROP TABLE IF EXISTS materialflowresources_resourcestockdto;

CREATE OR REPLACE VIEW materialflowresources_orderedquantitystock AS SELECT COALESCE(SUM(orderedproduct.orderedquantity), 0::numeric) AS orderedquantity, resource.id AS resource_id FROM materialflowresources_resourcestock resource JOIN deliveries_orderedproduct orderedproduct ON (orderedproduct.product_id = resource.product_id) JOIN deliveries_delivery delivery ON (orderedproduct.delivery_id = delivery.id AND delivery.active = true AND delivery.location_id = resource.location_id AND (delivery.state::text = ANY (ARRAY['01draft'::character varying::text, '02prepared'::character varying::text, '03duringCorrection'::character varying::text, '05approved'::character varying::text]))) GROUP BY resource.id;

CREATE OR REPLACE VIEW materialflowresources_resourcestockdto_internal AS SELECT row_number() OVER () AS id, resource.location_id, resource.product_id::integer, resource.quantity AS quantity, COALESCE(orderedquantity.orderedquantity, 0::numeric) AS orderedquantity, (SELECT SUM(warehouseminimalstate_warehouseminimumstate.minimumstate) AS sum FROM warehouseminimalstate_warehouseminimumstate WHERE warehouseminimalstate_warehouseminimumstate.product_id = resource.product_id AND warehouseminimalstate_warehouseminimumstate.location_id = resource.location_id) AS minimumstate, reservedQuantity, availableQuantity FROM materialflowresources_resourcestock resource LEFT JOIN materialflowresources_orderedquantitystock orderedquantity ON (orderedquantity.resource_id = resource.id) GROUP BY resource.location_id, resource.product_id, orderedquantity.orderedquantity, reservedQuantity, availableQuantity, quantity;

CREATE OR REPLACE VIEW materialflowresources_resourcestockdto AS SELECT internal.*, location.number AS locationNumber, location.name AS locationName, product.number AS productNumber, product.name AS productName, product.unit AS productUnit FROM materialflowresources_resourcestockdto_internal internal JOIN materialflow_location location ON (location.id = internal.location_id) JOIN basic_product product ON (product.id = internal.product_id);

-- end


-- VIEW: repairs_repairorderdto

ALTER TABLE productioncounting_productiontracking DROP COLUMN repairorder_id;

ALTER TABLE repairs_repairorder ADD COLUMN productiontracking_id bigint;
ALTER TABLE repairs_repairorder ADD CONSTRAINT repairorder_productiontracking_fkey FOREIGN KEY (productiontracking_id) REFERENCES productioncounting_productiontracking (id) DEFERRABLE;

DROP TABLE IF EXISTS repairs_repairorderdto;

CREATE OR REPLACE VIEW repairs_repairorderdto AS SELECT repairorder.id AS id, repairorder.number AS number, repairorder.state AS state, repairorder.createdate AS createdate, repairorder.startdate AS startdate, repairorder.enddate AS enddate, repairorder.quantitytorepair AS quantitytorepair, repairorder.quantityrepaired AS quantityrepaired, repairorder.lack AS lack, repairorder.active AS active, orderdto.id::integer AS order_id, orderdto.number AS ordernumber, division.id::integer AS division_id, division.number AS divisionnumber, shift.id::integer AS shift_id, shift.name AS shiftname, product.id::integer AS product_id, product.number AS productnumber, product.name AS productname, product.unit AS productunit, productiontrackingdto.id::integer AS productiontracking_id, productiontrackingdto.number AS productiontrackingnumber FROM repairs_repairorder repairorder LEFT JOIN orders_orderdto orderdto ON orderdto.id = repairorder.order_id LEFT JOIN basic_division division ON division.id = repairorder.division_id LEFT JOIN basic_shift shift ON shift.id = repairorder.shift_id LEFT JOIN basic_product product ON product.id = repairorder.product_id LEFT JOIN productioncounting_productiontracking productiontrackingdto ON productiontrackingdto.id = repairorder.productiontracking_id;

CREATE SEQUENCE repairs_repairorder_number_seq;

CREATE OR REPLACE FUNCTION generate_repairorder_number() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _number text; BEGIN _pattern := '#seq'; SELECT nextval('repairs_repairorder_number_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); IF _seq LIKE '%#%' then _seq := _sequence_value; END IF; _number := _pattern; _number := REPLACE(_number, '#seq', _seq); RETURN _number; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_repairorder_number_trigger() RETURNS trigger AS $$ BEGIN NEW.number := generate_repairorder_number(); return NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER repairs_repairorder_trigger_number BEFORE INSERT ON repairs_repairorder FOR EACH ROW EXECUTE PROCEDURE generate_and_set_repairorder_number_trigger();

-- end


ALTER TABLE productioncounting_productiontracking ADD COLUMN repairorder_id bigint;
ALTER TABLE productioncounting_productiontracking ADD CONSTRAINT productiontracking_repairorder_fkey FOREIGN KEY (repairorder_id) REFERENCES repairs_repairorder (id) DEFERRABLE;


DROP TABLE IF EXISTS orders_orderlistdto;

CREATE OR REPLACE VIEW orders_orderlistdto AS SELECT ordersorder.id, ordersorder.active, ordersorder.number, ordersorder.name, ordersorder.datefrom, ordersorder.dateto, ordersorder.startdate, ordersorder.finishdate, ordersorder.state, ordersorder.externalnumber, ordersorder.externalsynchronized, ordersorder.issubcontracted, ordersorder.plannedquantity, ordersorder.workplandelivered, ordersorder.deadline, product.number AS productnumber, technology.number AS technologynumber, product.unit, masterorder.number AS masterordernumber, division.name AS divisionname, company.name AS companyname, masterorderdefinition.number AS masterorderdefinitionnumber, (CASE WHEN (EXISTS (SELECT repairoder.id FROM repairs_repairorder repairoder WHERE repairoder.order_id = ordersorder.id)) THEN TRUE ELSE FALSE END) AS existsrepairorders FROM orders_order ordersorder JOIN basic_product product ON product.id = ordersorder.product_id LEFT JOIN technologies_technology technology ON technology.id = ordersorder.technology_id LEFT JOIN basic_company company ON company.id = ordersorder.company_id LEFT JOIN masterorders_masterorder masterorder ON masterorder.id = ordersorder.masterorder_id LEFT JOIN masterorders_masterorderdefinition masterorderdefinition ON masterorderdefinition.id = masterorder.masterorderdefinition_id LEFT JOIN basic_division division ON division.id = technology.division_id;

-- VIEW: ordersGroupDto

DROP TABLE IF EXISTS ordersgroups_ordersgroupdto;
CREATE OR REPLACE VIEW public.ordersgroups_ordersgroupdto AS SELECT ordersgroup.id, ordersgroup.active, ordersgroup.number, assortment.name AS assortmentname, productionline.number AS productionlinenumber, ordersgroup.startdate, ordersgroup.finishdate, ordersgroup.deadline, ordersgroup.quantity, ordersgroup.producedquantity, ordersgroup.remainingquantity, ''::character varying(255) AS unit, ordersgroup.state, company.number AS company FROM ordersgroups_ordersgroup ordersgroup JOIN basic_assortment assortment ON ordersgroup.assortment_id = assortment.id JOIN productionlines_productionline productionline ON ordersgroup.productionline_id = productionline.id JOIN  masterorders_masterorder masterorder ON ordersgroup.masterorder_id = masterorder.id JOIN basic_company company ON company.id = masterorder.company_id;
-- end

DROP TABLE IF EXISTS  productioncounting_productiontrackingdto;

CREATE OR REPLACE VIEW productioncounting_productiontrackingdto AS SELECT productiontracking.id, productiontracking.number, productiontracking.state, productiontracking.createdate, productiontracking.lasttracking, productiontracking.timerangefrom, productiontracking.timerangeto, productiontracking.active, ordersorder.id::integer AS order_id, ordersorder.number AS ordernumber, ordersorder.state AS orderstate, technologyoperationcomponent.id::integer AS technologyoperationcomponent_id, CASE WHEN technologyoperationcomponent.* IS NULL THEN ''::text ELSE (technologyoperationcomponent.nodenumber::text || ' '::text) || operation.name::text END AS technologyoperationcomponentnumber, operation.id::integer AS operation_id, shift.id::integer AS shift_id, shift.name AS shiftname, staff.id::integer AS staff_id, (staff.name::text || ' '::text) || staff.surname::text AS staffname, division.id::integer AS division_id, division.number AS divisionnumber, subcontractor.id::integer AS subcontractor_id, subcontractor.name AS subcontractorname, repairorderdto.id::integer AS repairorder_id, repairorderdto.number AS repairordernumber, productiontrackingcorrection.number AS correctionnumber, productionline.id::integer AS productionline_id, productionline.number AS productionlinenumber, ordersgroupdto.number AS ordersgroup, concat(product.number, ' - ', product.name) AS productnumber, product.unit AS productunit, outcomponent.usedquantity, company.number AS companynumber FROM productioncounting_productiontracking productiontracking LEFT JOIN orders_order ordersorder ON ordersorder.id = productiontracking.order_id LEFT JOIN basic_product product ON ordersorder.product_id = product.id LEFT JOIN productionlines_productionline productionline ON productionline.id = ordersorder.productionline_id LEFT JOIN technologies_technologyoperationcomponent technologyoperationcomponent ON technologyoperationcomponent.id = productiontracking.technologyoperationcomponent_id LEFT JOIN technologies_operation operation ON operation.id = technologyoperationcomponent.operation_id LEFT JOIN basic_shift shift ON shift.id = productiontracking.shift_id LEFT JOIN basic_staff staff ON staff.id = productiontracking.staff_id LEFT JOIN basic_division division ON division.id = productiontracking.division_id LEFT JOIN basic_company subcontractor ON subcontractor.id = productiontracking.subcontractor_id LEFT JOIN productioncounting_productiontracking productiontrackingcorrection ON productiontrackingcorrection.id = productiontracking.correction_id LEFT JOIN repairs_repairorderdto repairorderdto ON repairorderdto.id = productiontracking.repairorder_id LEFT JOIN ordersgroups_ordersgroupdto ordersgroupdto ON ordersgroupdto.id = ordersorder.ordersgroup_id LEFT JOIN productioncounting_trackingoperationproductoutcomponent outcomponent ON outcomponent.product_id = product.id AND productiontracking.id = outcomponent.productiontracking_id LEFT JOIN basic_company company ON company.id = ordersorder.company_id;
DROP TABLE IF EXISTS productioncounting_productiontrackingforproductdto;

CREATE OR REPLACE VIEW productioncounting_productiontrackingforproductdto AS SELECT trackingoperationproductcomponentdto.id AS id, productiontrackingdto.number AS number, productiontrackingdto.state AS state, productiontrackingdto.createdate AS createdate, productiontrackingdto.lasttracking AS lasttracking, productiontrackingdto.timerangefrom AS timerangefrom, productiontrackingdto.timerangeto AS timerangeto, productiontrackingdto.active AS active, productiontrackingdto.order_id::integer AS order_id, productiontrackingdto.ordernumber AS ordernumber, productiontrackingdto.orderstate AS orderstate, productiontrackingdto.technologyoperationcomponent_id::integer AS technologyoperationcomponent_id, productiontrackingdto.technologyoperationcomponentnumber AS technologyoperationcomponentnumber, productiontrackingdto.operation_id::integer AS operation_id, productiontrackingdto.shift_id::integer AS shift_id, productiontrackingdto.shiftname AS shiftname, productiontrackingdto.staff_id::integer AS staff_id, productiontrackingdto.staffname AS staffname, productiontrackingdto.division_id::integer AS division_id, productiontrackingdto.divisionnumber AS divisionnumber, productiontrackingdto.subcontractor_id::integer AS subcontractor_id, productiontrackingdto.subcontractorname AS subcontractorname, trackingoperationproductcomponentdto.product_id::integer AS product_id, trackingoperationproductcomponentdto.productnumber AS productnumber, trackingoperationproductcomponentdto.productunit AS productunit, trackingoperationproductcomponentdto.plannedquantity AS plannedquantity, trackingoperationproductcomponentdto.usedquantity AS usedquantity, productiontrackingdto.id::integer AS productiontracking_id, trackingoperationproductcomponentdto.batchnumber FROM productioncounting_trackingoperationproductcomponentdto trackingoperationproductcomponentdto LEFT JOIN productioncounting_productiontrackingdto productiontrackingdto ON productiontrackingdto.id = trackingoperationproductcomponentdto.productiontracking_id;


DROP TABLE IF EXISTS productioncounting_productiontrackingforproductgroupeddto;

CREATE OR REPLACE VIEW productioncounting_productiontrackingforproductgroupeddto AS SELECT row_number() OVER () AS id, productiontrackingforproductdto.active AS active, productiontrackingforproductdto.order_id::integer AS order_id, productiontrackingforproductdto.ordernumber AS ordernumber, productiontrackingforproductdto.technologyoperationcomponent_id::integer AS technologyoperationcomponent_id, productiontrackingforproductdto.technologyoperationcomponentnumber AS technologyoperationcomponentnumber, productiontrackingforproductdto.operation_id AS operation_id, productiontrackingforproductdto.product_id::integer AS product_id, productiontrackingforproductdto.productnumber AS productnumber, productiontrackingforproductdto.productunit AS productunit, productiontrackingforproductdto.plannedquantity AS plannedquantity, SUM(productiontrackingforproductdto.usedquantity) AS usedquantity FROM productioncounting_productiontrackingforproductdto productiontrackingforproductdto GROUP BY productiontrackingforproductdto.active, productiontrackingforproductdto.order_id, productiontrackingforproductdto.ordernumber, productiontrackingforproductdto.technologyoperationcomponent_id, productiontrackingforproductdto.technologyoperationcomponentnumber, productiontrackingforproductdto.operation_id, productiontrackingforproductdto.product_id, productiontrackingforproductdto.productnumber, productiontrackingforproductdto.productunit, productiontrackingforproductdto.plannedquantity;


-- VIEW: cmmsmachineparts_worktimeforuserdto

DROP TABLE IF EXISTS cmmsmachineparts_worktimeforuserdto;

CREATE OR REPLACE VIEW cmmsmachineparts_worktimeforuserdto_internal AS SELECT u.username AS username, swt.effectiveexecutiontimestart AS startdate, swt.effectiveexecutiontimeend AS finishdate, swt.labortime AS duration, me.number AS eventNumber, me.type AS eventtype, COALESCE(s.number, w.number, p.number, d.number, f.number) AS objectnumber, null AS actionname FROM cmmsmachineparts_staffworktime swt JOIN qcadoosecurity_user u ON swt.worker_id = u.staff_id JOIN cmmsmachineparts_maintenanceevent me ON me.id = swt.maintenanceevent_id JOIN basic_factory f ON me.factory_id = f.id JOIN basic_division d ON me.division_id = d.id LEFT JOIN productionlines_productionline p ON me.productionline_id = p.id LEFT JOIN basic_workstation w ON me.workstation_id = w.id LEFT JOIN basic_subassembly s ON me.subassembly_id = s.id union all SELECT u.username AS username, per.startdate AS startdate, per.finishdate AS finishdate, per.duration AS duration, pe.number AS eventnumber, pe.type AS eventtype, COALESCE(s.number, w.number, p.number, d.number, f.number) AS objectnumber, a.name AS actionname FROM cmmsmachineparts_plannedeventrealization per JOIN qcadoosecurity_user u ON per.worker_id = u.staff_id JOIN cmmsmachineparts_plannedevent pe ON pe.id = per.plannedevent_id JOIN basic_factory f ON pe.factory_id = f.id JOIN basic_division d ON pe.division_id = d.id LEFT JOIN productionlines_productionline p ON pe.productionline_id = p.id LEFT JOIN basic_workstation w ON pe.workstation_id = w.id LEFT JOIN basic_subassembly s ON pe.subassembly_id = s.id LEFT JOIN cmmsmachineparts_actionforplannedevent afpe ON per.action_id = afpe.id LEFT JOIN cmmsmachineparts_action a ON afpe.action_id = a.id;

CREATE OR REPLACE VIEW cmmsmachineparts_worktimeforuserdto AS SELECT row_number() OVER () AS id, internal.* FROM cmmsmachineparts_worktimeforuserdto_internal internal;

-- end


-- VIEW: storageLocationDto

DROP TABLE IF EXISTS materialflowresources_storagelocationdto;

CREATE OR REPLACE VIEW materialflowresources_storagelocationdto_internal AS SELECT location.number AS locationNumber, storageLocation.number AS storageLocationNumber, COALESCE(product.number, storageProduct.number) AS productNumber, COALESCE(product.name, storageProduct.name) AS productName, resourceCode.code AS additionalCode, COALESCE(SUM(resource.quantity), 0::numeric) AS resourceQuantity, COALESCE(product.unit, storageProduct.unit) AS productUnit, COALESCE(SUM(resource.quantityinadditionalunit), 0::numeric) AS quantityInAdditionalUnit, COALESCE(product.additionalunit, product.unit, storageProduct.additionalunit, storageProduct.unit) AS productAdditionalUnit FROM materialflowresources_storagelocation storageLocation JOIN materialflow_location location ON storageLocation.location_id = location.id LEFT JOIN materialflowresources_resource resource ON resource.storagelocation_id = storageLocation.id LEFT JOIN basic_product product ON product.id = resource.product_id LEFT JOIN basic_product storageProduct ON storageProduct.id = storageLocation.product_id LEFT JOIN basic_additionalcode resourceCode ON resourceCode.id = resource.additionalcode_id  where storageLocation.active = true GROUP BY locationNumber, storageLocationNumber, productNumber, productName, additionalCode, productUnit, productAdditionalUnit;

CREATE OR REPLACE VIEW materialflowresources_storagelocationdto AS SELECT row_number() OVER () AS id, internal.* FROM materialflowresources_storagelocationdto_internal internal;

DROP TABLE IF EXISTS deliveries_orderedproductlistdto;
CREATE OR REPLACE VIEW deliveries_orderedproductlistdto AS SELECT orderedproduct.id, orderedproduct.succession, orderedproduct.orderedquantity, orderedproduct.priceperunit, orderedproduct.conversion, orderedproduct.additionalquantity, orderedproduct.description, orderedproduct.actualversion, delivery.id AS delivery, delivery.id::integer AS deliveryid, delivery.supplier_id AS supplier, delivery.deliverydate, delivery.state AS deliverystate, delivery.number AS deliverynumber, delivery.name AS deliveryname, delivery.active AS deliveryactive, currency.alphabeticcode AS deliverycurrency, supplier.name AS suppliername, product.number AS productnumber, product.name AS productname, product.norm AS productnorm, product.unit AS productunit, offer.number AS offernumber, negotiation.number AS negotiationnumber, operation.number AS operationnumber, ( SELECT productcatalognumbers_productcatalognumbers.catalognumber FROM productcatalognumbers_productcatalognumbers WHERE productcatalognumbers_productcatalognumbers.product_id = product.id AND productcatalognumbers_productcatalognumbers.company_id = delivery.supplier_id) AS productcatalognumber FROM deliveries_orderedproduct orderedproduct LEFT JOIN deliveries_delivery delivery ON orderedproduct.delivery_id = delivery.id LEFT JOIN basic_currency currency ON delivery.currency_id = currency.id LEFT JOIN basic_company supplier ON delivery.supplier_id = supplier.id LEFT JOIN basic_product product ON orderedproduct.product_id = product.id LEFT JOIN supplynegotiations_offer offer ON orderedproduct.offer_id = offer.id LEFT JOIN supplynegotiations_negotiation negotiation ON offer.negotiation_id = negotiation.id LEFT JOIN technologies_operation operation ON orderedproduct.operation_id = operation.id;

DROP TABLE IF EXISTS deliveries_orderedproductdto;

CREATE OR REPLACE VIEW deliveries_orderedproductdto AS SELECT orderedproduct.id, orderedproduct.succession, orderedproduct.orderedquantity, orderedproduct.priceperunit, orderedproduct.totalprice, orderedproduct.conversion, orderedproduct.additionalquantity, orderedproduct.description, orderedproduct.actualversion, delivery.id AS delivery, delivery.id::integer AS deliveryid, delivery.supplier_id AS supplier, delivery.deliveryDate AS deliveryDate, delivery.state AS deliveryState, delivery.number AS deliveryNumber, delivery.name AS deliveryName, delivery.active AS deliveryActive, currency.alphabeticCode AS deliveryCurrency, supplier.name AS supplierName, product.number AS productnumber, product.name AS productname, product.norm AS productnorm, product.unit AS productunit, addcode.code AS additionalcode, offer.number AS offernumber, negotiation.number AS negotiationNumber, operation.number AS operationnumber, ( SELECT productcatalognumbers_productcatalognumbers.catalognumber FROM productcatalognumbers_productcatalognumbers WHERE productcatalognumbers_productcatalognumbers.product_id = product.id AND productcatalognumbers_productcatalognumbers.company_id = delivery.supplier_id) AS productcatalognumber, CASE WHEN addcode.id IS NULL THEN ( SELECT sum(deliveries_deliveredproduct.deliveredquantity) AS sum FROM deliveries_deliveredproduct WHERE deliveries_deliveredproduct.delivery_id = delivery.id AND deliveries_deliveredproduct.product_id = product.id AND deliveries_deliveredproduct.additionalcode_id IS NULL GROUP BY deliveries_deliveredproduct.product_id, deliveries_deliveredproduct.additionalcode_id) ELSE ( SELECT sum(deliveries_deliveredproduct.deliveredquantity) AS sum FROM deliveries_deliveredproduct WHERE deliveries_deliveredproduct.delivery_id = delivery.id AND deliveries_deliveredproduct.product_id = product.id AND deliveries_deliveredproduct.additionalcode_id = addcode.id GROUP BY deliveries_deliveredproduct.product_id, deliveries_deliveredproduct.additionalcode_id) END AS deliveredquantity, CASE WHEN addcode.id IS NULL THEN ( SELECT sum(deliveredproduct.additionalquantity) AS sum FROM deliveries_deliveredproduct deliveredproduct WHERE deliveredproduct.delivery_id = delivery.id AND deliveredproduct.product_id = product.id AND deliveredproduct.additionalcode_id IS NULL GROUP BY deliveredproduct.product_id, deliveredproduct.additionalcode_id) ELSE ( SELECT sum(deliveries_deliveredproduct.additionalquantity) AS sum FROM deliveries_deliveredproduct WHERE deliveries_deliveredproduct.delivery_id = delivery.id AND deliveries_deliveredproduct.product_id = product.id AND deliveries_deliveredproduct.additionalcode_id = addcode.id GROUP BY deliveries_deliveredproduct.product_id, deliveries_deliveredproduct.additionalcode_id) END AS additionaldeliveredquantity, CASE WHEN addcode.id IS NULL THEN orderedproduct.orderedquantity - (( SELECT sum(deliveries_deliveredproduct.deliveredquantity) AS sum FROM deliveries_deliveredproduct WHERE deliveries_deliveredproduct.delivery_id = delivery.id AND deliveries_deliveredproduct.product_id = product.id AND deliveries_deliveredproduct.additionalcode_id IS NULL GROUP BY deliveries_deliveredproduct.product_id, deliveries_deliveredproduct.additionalcode_id)) ELSE orderedproduct.orderedquantity - (( SELECT sum(deliveries_deliveredproduct.deliveredquantity) AS sum FROM deliveries_deliveredproduct WHERE deliveries_deliveredproduct.delivery_id = delivery.id AND deliveries_deliveredproduct.product_id = product.id AND deliveries_deliveredproduct.additionalcode_id = addcode.id GROUP BY deliveries_deliveredproduct.product_id, deliveries_deliveredproduct.additionalcode_id)) END AS lefttoreceivequantity, CASE WHEN addcode.id IS NULL THEN orderedproduct.additionalquantity - (( SELECT sum(deliveredproduct.additionalquantity) AS sum FROM deliveries_deliveredproduct deliveredproduct WHERE deliveredproduct.delivery_id = delivery.id AND deliveredproduct.product_id = product.id AND deliveredproduct.additionalcode_id IS NULL GROUP BY deliveredproduct.product_id, deliveredproduct.additionalcode_id)) ELSE orderedproduct.additionalquantity - (( SELECT sum(deliveredproduct.additionalquantity) AS sum FROM deliveries_deliveredproduct deliveredproduct WHERE deliveredproduct.delivery_id = delivery.id AND deliveredproduct.product_id = product.id AND deliveredproduct.additionalcode_id = addcode.id GROUP BY deliveredproduct.product_id, deliveredproduct.additionalcode_id)) END AS additionallefttoreceivequantity FROM deliveries_orderedproduct orderedproduct LEFT JOIN deliveries_delivery delivery ON orderedproduct.delivery_id = delivery.id LEFT JOIN basic_currency currency ON delivery.currency_id = currency.id LEFT JOIN basic_company supplier ON delivery.supplier_id = supplier.id LEFT JOIN basic_product product ON orderedproduct.product_id = product.id LEFT JOIN supplynegotiations_offer offer ON orderedproduct.offer_id = offer.id LEFT JOIN supplynegotiations_negotiation negotiation ON offer.negotiation_id = negotiation.id LEFT JOIN technologies_operation operation ON orderedproduct.operation_id = operation.id LEFT JOIN basic_additionalcode addcode ON orderedproduct.additionalcode_id = addcode.id;

DROP TABLE IF EXISTS deliveries_deliveredproductdto;

CREATE OR REPLACE VIEW deliveries_deliveredproductdto AS SELECT deliveredproduct.id AS id, deliveredproduct.succession AS succession, deliveredproduct.damagedquantity AS damagedquantity, deliveredproduct.deliveredquantity AS deliveredquantity, deliveredproduct.priceperunit AS priceperunit, deliveredproduct.totalprice AS totalprice, deliveredproduct.conversion AS conversion, deliveredproduct.additionalquantity AS additionalquantity, deliveredproduct.iswaste AS iswaste, delivery.id AS delivery, delivery.id::integer AS deliveryId, delivery.supplier_id AS supplier, product.number AS productNumber, product.name AS productName, product.unit AS productUnit, addcode.code AS additionalCode, offer.number AS offerNumber, operation.number AS operationNumber, slocation.number AS storageLocationNumber, pnumber.number AS palletNumber, (SELECT catalognumber FROM productcatalognumbers_productcatalognumbers WHERE product_id = product.id AND company_id = delivery.supplier_id) AS productCatalogNumber FROM deliveries_deliveredproduct deliveredproduct LEFT JOIN deliveries_delivery delivery ON deliveredproduct.delivery_id = delivery.id LEFT JOIN basic_product product ON deliveredproduct.product_id = product.id LEFT JOIN supplynegotiations_offer offer ON deliveredproduct.offer_id = offer.id LEFT JOIN technologies_operation operation ON deliveredproduct.operation_id = operation.id LEFT JOIN basic_additionalcode addcode ON deliveredproduct.additionalcode_id = addcode.id LEFT JOIN materialflowresources_storagelocation slocation ON deliveredproduct.storagelocation_id = slocation.id LEFT JOIN basic_palletnumber pnumber ON deliveredproduct.palletnumber_id = pnumber.id;

 -- end

-- views for gantt

DROP TABLE IF EXISTS linechangeovernorms_ordersnormview;
DROP TABLE IF EXISTS linechangeovernorms_normflatview;
DROP TABLE IF EXISTS linechangeovernorms_groupsview;

CREATE OR REPLACE VIEW linechangeovernorms_groupsview AS SELECT norms.number, norms.name, norms.duration, '02forTechnologyGroup'::text AS changeovertype, norms.productionline_id AS productionlineid, technologygroupfrom.id AS technologygroupfromid, technologygroupto.id AS technologygrouptoid, technologyfrom.id AS technologyfromid, technologyto.id AS technologytoid, technologyfrom.number AS technologyfromnumber, technologyto.number AS technologytonumber FROM linechangeovernorms_linechangeovernorms norms LEFT JOIN technologies_technologygroup technologygroupfrom ON technologygroupfrom.id = norms.fromtechnologygroup_id LEFT JOIN technologies_technology technologyfrom ON technologyfrom.technologygroup_id = technologygroupfrom.id AND technologyfrom.active = true AND technologyfrom.technologyprototype_id IS NULL LEFT JOIN technologies_technologygroup technologygroupto ON technologygroupto.id = norms.totechnologygroup_id LEFT JOIN technologies_technology technologyto ON technologyto.technologygroup_id = technologygroupto.id AND technologyto.active = true AND technologyto.technologyprototype_id IS NULL WHERE norms.changeovertype::text = '02forTechnologyGroup'::text;

CREATE OR REPLACE VIEW linechangeovernorms_normflatview AS SELECT groupnorms.number, groupnorms.name, groupnorms.duration, groupnorms.changeovertype, groupnorms.productionlineid, groupnorms.technologyfromid AS technnolgyfromid, groupnorms.technologytoid, groupnorms.technologyfromnumber, groupnorms.technologytonumber FROM linechangeovernorms_groupsview groupnorms WHERE groupnorms.technologyfromid IS NOT NULL AND groupnorms.technologytoid IS NOT NULL UNION ALL SELECT norms.number, norms.name, norms.duration, norms.changeovertype, norms.productionline_id AS productionlineid, norms.fromtechnology_id AS technnolgyfromid, norms.totechnology_id AS technologytoid, technologyfrom.number AS technologyfromnumber, technologyto.number AS technologytonumber FROM linechangeovernorms_linechangeovernorms norms LEFT JOIN technologies_technology technologyfrom ON technologyfrom.id = norms.fromtechnology_id LEFT JOIN technologies_technology technologyto ON technologyto.id = norms.totechnology_id WHERE norms.changeovertype::text = '01forTechnology'::text AND norms.fromtechnology_id IS NOT NULL AND norms.totechnology_id IS NOT NULL;

CREATE OR REPLACE VIEW linechangeovernorms_ordersnormview AS SELECT (o.id::text || ', '::text) || norms.number::text AS id, o.number, o.id AS orderid, norms.number AS normnumber, norms.name AS normname, norms.duration, norms.technologyfromnumber, norms.technologytonumber FROM orders_order o LEFT JOIN linechangeovernorms_normflatview norms ON norms.technologytoid = o.technologyprototype_id AND norms.technnolgyfromid = (( SELECT ord.technologyprototype_id FROM orders_order ord WHERE ord.active = true AND ord.productionline_id = o.productionline_id AND ord.finishdate < o.finishdate AND (ord.state::text <> ALL (ARRAY['05declined'::character varying::text, '07abandoned'::character varying::text])) ORDER BY ord.finishdate DESC LIMIT 1)) WHERE o.active = true AND o.finishdate > (now() - '1 mon'::interval) AND norms.number IS NOT NULL ORDER BY norms.productionlineid, norms.changeovertype;

-- end


-- VIEW: positionDto

DROP TABLE IF EXISTS materialflowresources_positiondto;

CREATE OR REPLACE VIEW materialflowresources_positiondto AS SELECT position.id AS id, locFrom.number AS locationFrom, locTo.number AS locationTo, product.number AS productNumber, product.name AS productName, position.quantity AS quantity, position.price AS price, product.unit AS productUnit, document.time AS documentDate, position.expirationdate::TIMESTAMP WITHOUT TIME ZONE AS expirationDate, position.productiondate::TIMESTAMP WITHOUT TIME ZONE AS productionDate, document.type AS documentType, document.state AS state, document.number AS documentNumber, document.name AS documentName, company.name AS companyName, (CASE WHEN address.name IS NULL THEN address.number ELSE address.number::text || ' - '::text || address.name::text END) AS documentAddress, position.batch AS batch, storageLoc.number AS storageLocation, position.waste AS waste, delivery.number AS deliveryNumber, plannedEvent.number AS plannedEventNumber, maintenanceEvent.number AS maintenanceEventNumber, subOrder.number AS subOrderNumber, ord.number AS orderNumber FROM materialflowresources_position position JOIN materialflowresources_document document ON position.document_id = document.id LEFT JOIN materialflow_location locFrom ON document.locationfrom_id = locFrom.id LEFT JOIN materialflow_location locTo ON document.locationto_id = locTo.id JOIN basic_product product ON position.product_id = product.id LEFT JOIN basic_company company ON document.company_id = company.id LEFT JOIN basic_address address ON document.address_id = address.id LEFT JOIN materialflowresources_storagelocation storageLoc ON position.storagelocation_id = storageLoc.id LEFT JOIN cmmsmachineparts_maintenanceevent maintenanceEvent ON document.maintenanceevent_id = maintenanceEvent.id LEFT JOIN cmmsmachineparts_plannedevent plannedEvent ON document.plannedevent_id = plannedEvent.id LEFT JOIN deliveries_delivery delivery ON document.delivery_id = delivery.id LEFT JOIN subcontractorportal_suborder subOrder ON document.suborder_id = subOrder.id LEFT JOIN orders_order ord ON document.order_id = ord.id;

-- end


-- VIEW: masterorders_masterorderpositiondto

DROP TABLE IF EXISTS masterorders_masterorderpositiondto;

CREATE OR REPLACE VIEW masterorders_masterorderposition_manyproducts AS SELECT COALESCE(masterorderproduct.id, 0::integer), masterorderdefinition.name, masterorder.id::integer AS masterorderid, masterorderproduct.product_id::integer AS productid, masterorderproduct.id::integer AS masterorderproductid, masterorder.masterordertype, masterorder.name AS masterordername, masterorder.number, masterorder.deadline, masterorder.masterorderstate AS masterorderstatus, masterorderproduct.masterorderpositionstatus, COALESCE(masterorderproduct.masterorderquantity, 0::numeric) AS masterorderquantity, COALESCE((SELECT SUM(orders.plannedquantity)), 0::numeric) AS cumulatedmasterorderquantity, COALESCE((SELECT SUM(orders.donequantity)), 0::numeric) AS producedorderquantity, CASE WHEN (COALESCE(masterorderproduct.masterorderquantity, 0::numeric) - COALESCE((SELECT SUM(orders.donequantity)), 0::numeric)) > 0 THEN (COALESCE(masterorderproduct.masterorderquantity, 0::numeric)- COALESCE((SELECT SUM(orders.donequantity)), 0::numeric)) ELSE 0::numeric END AS lefttorelease, masterorderproduct.comments, product.number AS productnumber, product.name AS productname, product.unit, technology.number AS technologyname, company.name AS companyname, masterorder.active,companypayer.name AS companypayer FROM masterorders_masterorder masterorder LEFT JOIN masterorders_masterorderdefinition masterorderdefinition ON masterorderdefinition.id = masterorder.masterorderdefinition_id LEFT JOIN masterorders_masterorderproduct masterorderproduct ON masterorderproduct.masterorder_id = masterorder.id LEFT JOIN basic_product product ON product.id = masterorderproduct.product_id LEFT JOIN basic_company company ON company.id = masterorder.company_id LEFT JOIN technologies_technology technology ON technology.id = masterorderproduct.technology_id LEFT JOIN orders_order orders ON orders.masterorder_id = masterorderproduct.masterorder_id AND orders.product_id = masterorderproduct.product_id LEFT JOIN basic_company companypayer ON companypayer.id = masterorder.companypayer_id WHERE masterorder.masterordertype = '03manyProducts' AND masterorderproduct.id IS NOT NULL GROUP BY masterorderdefinition.name, masterorder.id, masterorder.product_id, masterorderproduct.id, masterorder.masterordertype, masterorder.name, masterorder.deadline, masterorder.masterorderstate, masterorder.masterorderpositionstatus, masterorder.comments, product.number, product.name, product.unit, technology.number, company.name, masterorder.active,companypayer.name;

CREATE OR REPLACE VIEW public.masterorders_masterorderposition_oneproduct AS SELECT (( SELECT COALESCE(max(masterorders_masterorderproduct.id), 0::bigint) AS "coalesce" FROM masterorders_masterorderproduct)) + row_number() OVER () AS id, masterorderdefinition.name, masterorder.id::integer AS masterorderid, masterorder.product_id::integer AS productid, masterorderproduct.id::integer AS masterorderproductid, masterorder.masterordertype, masterorder.name AS masterordername, masterorder.number, masterorder.deadline, masterorder.masterorderstate AS masterorderstatus, masterorder.masterorderpositionstatus, COALESCE(masterorder.masterorderquantity, 0::numeric) AS masterorderquantity, COALESCE(( SELECT sum(orders.plannedquantity) AS sum), 0::numeric) AS cumulatedmasterorderquantity, COALESCE(( SELECT sum(orders.donequantity) AS sum), 0::numeric) AS producedorderquantity, CASE WHEN (COALESCE(masterorderproduct.masterorderquantity, 0::numeric) - COALESCE(( SELECT sum(orders.donequantity) AS sum), 0::numeric)) > 0::numeric THEN COALESCE(masterorderproduct.masterorderquantity, 0::numeric) - COALESCE(( SELECT sum(orders.donequantity) AS sum), 0::numeric) ELSE 0::numeric END AS lefttorelease, masterorder.comments, product.number AS productnumber, product.name AS productname, product.unit, technology.number AS technologyname, company.name AS companyname, masterorder.active, companypayer.name AS companypayer FROM masterorders_masterorder masterorder LEFT JOIN masterorders_masterorderdefinition masterorderdefinition ON masterorderdefinition.id = masterorder.masterorderdefinition_id LEFT JOIN masterorders_masterorderproduct masterorderproduct ON masterorderproduct.masterorder_id = masterorder.id LEFT JOIN basic_product product ON product.id = masterorder.product_id LEFT JOIN basic_company company ON company.id = masterorder.company_id LEFT JOIN technologies_technology technology ON technology.id = masterorder.technology_id LEFT JOIN orders_order orders ON orders.masterorder_id = masterorder.id AND orders.product_id = masterorder.product_id LEFT JOIN basic_company companypayer ON companypayer.id = masterorder.companypayer_id WHERE masterorder.masterordertype::text = '02oneProduct'::text GROUP BY companypayer.name,masterorderdefinition.name, masterorder.id, masterorder.product_id, masterorderproduct.id, masterorder.masterordertype, masterorder.name, masterorder.deadline, masterorder.masterorderstate, masterorder.masterorderpositionstatus, masterorder.comments, product.number, product.name, product.unit, technology.number, company.name, masterorder.active;

CREATE OR REPLACE VIEW masterorders_masterorderpositiondto AS SELECT * FROM masterorders_masterorderposition_oneproduct UNION ALL SELECT * FROM masterorders_masterorderposition_manyproducts;

-- end


-- production tracking number sequence

CREATE SEQUENCE productioncounting_productiontracking_number_seq;

CREATE OR REPLACE FUNCTION generate_productiontracking_number() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _number text; BEGIN _pattern := '#seq'; select nextval('productioncounting_productiontracking_number_seq') into _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); if _seq like '%#%' then _seq := _sequence_value; end if; _number := _pattern; _number := replace(_number, '#seq', _seq); RETURN _number; END; $$ LANGUAGE 'plpgsql';

-- end

-- VIEW masterorders_masterorderdto

DROP TABLE IF EXISTS masterorders_masterorderdto;

CREATE OR REPLACE VIEW masterorders_masterorderdto AS SELECT masterorder.id, masterorderdefinition.number AS masterorderdefinition, masterorder.number, masterorder.name, masterorder.deadline, company.name AS company, companypayer.name AS companypayer, masterorder.masterorderpositionstatus AS status, COALESCE(orderedpositions.count::integer, 0::integer) AS orderedpositionquantity, COALESCE(cumulatedpositions.count::integer, 0::integer) AS commissionedpositionquantity, COALESCE(orderedpositions.count::integer, 0::integer) - COALESCE(cumulatedpositions.count::integer, 0::integer) AS quantityforcommission, masterorder.masterorderstate, masterorder.active FROM masterorders_masterorder masterorder LEFT JOIN masterorders_masterorderdefinition masterorderdefinition ON masterorderdefinition.id = masterorder.masterorderdefinition_id LEFT JOIN basic_company company ON company.id = masterorder.company_id LEFT JOIN basic_company companypayer ON companypayer.id = masterorder.companypayer_id LEFT JOIN ( SELECT masterorderid, count(*) AS count FROM masterorders_masterorderpositiondto GROUP BY masterorderid ) orderedpositions ON orderedpositions.masterorderid = masterorder.id LEFT JOIN ( SELECT masterorderid, count(*) AS count FROM masterorders_masterorderpositiondto WHERE cumulatedmasterorderquantity > 0 GROUP BY masterorderid ) cumulatedpositions ON cumulatedpositions.masterorderid = masterorder.id;
-- end

-- VIEW: productioncounting_performanceanalysisdetaildto

DROP TABLE IF EXISTS productioncounting_performanceanalysisdetaildto;

CREATE OR REPLACE VIEW productioncounting_performanceanalysisdetaildto AS SELECT productiontracking.id AS id, productiontracking.active AS active, productionline.id::integer AS productionline_id, productionline.number AS productionlinenumber, staff.id::integer AS staff_id, staff.name || ' ' || staff.surname AS staffname, assortment.id::integer AS assortment_id, assortment.name AS assortmentname, product.id::integer AS product_id, product.number AS productnumber, product.name AS productname, product.unit AS productunit, product.size AS size, technology.standardperformancetechnology AS performancenorm, (COALESCE(trackingoperationproductoutcomponent.usedquantity, 0) + COALESCE(trackingoperationproductoutcomponent.wastesquantity, 0))::numeric(14,5) AS donequantity, ((COALESCE(trackingoperationproductoutcomponent.usedquantity, 0) + COALESCE(trackingoperationproductoutcomponent.wastesquantity, 0))::numeric * 60 / technology.standardperformancetechnology)::integer AS timebasedonnorms, shift.id::integer AS shift_id, shift.name AS shiftname, productiontracking.timerangefrom AS timerangefrom, productiontracking.timerangeto AS timerangeto, ordersorder.id::integer AS order_id, ordersorder.number AS ordernumber FROM productioncounting_productiontracking productiontracking LEFT JOIN orders_order ordersorder ON ordersorder.id = productiontracking.order_id LEFT JOIN productionlines_productionline productionline ON productionline.id = ordersorder.productionline_id LEFT JOIN basic_staff staff ON staff.id = productiontracking.staff_id LEFT JOIN productioncounting_trackingoperationproductoutcomponent trackingoperationproductoutcomponent ON trackingoperationproductoutcomponent.productiontracking_id = productiontracking.id LEFT JOIN basic_product product ON product.id = trackingoperationproductoutcomponent.product_id LEFT JOIN basic_assortment assortment ON assortment.id = product.assortment_id LEFT JOIN technologies_technology technology ON technology.id = ordersorder.technology_id LEFT JOIN basic_shift shift ON shift.id = productiontracking.shift_id WHERE productiontracking.state IN ('01draft', '02accepted');

-- end


-- VIEW: productioncounting_performanceanalysisdto

DROP TABLE IF EXISTS productioncounting_performanceanalysisdto;

CREATE OR REPLACE VIEW productioncounting_performanceanalysisdto AS SELECT row_number() OVER () AS id, BOOL_OR(performanceanalysisdetaildto.active) AS active, performanceanalysisdetaildto.productionline_id::integer AS productionline_id, performanceanalysisdetaildto.productionlinenumber AS productionlinenumber, performanceanalysisdetaildto.staff_id::integer AS staff_id, performanceanalysisdetaildto.staffname AS staffname, COALESCE(SUM(performanceanalysisdetaildto.timebasedonnorms)::integer, 0) AS timebasedonnormssum, (8 * 60 * 60)::integer AS labortimesum, (COALESCE(SUM(performanceanalysisdetaildto.timebasedonnorms)::integer, 0) - (8 * 60 * 60))::integer AS timedeviation, (100 * SUM(performanceanalysisdetaildto.timebasedonnorms)::numeric / (8 * 60 * 60))::numeric(14,5) AS performance, performanceanalysisdetaildto.shift_id::integer AS shift_id, performanceanalysisdetaildto.shiftname, performanceanalysisdetaildto.timerangefrom::date AS timerangefrom, performanceanalysisdetaildto.timerangeto::date AS timerangeto FROM productioncounting_performanceanalysisdetaildto performanceanalysisdetaildto GROUP BY productionline_id, productionlinenumber, staff_id, staffname, shift_id, shiftname, timerangefrom::date, timerangeto::date;

-- end


-- VIEW: productioncounting_productionanalysisdto

DROP TABLE IF EXISTS productioncounting_productionanalysisdto;

CREATE OR REPLACE VIEW productioncounting_productionanalysisdto AS SELECT ROW_NUMBER() OVER () AS id, BOOL_OR(productiontracking.active) AS active, productionline.id::integer AS productionline_id, productionline.number AS productionlinenumber, basiccompany.id::integer as company_id, basiccompany.number as companynumber, staff.id::integer AS staff_id, staff.name || ' ' || staff.surname AS staffname, assortment.id::integer AS assortment_id, assortment.name AS assortmentname, product.id::integer AS product_id, product.number AS productnumber, product.name AS productname, product.unit AS productunit, product.size AS size, SUM(COALESCE(trackingoperationproductoutcomponent.usedquantity, 0)::numeric(14,5)) AS usedquantity, SUM(COALESCE(trackingoperationproductoutcomponent.wastesquantity, 0)::numeric(14,5)) as wastesquantity, SUM((COALESCE(trackingoperationproductoutcomponent.usedquantity, 0) + COALESCE(trackingoperationproductoutcomponent.wastesquantity, 0))::numeric(14,5)) AS donequantity, shift.id::integer AS shift_id, shift.name AS shiftname, productiontracking.timerangefrom::date AS timerangefrom, productiontracking.timerangeto::date AS timerangeto, tcontext.id::integer AS generator_id, tcontext.number AS generatorname, ordersorder.id::integer AS order_id, ordersorder.number AS ordernumber FROM productioncounting_productiontracking productiontracking LEFT JOIN orders_order ordersorder ON ordersorder.id = productiontracking.order_id LEFT JOIN basic_company basiccompany ON basiccompany.id = ordersorder.company_id LEFT JOIN productionlines_productionline productionline ON productionline.id = ordersorder.productionline_id LEFT JOIN basic_staff staff ON staff.id = productiontracking.staff_id LEFT JOIN productioncounting_trackingoperationproductoutcomponent trackingoperationproductoutcomponent ON trackingoperationproductoutcomponent.productiontracking_id = productiontracking.id LEFT JOIN basic_product product ON product.id = trackingoperationproductoutcomponent.product_id LEFT JOIN basic_assortment assortment ON assortment.id = product.assortment_id LEFT JOIN basic_shift shift ON shift.id = productiontracking.shift_id LEFT JOIN technologiesgenerator_generatortechnologiesforproduct tgenn ON ordersorder.technologyprototype_id = tgenn.technology_id LEFT JOIN technologiesgenerator_generatorcontext tcontext ON tcontext.id = tgenn.generatorcontext_id WHERE productiontracking.state IN ('01draft', '02accepted') GROUP BY productionline.id, basiccompany.id, staff.id, assortment.id, product.id, shift.id, timerangefrom::date, timerangeto::date, ordersorder.id, tcontext.id;

-- end


-- VIEW: productioncounting_beforeadditionalactionsanalysisentry

DROP TABLE IF EXISTS productioncounting_beforeadditionalactionsanalysisentry;

CREATE OR REPLACE VIEW productioncounting_beforeadditionalactionsanalysisentry AS SELECT row_number() OVER () AS id, pl.number AS productionLineNumber, ord.number AS orderNumber, c.number AS companyNumber, assortment.name AS assortmentName, product.number AS productNumber,product.name AS productName, product.unit AS productUnit, product.size AS size, SUM(COALESCE(topoc.usedquantity, 0)) AS quantity, SUM(COALESCE(topoc.wastesquantity,0)) AS wastes, SUM(COALESCE(topoc.usedquantity, 0)) + SUM(COALESCE(topoc.wastesquantity,0)) AS doneQuantity, DATE(date_trunc('day',pt.timerangefrom)) AS timeRangeFrom, DATE(date_trunc('day',pt.timerangeto)) AS timeRangeTo, shift.name AS shiftName, tcontext.number AS technologyGeneratorNumber FROM productioncounting_trackingoperationproductoutcomponent topoc JOIN productioncounting_productiontracking pt ON pt.id = topoc.productiontracking_id JOIN orders_order ord ON ord.id = pt.order_id JOIN basic_product product ON topoc.product_id = product.id JOIN technologies_technology technologyPrototype ON technologyPrototype.id = ord.technologyprototype_id JOIN technologies_technology technology ON technology.id = ord.technology_id LEFT JOIN orders_order parentOrder ON ord.parent_id = parentOrder.id LEFT JOIN technologies_technology parentTechnology ON parentTechnology.id = parentOrder.technology_id LEFT JOIN basic_shift shift ON pt.shift_id = shift.id LEFT JOIN basic_assortment assortment ON product.assortment_id = assortment.id LEFT JOIN productionlines_productionline pl ON ord.productionline_id = pl.id LEFT JOIN basic_company c ON c.id = ord.company_id LEFT JOIN technologiesgenerator_generatortechnologiesforproduct tgenn ON technologyPrototype.id = tgenn.technology_id LEFT JOIN technologiesgenerator_generatorcontext tcontext ON tcontext.id = tgenn.generatorcontext_id WHERE (technology.additionalActions = FALSE AND (parentTechnology.additionalActions = TRUE OR ord.parent_id IS NULL)) AND (product.id = ord.product_id OR (pt.technologyoperationcomponent_id IS NOT NULL AND topoc.typeofmaterial = '02intermediate')) GROUP BY ord.number, shift.name, date_trunc('day',pt.timerangefrom), date_trunc('day',pt.timerangeto), productionLineNumber, companyNumber, assortmentName, productNumber, productName, productUnit, size, technologyGeneratorNumber;

-- end


-- VIEW: productioncounting_finalproductanalysisentry

DROP TABLE IF EXISTS productioncounting_finalproductanalysisentry;

CREATE OR REPLACE VIEW productioncounting_finalproductanalysisentry AS SELECT row_number() OVER () AS id, pl.number AS productionLineNumber, ord.number AS orderNumber, c.number AS companyNumber, assortment.name AS assortmentName, product.number AS productNumber,product.name AS productName, product.unit AS productUnit, product.size AS size, SUM(COALESCE(topoc.usedquantity, 0)) AS quantity, SUM(COALESCE(topoc.wastesquantity,0)) AS wastes, SUM(COALESCE(topoc.usedquantity, 0)) + SUM(COALESCE(topoc.wastesquantity,0)) AS doneQuantity, DATE(date_trunc('day',pt.timerangefrom)) AS timeRangeFrom, DATE(date_trunc('day',pt.timerangeto)) AS timeRangeTo, shift.name AS shiftName, tcontext.number AS technologyGeneratorNumber FROM productioncounting_trackingoperationproductoutcomponent topoc JOIN productioncounting_productiontracking pt ON pt.id = topoc.productiontracking_id JOIN orders_order ord ON ord.id = pt.order_id JOIN basic_product product ON topoc.product_id = product.id JOIN technologies_technology technology ON technology.id = ord.technologyprototype_id LEFT JOIN basic_shift shift ON pt.shift_id = shift.id LEFT JOIN basic_assortment assortment ON product.assortment_id = assortment.id LEFT JOIN productionlines_productionline pl ON ord.productionline_id = pl.id LEFT JOIN basic_company c ON c.id = ord.company_id LEFT JOIN technologiesgenerator_generatortechnologiesforproduct tgenn ON technology.id = tgenn.technology_id LEFT JOIN technologiesgenerator_generatorcontext tcontext ON tcontext.id = tgenn.generatorcontext_id WHERE ord.parent_id IS NULL AND (product.id = ord.product_id OR (pt.technologyoperationcomponent_id IS NOT NULL AND topoc.typeofmaterial = '02intermediate')) GROUP BY ord.number, shift.name, date_trunc('day',pt.timerangefrom), date_trunc('day',pt.timerangeto), productionLineNumber, companyNumber, assortmentName, productNumber, productName, productUnit, size, technologyGeneratorNumber;

-- end


-- TRIGGER: assignmenttoshift_assignmenttoshift

CREATE SEQUENCE assignmenttoshift_assignmenttoshift_externalnumber_seq;

CREATE OR REPLACE FUNCTION generate_assignmenttoshift_externalnumber() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _externalnumber text; BEGIN _pattern := '#seq'; SELECT nextval('assignmenttoshift_assignmenttoshift_externalnumber_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); if _seq like '%#%' then _seq := _sequence_value; END IF; _externalnumber := _pattern; _externalnumber := replace(_externalnumber, '#seq', _seq); RETURN _externalnumber; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_assignmenttoshift_externalnumber_trigger() RETURNS trigger AS $$ BEGIN NEW.externalnumber := generate_assignmenttoshift_externalnumber(); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER assignmenttoshift_assignmenttoshift_trigger_externalnumber BEFORE INSERT ON assignmenttoshift_assignmenttoshift FOR EACH ROW EXECUTE PROCEDURE generate_and_set_assignmenttoshift_externalnumber_trigger();

-- end


-- TRIGGER: goodfood_pallet

CREATE SEQUENCE goodfood_pallet_externalnumber_seq;

CREATE OR REPLACE FUNCTION generate_pallet_externalnumber() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _externalnumber text; BEGIN _pattern := '#seq'; SELECT nextval('goodfood_pallet_externalnumber_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); if _seq like '%#%' then _seq := _sequence_value; END IF; _externalnumber := _pattern; _externalnumber := replace(_externalnumber, '#seq', _seq); RETURN _externalnumber; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_pallet_externalnumber_trigger() RETURNS trigger AS $$ BEGIN NEW.externalnumber := generate_pallet_externalnumber(); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER goodfood_pallet_trigger_externalnumber BEFORE INSERT ON goodfood_pallet FOR EACH ROW EXECUTE PROCEDURE generate_and_set_pallet_externalnumber_trigger();

-- end


-- TRIGGER: goodfood_confectionprotocol


CREATE SEQUENCE goodfood_confectionprotocol_externalnumber_seq;

CREATE OR REPLACE FUNCTION generate_confectionprotocol_externalnumber() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _externalnumber text; BEGIN _pattern := '#seq'; SELECT nextval('goodfood_confectionprotocol_externalnumber_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); if _seq like '%#%' then _seq := _sequence_value; END IF; _externalnumber := _pattern; _externalnumber := replace(_externalnumber, '#seq', _seq); RETURN _externalnumber; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_confectionprotocol_externalnumber_trigger() RETURNS trigger AS $$ BEGIN NEW.externalnumber := generate_confectionprotocol_externalnumber(); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER goodfood_confectionprotocol_trigger_externalnumber BEFORE INSERT ON goodfood_confectionprotocol FOR EACH ROW EXECUTE PROCEDURE generate_and_set_confectionprotocol_externalnumber_trigger();

-- end


-- TRIGGER: goodfood_extrusionprotocol

CREATE SEQUENCE goodfood_extrusionprotocol_externalnumber_seq;

CREATE OR REPLACE FUNCTION generate_extrusionprotocol_externalnumber() RETURNS text AS $$ DECLARE _pattern text; _sequence_name text; _sequence_value numeric; _tmp text; _seq text; _externalnumber text; BEGIN _pattern := '#seq'; SELECT nextval('goodfood_extrusionprotocol_externalnumber_seq') INTO _sequence_value; _seq := to_char(_sequence_value, 'fm000000'); if _seq like '%#%' then _seq := _sequence_value; END IF; _externalnumber := _pattern; _externalnumber := replace(_externalnumber, '#seq', _seq); RETURN _externalnumber; END; $$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION generate_and_set_extrusionprotocol_externalnumber_trigger() RETURNS trigger AS $$ BEGIN NEW.externalnumber := generate_extrusionprotocol_externalnumber(); RETURN NEW; END; $$ LANGUAGE 'plpgsql';

CREATE TRIGGER goodfood_extrusionprotocol_trigger_externalnumber BEFORE INSERT ON goodfood_extrusionprotocol FOR EACH ROW EXECUTE PROCEDURE generate_and_set_extrusionprotocol_externalnumber_trigger();

-- end


-- VIEW: materialflowresources_palletstoragestatedetailsdto

DROP TABLE IF EXISTS materialflowresources_palletstoragestatedetailsdto;

CREATE OR REPLACE VIEW materialflowresources_palletstoragestatedetailsdto AS SELECT resource.id AS id, TRUE AS active, resource.number AS resourcenumber, product.number AS productnumber, product.name AS productname, additionalcode.code AS additionalcode, resource.quantity, product.unit, resource.quantityinadditionalunit AS additionalquantity, resource.givenunit AS additionalunit, resource.expirationdate, palletnumber.number AS palletnumber, resource.typeofpallet, storagelocation.number AS storagelocationnumber, location.number AS locationnumber FROM materialflowresources_resource resource LEFT JOIN basic_product product ON product.id = resource.product_id LEFT JOIN basic_additionalcode additionalcode ON additionalcode.id = resource.additionalcode_id LEFT JOIN basic_palletnumber palletnumber ON palletnumber.id = resource.palletnumber_id LEFT JOIN materialflowresources_storagelocation storagelocation ON storagelocation.id = resource.storagelocation_id LEFT JOIN materialflow_location location ON location.id = resource.location_id WHERE resource.palletnumber_id IS NOT NULL ORDER BY palletnumber.number;

-- end


-- VIEW: materialflowresources_palletstoragestatedto

DROP TABLE IF EXISTS materialflowresources_palletstoragestatedto;

CREATE OR REPLACE VIEW materialflowresources_palletstoragestatedto AS SELECT ROW_NUMBER() OVER () AS id, TRUE AS active, palletstoragestatedetails.palletnumber, palletstoragestatedetails.typeofpallet, palletstoragestatedetails.storagelocationnumber, palletstoragestatedetails.locationnumber, SUM(palletstoragestatedetails.quantity)::NUMERIC(14,5) AS totalquantity FROM materialflowresources_palletstoragestatedetailsdto palletstoragestatedetails GROUP BY palletstoragestatedetails.palletnumber, palletstoragestatedetails.typeofpallet, palletstoragestatedetails.storagelocationnumber, palletstoragestatedetails.locationnumber ORDER BY palletstoragestatedetails.palletnumber, palletstoragestatedetails.locationnumber;

-- end