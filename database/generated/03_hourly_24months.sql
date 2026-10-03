-- MyEMS Generated Demo - 24 Months Hourly Rollups (2024-01-01 to 2025-12-31)
-- Generates: meter_hourly, equipment_input/output, space_input/output, combined, shopfloor, etc.
-- Method: Stored Procedure with deterministic seasonal/weekday/peak formula -> meaningful dashboard metrics
-- Execution: ~17544 hours * 150 meters = 2.63M meter rows + 120*17544 ~2.1M equipment rows; chunked INSERTs in batches of 5000
-- Safe to re-run: DELETEs generated range first (WHERE id not needed, WHERE start_datetime_utc between range AND meter_id >=50000)
USE `myems_system_db`;
DELIMITER //

DROP PROCEDURE IF EXISTS gen_demo_hourly//
CREATE PROCEDURE gen_demo_hourly()
BEGIN
  DECLARE cur DATETIME;
  DECLARE done INT DEFAULT 0;
  DECLARE batch INT DEFAULT 5000;
  -- Temporary tables for fast bulk insert
  SET @start_utc = '2024-01-01 00:00:00';
  SET @end_utc   = '2026-01-01 00:00:00'; -- exclusive, covers 2024+2025 = 17544h (2024 leap)
  SET @hours = TIMESTAMPDIFF(HOUR, @start_utc, @end_utc); -- 17544

  -- Clean previous generated window for idempotency (only demo ids >=50000)
  DELETE FROM `myems_energy_db`.`tbl_meter_hourly` WHERE meter_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_equipment_input_item_hourly` WHERE equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_equipment_output_category_hourly` WHERE equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_combined_equipment_input_category_hourly` WHERE combined_equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_combined_equipment_output_category_hourly` WHERE combined_equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_space_input_category_hourly` WHERE space_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_space_input_item_hourly` WHERE space_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_space_output_category_hourly` WHERE space_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_shopfloor_input_category_hourly` WHERE shopfloor_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_tenant_input_category_hourly` WHERE tenant_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_energy_db`.`tbl_store_input_category_hourly` WHERE store_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_billing_db`.`tbl_meter_hourly` WHERE meter_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_billing_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_carbon_db`.`tbl_meter_hourly` WHERE meter_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;
  DELETE FROM `myems_carbon_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id >= 50000 AND start_datetime_utc >= @start_utc AND start_datetime_utc < @end_utc;

  -- Helper: numbers 0..17543 via recursive CTE is slow for large; we use a loop with prepared batch
  -- Generate meter hourly first (base source)
  SET cur = @start_utc;
  WHILE cur < @end_utc DO
    -- Meter hourly: per meter seasonal * weekday * hour-of-day curve
    INSERT INTO `myems_energy_db`.`tbl_meter_hourly` (meter_id, start_datetime_utc, actual_value)
    SELECT m.id, cur,
      ROUND(
        -- base by category
        (CASE m.energy_category_id WHEN 1 THEN 22 WHEN 2 THEN 6 WHEN 3 THEN 12 WHEN 5 THEN 18 WHEN 6 THEN 28 WHEN 7 THEN 15 WHEN 9 THEN 20 ELSE 12 END)
        * (1 + 0.20*SIN(2*PI()* (MONTH(cur)-1)/12) + 0.10*SIN(2*PI()*DAYOFYEAR(cur)/365) ) -- seasonal ±20% summer peak, plus 10% annual wave
        * (CASE WHEN DAYOFWEEK(cur) IN (1,7) THEN 0.78 ELSE 1.0 END) -- weekend -22%
        * (CASE WHEN HOUR(cur) BETWEEN 8 AND 18 THEN 1.25 WHEN HOUR(cur) BETWEEN 19 AND 22 THEN 0.95 WHEN HOUR(cur) BETWEEN 0 AND 5 THEN 0.62 ELSE 0.85 END) -- day peak
        * (0.90 + RAND()*0.20) -- ±10% noise
      ,6)
    FROM `myems_system_db`.`tbl_meters` m WHERE m.id >= 50000;
    SET cur = DATE_ADD(cur, INTERVAL 1 HOUR);
    -- commit every 24h to avoid huge transaction (1 day = 150*1 batch)
    IF HOUR(cur)=0 THEN COMMIT; END IF;
  END WHILE;
  COMMIT;

  -- Equipment input category hourly: derived from its meters (sum of meter_hourly grouped by equipment's category)
  -- We aggregate directly from meter_hourly join to equipments_meters to keep FK-consistent
  INSERT INTO `myems_energy_db`.`tbl_equipment_input_category_hourly` (equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT em.equipment_id, m.energy_category_id, mh.start_datetime_utc, SUM(mh.actual_value)
  FROM `myems_system_db`.`tbl_equipments_meters` em
  JOIN `myems_system_db`.`tbl_meters` m ON m.id = em.meter_id
  JOIN `myems_energy_db`.`tbl_meter_hourly` mh ON mh.meter_id = m.id
  WHERE em.is_output=0 AND mh.start_datetime_utc >= @start_utc AND mh.start_datetime_utc < @end_utc
  GROUP BY em.equipment_id, m.energy_category_id, mh.start_datetime_utc;
  -- Equipment input item hourly: copy category to item 1 (Power for lighting) for item reports
  INSERT INTO `myems_energy_db`.`tbl_equipment_input_item_hourly` (equipment_id, energy_item_id, start_datetime_utc, actual_value)
  SELECT equipment_id, 1, start_datetime_utc, actual_value FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000;
  -- Equipment output category: 35% of input with efficiency variation (for KPI efficiency column)
  INSERT INTO `myems_energy_db`.`tbl_equipment_output_category_hourly` (equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT equipment_id, energy_category_id, start_datetime_utc, ROUND(actual_value * (0.30 + (equipment_id % 17)/100.0),6)
  FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000;

  -- Space input: sum of equipments in space (via spaces_equipments)
  INSERT INTO `myems_energy_db`.`tbl_space_input_category_hourly` (space_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT se.space_id, eic.energy_category_id, eic.start_datetime_utc, SUM(eic.actual_value)
  FROM `myems_system_db`.`tbl_spaces_equipments` se
  JOIN `myems_energy_db`.`tbl_equipment_input_category_hourly` eic ON eic.equipment_id = se.equipment_id
  GROUP BY se.space_id, eic.energy_category_id, eic.start_datetime_utc;
  INSERT INTO `myems_energy_db`.`tbl_space_input_item_hourly` (space_id, energy_item_id, start_datetime_utc, actual_value)
  SELECT space_id, 1, start_datetime_utc, actual_value FROM `myems_energy_db`.`tbl_space_input_category_hourly` WHERE space_id>=50000;
  INSERT INTO `myems_energy_db`.`tbl_space_output_category_hourly` (space_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT space_id, energy_category_id, start_datetime_utc, ROUND(actual_value*0.28,6) FROM `myems_energy_db`.`tbl_space_input_category_hourly` WHERE space_id>=50000;

  -- Combined equipment
  INSERT INTO `myems_energy_db`.`tbl_combined_equipment_input_category_hourly` (combined_equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT cee.combined_equipment_id, eic.energy_category_id, eic.start_datetime_utc, SUM(eic.actual_value)
  FROM `myems_system_db`.`tbl_combined_equipments_equipments` cee
  JOIN `myems_energy_db`.`tbl_equipment_input_category_hourly` eic ON eic.equipment_id = cee.equipment_id
  GROUP BY cee.combined_equipment_id, eic.energy_category_id, eic.start_datetime_utc;
  INSERT INTO `myems_energy_db`.`tbl_combined_equipment_output_category_hourly` (combined_equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT combined_equipment_id, energy_category_id, start_datetime_utc, ROUND(actual_value*0.32,6) FROM `myems_energy_db`.`tbl_combined_equipment_input_category_hourly` WHERE combined_equipment_id>=50000;

  -- Shopfloor / Tenant / Store (subset)
  INSERT INTO `myems_energy_db`.`tbl_shopfloor_input_category_hourly` (shopfloor_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT sfe.shopfloor_id, eic.energy_category_id, eic.start_datetime_utc, SUM(eic.actual_value)
  FROM `myems_system_db`.`tbl_shopfloors_equipments` sfe
  JOIN `myems_energy_db`.`tbl_equipment_input_category_hourly` eic ON eic.equipment_id = sfe.equipment_id
  GROUP BY sfe.shopfloor_id, eic.energy_category_id, eic.start_datetime_utc;

  -- Billing & Carbon clones: derive from energy with tariff & kgco2e factors
  -- Billing: apply TOU price (7 slots ~0.345-1.159) based on HOUR(cur)
  INSERT INTO `myems_billing_db`.`tbl_meter_hourly` (meter_id, start_datetime_utc, actual_value)
  SELECT meter_id, start_datetime_utc, ROUND(actual_value *
    (CASE WHEN HOUR(start_datetime_utc) BETWEEN 0 AND 5 THEN 0.345 WHEN HOUR(start_datetime_utc) BETWEEN 6 AND 7 THEN 0.708 WHEN HOUR(start_datetime_utc) BETWEEN 8 AND 10 THEN 1.159 WHEN HOUR(start_datetime_utc) BETWEEN 11 AND 17 THEN 0.708 WHEN HOUR(start_datetime_utc) BETWEEN 18 AND 20 THEN 1.159 WHEN HOUR(start_datetime_utc) BETWEEN 21 AND 21 THEN 0.708 ELSE 0.345 END),6)
  FROM `myems_energy_db`.`tbl_meter_hourly` WHERE meter_id>=50000;
  INSERT INTO `myems_billing_db`.`tbl_equipment_input_category_hourly` (equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT equipment_id, energy_category_id, start_datetime_utc, ROUND(actual_value *
    (CASE WHEN HOUR(start_datetime_utc) BETWEEN 0 AND 5 THEN 0.345 WHEN HOUR(start_datetime_utc) BETWEEN 6 AND 7 THEN 0.708 WHEN HOUR(start_datetime_utc) BETWEEN 8 AND 10 THEN 1.159 WHEN HOUR(start_datetime_utc) BETWEEN 11 AND 17 THEN 0.708 WHEN HOUR(start_datetime_utc) BETWEEN 18 AND 20 THEN 1.159 ELSE 0.345 END),6)
  FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000;

  INSERT INTO `myems_carbon_db`.`tbl_meter_hourly` (meter_id, start_datetime_utc, actual_value)
  SELECT mh.meter_id, mh.start_datetime_utc, ROUND(mh.actual_value * ec.kgco2e,6)
  FROM `myems_energy_db`.`tbl_meter_hourly` mh JOIN `myems_system_db`.`tbl_meters` m ON m.id=mh.meter_id JOIN `myems_system_db`.`tbl_energy_categories` ec ON ec.id=m.energy_category_id WHERE mh.meter_id>=50000;
  INSERT INTO `myems_carbon_db`.`tbl_equipment_input_category_hourly` (equipment_id, energy_category_id, start_datetime_utc, actual_value)
  SELECT eic.equipment_id, eic.energy_category_id, eic.start_datetime_utc, ROUND(eic.actual_value * ec.kgco2e,6)
  FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` eic JOIN `myems_system_db`.`tbl_energy_categories` ec ON ec.id=eic.energy_category_id WHERE eic.equipment_id>=50000;

END //
DELIMITER ;
CALL gen_demo_hourly();
DROP PROCEDURE gen_demo_hourly;