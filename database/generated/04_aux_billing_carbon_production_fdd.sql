-- MyEMS Generated Demo - Billing/Carbon mirrors + Production + FDD + Historical Latest
-- Depends on 03_hourly_24months.sql having been run
SET FOREIGN_KEY_CHECKS=0;
-- FDD: ensure table exists before transaction (CREATE causes implicit COMMIT)
CREATE TABLE IF NOT EXISTS `myems_fdd_db`.`tbl_faults` (
  `id` BIGINT NOT NULL AUTO_INCREMENT, `rule_id` BIGINT, `equipment_id` BIGINT, `space_id` BIGINT, `status` VARCHAR(32), `priority` VARCHAR(32), `created_datetime_utc` DATETIME, PRIMARY KEY(`id`), INDEX(`equipment_id`), INDEX(`status`)
) ENGINE=InnoDB;
START TRANSACTION;
-- Tenant/Store hourly: via equipment allocation (derived from equipment rollups in 03_hourly)
-- Actually populate tenant/store via equipment allocation: use first 6 tenants each mapped to 5 equipments
DELETE FROM `myems_energy_db`.`tbl_tenant_input_category_hourly` WHERE tenant_id>=50000;
DELETE FROM `myems_energy_db`.`tbl_store_input_category_hourly` WHERE store_id>=50000;
INSERT INTO `myems_energy_db`.`tbl_tenant_input_category_hourly` (tenant_id, energy_category_id, start_datetime_utc, actual_value)
SELECT 50001, eic.energy_category_id, eic.start_datetime_utc, ROUND(SUM(eic.actual_value)*0.18,6)
FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` eic WHERE eic.equipment_id IN (50001,50002,50003,50004,50005) GROUP BY eic.energy_category_id, eic.start_datetime_utc;
INSERT INTO `myems_energy_db`.`tbl_tenant_input_category_hourly` (tenant_id, energy_category_id, start_datetime_utc, actual_value)
SELECT 50002, eic.energy_category_id, eic.start_datetime_utc, ROUND(SUM(eic.actual_value)*0.22,6) FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` eic WHERE eic.equipment_id IN (50006,50007,50008) GROUP BY eic.energy_category_id, eic.start_datetime_utc;
-- Stores similarly
INSERT INTO `myems_energy_db`.`tbl_store_input_category_hourly` (store_id, energy_category_id, start_datetime_utc, actual_value)
SELECT 50001, eic.energy_category_id, eic.start_datetime_utc, ROUND(SUM(eic.actual_value)*0.25,6) FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` eic WHERE eic.equipment_id IN (50010,50011) GROUP BY eic.energy_category_id, eic.start_datetime_utc;

-- Historical latest tables: populate latest values for point realtime dashboards (space/equipment reports pull from *_latest)
DELETE FROM `myems_historical_db`.`tbl_energy_value_latest` WHERE point_id>=50000;
DELETE FROM `myems_historical_db`.`tbl_analog_value_latest` WHERE point_id>=50000;
INSERT INTO `myems_historical_db`.`tbl_energy_value_latest` (point_id, utc_date_time, actual_value)
SELECT p.id, '2025-12-31 23:00:00', ROUND(50000 + RAND()*10000,2) FROM `myems_system_db`.`tbl_points` p WHERE p.id>=50000 AND p.object_type='ENERGY_VALUE' LIMIT 50;
INSERT INTO `myems_historical_db`.`tbl_analog_value_latest` (point_id, utc_date_time, actual_value)
SELECT p.id, '2025-12-31 23:00:00', ROUND(30 + RAND()*70,2) FROM `myems_system_db`.`tbl_points` p WHERE p.id>=50000 AND p.object_type='ANALOG_VALUE' LIMIT 50;

-- FDD faults: insert 5 active faults for top equipments to show alerts in equipmentdashboard (status='active')
DELETE FROM `myems_fdd_db`.`tbl_faults` WHERE equipment_id>=50000;
INSERT INTO `myems_fdd_db`.`tbl_faults` (`rule_id`,`equipment_id`,`space_id`,`status`,`priority`,`created_datetime_utc`) VALUES (1,50001,50001,'active','HIGH','2025-12-30 08:00:00'),(1,50005,50002,'active','MEDIUM','2025-12-29 14:00:00'),(1,50012,50003,'active','CRITICAL','2025-12-28 22:00:00'),(1,50020,50005,'acknowledged','LOW','2025-12-27 09:00:00'),(1,50033,50006,'active','MEDIUM','2025-12-26 11:00:00');

-- Production: equip hourly production (for equipmentoutput reports)
DELETE FROM `myems_production_db`.`tbl_equipment_hourly` WHERE equipment_id>=50000;
INSERT INTO `myems_production_db`.`tbl_equipment_hourly` (equipment_id, start_datetime_utc, product_id, product_count)
SELECT eic.equipment_id, eic.start_datetime_utc, 1, ROUND(eic.actual_value*0.5,2) FROM `myems_energy_db`.`tbl_equipment_input_category_hourly` eic WHERE eic.equipment_id IN (50001,50002,50003) AND eic.energy_category_id=1 LIMIT 1000;

-- User: ensure demo user can see demo spaces/equipments (update administrator privilege JSON if needed)
-- Non-destructive: create separate demo user if not exists
INSERT INTO `myems_user_db`.`tbl_privileges` (`id`,`name`,`data`) VALUES (50000,'Demo Viewer','{"spaces":[50001,50002],"equipments":[50001,50002,50003,50004,50005]}') ON DUPLICATE KEY UPDATE `name`=VALUES(`name`);
INSERT INTO `myems_user_db`.`tbl_users` (`id`,`name`,`uuid`,`display_name`,`email`,`phone`,`salt`,`password`,`is_admin`,`is_read_only`,`privilege_id`,`account_expiration_datetime_utc`,`password_expiration_datetime_utc`,`failed_login_count`) VALUES (50000,'demo_viewer','a0000000-0000-4000-a000-000000005000','Demo Viewer','demo@myems.local',NULL,'salt','pbkdf2_hash',0,0,50000,'2099-12-31 16:00:00','2099-12-31 16:00:00',0) ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `privilege_id`=VALUES(`privilege_id`);
COMMIT;