#!/bin/bash
# MyEMS Demo Import - merge-safe
set -euo pipefail
# Usage: ./import.sh [mysql_host] [mysql_user] [mysql_pass]
# Defaults read from myems-api/config.py or env MYEMS_* vars
HOST=${1:-${MYEMS_SYSTEM_DB_HOST:-127.0.0.1}}
USER=${2:-${MYEMS_SYSTEM_DB_USER:-root}}
PASS=${3:-${MYEMS_SYSTEM_DB_PASSWORD:-}}
PORT=${MYEMS_SYSTEM_DB_PORT:-3306}

DIR="$(cd "$(dirname "$0")" && pwd)"

run() {
  local file=$1
  echo "==> Importing $file"
  # 03_hourly contains DELIMITER/procedure and needs a default DB (myems_system_db)
  # All files use fully-qualified tbl names so any DB works, but for procedure we force myems_system_db
  if [ -n "$PASS" ]; then
    mysql -h "$HOST" -P "$PORT" -u "$USER" -p"$PASS" --binary-mode myems_system_db < "$file"
  else
    mysql -h "$HOST" -P "$PORT" -u "$USER" --binary-mode myems_system_db < "$file"
  fi
}

echo "MyEMS Demo Import - offset 50000 (safe for existing data <50000)"
echo "Checking existing max IDs..."
# Preflight query (optional, prints warnings if collision risk)
if [ -n "$PASS" ]; then
  mysql -h "$HOST" -P "$PORT" -u "$USER" -p"$PASS" -e "SELECT 'equip' as tbl, COALESCE(MAX(id),0) as max_id FROM myems_system_db.tbl_equipments UNION ALL SELECT 'meter', COALESCE(MAX(id),0) FROM myems_system_db.tbl_meters UNION ALL SELECT 'space', COALESCE(MAX(id),0) FROM myems_system_db.tbl_spaces;"
else
  mysql -h "$HOST" -P "$PORT" -u "$USER" -e "SELECT 'equip' as tbl, COALESCE(MAX(id),0) as max_id FROM myems_system_db.tbl_equipments UNION ALL SELECT 'meter', COALESCE(MAX(id),0) FROM myems_system_db.tbl_meters UNION ALL SELECT 'space', COALESCE(MAX(id),0) FROM myems_system_db.tbl_spaces;"
fi

echo "Step 1: system masters (cost centers, spaces 58, points 50, meters 150, shopfloors/stores/tenants)"
run "$DIR/01_system_masters.sql"
echo "Step 2: equipments 120 + parameters + combined systems"
run "$DIR/02_equipments.sql"
echo "Step 3: 24 months hourly (this will take 5-20 minutes; 150 meters * 17544h = 2.6M rows + equip rollups)"
run "$DIR/03_hourly_24months.sql"
echo "Step 4: aux (billing/carbon clones, tenant/store, FDD faults, historical latest, demo user)"
run "$DIR/04_aux_billing_carbon_production_fdd.sql"

echo "=== Verification ==="
if [ -n "$PASS" ]; then
  mysql -h "$HOST" -P "$PORT" -u "$USER" -p"$PASS" -e "
    SELECT 'equipments demo' as check, COUNT(*) FROM myems_system_db.tbl_equipments WHERE id>=50000;
    SELECT 'meters demo' as check, COUNT(*) FROM myems_system_db.tbl_meters WHERE id>=50000;
    SELECT 'equipment hourly 2024' as check, COUNT(*) FROM myems_energy_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2024-02-01';
    SELECT 'billing sample' as check, SUM(actual_value) FROM myems_billing_db.tbl_equipment_input_category_hourly WHERE equipment_id=50001 AND start_datetime_utc>='2025-01-01' AND start_datetime_utc<'2025-02-01';
    SELECT 'carbon sample' as check, SUM(actual_value) FROM myems_carbon_db.tbl_equipment_input_category_hourly WHERE equipment_id=50001 AND start_datetime_utc>='2025-01-01' AND start_datetime_utc<'2025-02-01';
    SELECT CONCAT('equipmentdashboard: ', COUNT(*), ' equipments with data') FROM (SELECT DISTINCT equipment_id FROM myems_energy_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000) t;
  "
else
  mysql -h "$HOST" -P "$PORT" -u "$USER" -e "
    SELECT 'equipments demo' as check, COUNT(*) FROM myems_system_db.tbl_equipments WHERE id>=50000;
    SELECT 'meters demo' as check, COUNT(*) FROM myems_system_db.tbl_meters WHERE id>=50000;
    SELECT 'equipment hourly 2024' as check, COUNT(*) FROM myems_energy_db.tbl_equipment_input_category_hourly WHERE equipment_id>=50000 AND start_datetime_utc>='2024-01-01' AND start_datetime_utc<'2024-02-01';
  "
fi
echo "Done. Test dashboard: curl 'http://localhost:8000/api/equipmentdashboard?useruuid=<admin>&periodtype=monthly&reportingperiodstartdatetime=2025-01-01T00:00:00&reportingperiodenddatetime=2025-02-01T00:00:00'"
echo "Rollback if needed: mysql < 99_rollback.sql"
