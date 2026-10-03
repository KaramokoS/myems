-- Verification queries for generated demo (run after import.sh)
SELECT '01_equip count' AS test, COUNT(*) AS result FROM myems_system_db.tbl_equipments WHERE id>=50000; -- expect 120
SELECT '02_meter count' AS test, COUNT(*) FROM myems_system_db.tbl_meters WHERE id>=50000; -- 150
SELECT '03_space count' AS test, COUNT(*) FROM myems_system_db.tbl_spaces WHERE id>=50000; -- 58 (2+8+48)
SELECT '04_equipment_meter links' AS test, COUNT(*) FROM myems_system_db.tbl_equipments_meters WHERE equipment_id>=50000; -- ~144
SELECT '05_meter_hourly months' AS test, COUNT(*) FROM myems_energy_db.tbl_meter_hourly WHERE meter_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2024-02-01'; -- 150*744=111600
SELECT '06_equipment_hourly 24mo' AS test, COUNT(*) FROM myems_energy_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000; -- ~2.1M (120*17544)
SELECT '07_space_hourly' AS test, COUNT(*) FROM myems_energy_db.tbl_space_input_category_hourly WHERE space_id>=50000 LIMIT 1; -- >0
SELECT '08_billing not zero' AS test, SUM(actual_value) FROM myems_billing_db.tbl_equipment_input_category_hourly WHERE equipment_id=50001 AND start_datetime_utc>='2025-06-01' AND start_datetime_utc<'2025-07-01';
SELECT '09_carbon not zero' AS test, SUM(actual_value) FROM myems_carbon_db.tbl_equipment_input_category_hourly WHERE equipment_id=50001 AND start_datetime_utc>='2025-06-01' AND start_datetime_utc<'2025-07-01';
SELECT '10_equipment efficiency range' AS test, MIN(efficiency_indicator), MAX(efficiency_indicator) FROM myems_system_db.tbl_equipments WHERE id>=50000;
SELECT '11_FDD faults' AS test, COUNT(*) FROM myems_fdd_db.tbl_faults WHERE equipment_id>=50000 AND status='active'; -- 4
SELECT '12_demo user' AS test, COUNT(*) FROM myems_user_db.tbl_users WHERE id=50000;
-- Dashboard sanity: these two queries are what equipmentdashboard.py:379 and billing:423 execute
SELECT energy_category_id, SUM(actual_value) AS total_kwh FROM myems_energy_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000 AND start_datetime_utc>='2025-01-01' AND start_datetime_utc<'2025-02-01' GROUP BY energy_category_id;
SELECT energy_category_id, SUM(actual_value) AS total_cost FROM myems_billing_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000 AND start_datetime_utc>='2025-01-01' AND start_datetime_utc<'2025-02-01' GROUP BY energy_category_id;
