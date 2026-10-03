-- MyEMS Generated Demo - ROLLBACK (idempotent)
-- Deletes only demo offset >=50000 and date range 2024-01-01..2026-01-01
SET FOREIGN_KEY_CHECKS=0;
START TRANSACTION;
-- Energy DB
DELETE FROM `myems_energy_db`.`tbl_meter_hourly` WHERE meter_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_equipment_input_item_hourly` WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_equipment_output_category_hourly` WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_combined_equipment_input_category_hourly` WHERE combined_equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_combined_equipment_output_category_hourly` WHERE combined_equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_space_input_category_hourly` WHERE space_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_space_input_item_hourly` WHERE space_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_space_output_category_hourly` WHERE space_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_shopfloor_input_category_hourly` WHERE shopfloor_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_tenant_input_category_hourly` WHERE tenant_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_energy_db`.`tbl_store_input_category_hourly` WHERE store_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
-- Billing & Carbon
DELETE FROM `myems_billing_db`.`tbl_meter_hourly` WHERE meter_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_billing_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_carbon_db`.`tbl_meter_hourly` WHERE meter_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
DELETE FROM `myems_carbon_db`.`tbl_equipment_input_category_hourly` WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2026-01-01';
-- Historical latest
DELETE FROM `myems_historical_db`.`tbl_energy_value_latest` WHERE point_id>=50000;
DELETE FROM `myems_historical_db`.`tbl_analog_value_latest` WHERE point_id>=50000;
DELETE FROM `myems_fdd_db`.`tbl_faults` WHERE equipment_id>=50000;
DELETE FROM `myems_production_db`.`tbl_equipment_hourly` WHERE equipment_id>=50000;
-- System junctions (FK-safe order: children first)
DELETE FROM `myems_system_db`.`tbl_equipments_parameters` WHERE equipment_id>=50000;
DELETE FROM `myems_system_db`.`tbl_equipments_meters` WHERE equipment_id>=50000;
DELETE FROM `myems_system_db`.`tbl_combined_equipments_equipments` WHERE combined_equipment_id>=50000 OR equipment_id>=50000;
DELETE FROM `myems_system_db`.`tbl_combined_equipments_meters` WHERE combined_equipment_id>=50000;
DELETE FROM `myems_system_db`.`tbl_spaces_equipments` WHERE equipment_id>=50000 OR space_id>=50000;
DELETE FROM `myems_system_db`.`tbl_shopfloors_equipments` WHERE equipment_id>=50000 OR shopfloor_id>=50000;
DELETE FROM `myems_system_db`.`tbl_meters_points` WHERE meter_id>=50000;
-- Masters
DELETE FROM `myems_system_db`.`tbl_equipments` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_combined_equipments` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_meters` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_points` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_spaces` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_shopfloors` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_stores` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_tenants` WHERE id>=50000;
DELETE FROM `myems_system_db`.`tbl_svgs` WHERE id>=105;
DELETE FROM `myems_system_db`.`tbl_cost_centers` WHERE id>=102;
DELETE FROM `myems_system_db`.`tbl_tenants` WHERE id>=50000;
DELETE FROM `myems_user_db`.`tbl_users` WHERE id>=50000;
DELETE FROM `myems_user_db`.`tbl_privileges` WHERE id>=50000;
COMMIT;
-- Reset auto-increment (optional)
ALTER TABLE `myems_system_db`.`tbl_equipments` AUTO_INCREMENT = 1;