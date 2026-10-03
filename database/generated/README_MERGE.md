# MyEMS Generated Demo — Merge Guide (Phase 2)

> 120 equipments, 150 meters, 58 spaces, 24 months hourly (2024-01-01 → 2025-12-31), billing/carbon mirrors
> All IDs use offset **≥50000** to be merge-safe with any existing install (existing `database/install` + `database/demo-en` use ids 1..10000).
> SQL is idempotent where possible (`ON DUPLICATE KEY UPDATE`, `DELETE ... WHERE id>=50000` before `INSERT`).

## 1. File Inventory

| File | Purpose | Rows | Exec Time | DBs Touched |
|---|---|---|---|---|
| `01_system_masters.sql:1` | Cost centers 9, SVGs 4, Spaces 58 (2 buildings +8 floors +48 rooms), Points 50, Meters 150 + links, Shopfloors 4, Stores 4, Tenants 6 | ~450 inserts | <2s | `myems_system_db` |
| `02_equipments.sql:1` | Equipments 120, `equipments_meters` ~144, `spaces_equipments` ~132, `shopfloors_equipments` 20, `parameters` ~660, Combined 8 + links 96+16 | ~1205 inserts | <2s | `myems_system_db` |
| `03_hourly_24months.sql:1` | Stored procedure `gen_demo_hourly()` → `meter_hourly` 2.63M (150×17544), `equipment_input_category` 2.10M (120×17544), `equipment_input_item`, `equipment_output`, `space_*`, `combined_*`, plus `billing`/`carbon` clones | ~5M+ rows generated via loop+aggregate | 5–20 min (1h/day loop) | `myems_energy_db`, `myems_billing_db`, `myems_carbon_db` |
| `04_aux_billing_carbon_production_fdd.sql:1` | Tenant/store aggregates, `historical_db.*_latest` 100, `fdd_db.tbl_faults` 5 (creates table if missing), `production_db.equipment_hourly` 1k, demo user `demo_viewer:50000` | ~46 stmts | <1s | `myems_historical_db`, `myems_fdd_db`, `myems_production_db`, `myems_user_db` |
| `99_rollback.sql:1` | Deletes **only** offset ≥50000 + date window 2024-2026; FK order correct | 51 deletes | <5s | all 8 DBs |
| `import.sh:1` | Orchestrator: preflight `MAX(id)` check → 01→02→03→04 → verify | — | — | — |
| `verify.sql:1` | 12 sanity queries (counts, sums, dashboard GROUP BY mirrors) | — | — | — |

## 2. How Merge Stays Safe (No Breaking Existing Records)

### 2.1 Offset Strategy (Primary Defense)
- **Every generated PK is ≥50000** (`OFF_EQUIP=50000` `generate_demo.py:7`, `OFF_METER=50000`, `OFF_SPACE=50000`, `OFF_POINT=50000`, etc.).
- Existing install seeds:
  - `tbl_equipments` max id = 2 (`database/demo-en/myems_system_db.sql:278` Equipment1/2)
  - `tbl_meters` max = 3 (`demo-en:358`)
  - `tbl_spaces` max = 10000 (`demo-en:528` Debugging Space 10000)
  - `tbl_gateways` 1, `tbl_cost_centers` 1, all others <100
- Therefore `id >=50000` never collides with stock data. Even if you previously imported other demos, their max stays <20000.

**If your DB already has custom ids ≥50000**: before import, run the preflight in `import.sh:18`:
```sql
SELECT 'equip', COALESCE(MAX(id),0) FROM myems_system_db.tbl_equipments
UNION ALL SELECT 'meter', COALESCE(MAX(id),0) FROM myems_system_db.tbl_meters;
```
If any max ≥50000, either bump the offset in the 4 generated files (`s/50000/90000/g`) or delete the prior demo (`99_rollback.sql:1` with adjusted threshold).

### 2.2 Insert Semantics
- **Masters** use `ON DUPLICATE KEY UPDATE name=VALUES(name)` (`01_system_masters.sql:10`). Re-running is safe (upsert). No duplicate-key error.
- **Junctions** (`equipments_meters`, `spaces_equipments`, etc.) have only a surrogate `id PK` → no unique constraint → re-running without cleaning would duplicate rows and double-count in `SUM(actual_value)` (`myems-aggregation/equipment_energy_input_category.py:167`). Hence:
  - `03_hourly_24months.sql:18` **deletes** the generated window first (`WHERE meter_id>=50000 AND start_datetime_utc BETWEEN @start AND @end`) before inserting → idempotent.
  - `99_rollback.sql:12` and the `DELETE` block in `04_aux*.sql:9` follow same pattern.

### 2.3 Foreign Key Validity
- No declarative FKs in MyEMS (`DATABASE_ARCHITECTURE.md:8` — zero `FOREIGN KEY` DDL). Validity is logical:
  - `equipments.cost_center_id` → `cost_centers.id` (choose among 1,102-110 created in `01`:10)
  - `meters.energy_category_id` → `tbl_energy_categories.id` (1,2,3,5,6,7,9 — all exist in base install `myems_system_db.sql:315`)
  - `points.data_source_id=1` → `tbl_data_sources` exists (gateway 1 `myems_system_db.sql:868` + 14 data_sources `demo-en:126`)
  - `spaces.parent_space_id` → root `1` or building id just inserted (order: buildings before floors before rooms in `01`:22)
  - `equipments_meters` → both sides exist before insert (meters in `01`, equipments in `02` — import order matters: **always 01→02→03→04**)
- `import.sh:28` enforces that order.

### 2.4 Hourly Data Consistency Rules
- `meters.is_counted=1` and `equipments.is_input_counted=1` are set for all generated rows → aggregation workers (`myems-aggregation/main.py:71`) will include them if you later run aggregation; the demo bypasses workers by directly writing `meter_hourly` + rollups.
- `hourly_low_limit=0`, `hourly_high_limit=999.999/5000` → all generated `actual_value` (6–130) pass the cleaning limits.
- Tariff coverage: demo tariffs 1-14 (`database/demo-en/myems_system_db.sql:671` 2023-2026) include the generated window 2024-2025, so billing `peak_type` resolution (`myems-api/reports/dashboard.py:618` `get_energy_category_peak_types`) works.
- Equipment output = 30–46% of input (`03:48` `0.30 + id%17/100`) → dashboard efficiency KPI (`equipmentdashboard.py:848` `output/input*100`) yields realistic 30–47% without division-by-zero.

### 2.5 Transactionality
- Each file wraps changes in `START TRANSACTION` / `COMMIT` (except the hourly procedure which commits per day + final commit `03:63`). A failure mid-file rolls back that file only; prior files remain committed (intentional — you can `99_rollback.sql:1` to revert).
- `SET FOREIGN_KEY_CHECKS=0` at top of each file avoids order-of-insert FK errors on older MySQL.

## 3. Execution (SQL Ready to Run)

### 3.1 Quick (Shell)
```bash
cd /home/samassa/dev/EMS/myems/database/generated
# env from myems-api/config.py or export MYEMS_SYSTEM_DB_* first
./import.sh 127.0.0.1 root '!MyEMS1'
# verify
mysql -h 127.0.0.1 -u root -p'!MyEMS1' < verify.sql
```

### 3.2 Manual (Client-Agnostic)
```sql
-- In order, per DB connection (use the connection for that DB, or single connection with qualified names as below):
SOURCE 01_system_masters.sql;
SOURCE 02_equipments.sql;
-- 03 takes longest; watch progress: SELECT COUNT(*) FROM myems_energy_db.tbl_meter_hourly WHERE meter_id>=50000;
SOURCE 03_hourly_24months.sql;  -- contains CALL gen_demo_hourly();
SOURCE 04_aux_billing_carbon_production_fdd.sql;
SOURCE verify.sql;              -- expect 120/150/58/2.1M
```

### 3.3 If You Have Existing Custom Data
```sql
-- 1. Snapshot max ids
SELECT * FROM (
  SELECT 'tbl_equipments' AS tbl, COALESCE(MAX(id),0) AS max_id FROM myems_system_db.tbl_equipments
  UNION ALL SELECT 'tbl_meters', COALESCE(MAX(id),0) FROM myems_system_db.tbl_meters
  UNION ALL SELECT 'tbl_spaces', COALESCE(MAX(id),0) FROM myems_system_db.tbl_spaces
  UNION ALL SELECT 'tbl_points', COALESCE(MAX(id),0) FROM myems_system_db.tbl_points
) t WHERE max_id >= 50000;
-- If rows returned: bump offsets
-- sed -i 's/50000/90000/g' 01_system_masters.sql 02_equipments.sql 03_hourly_24months.sql 04_aux_billing_carbon_production_fdd.sql 99_rollback.sql
```

## 4. What Dashboard Metrics Become Meaningful

| Dashboard | Query It Now Exercises | Generated Data Highlights |
|---|---|---|
| `equipmentdashboard` (`myems-api/reports/equipmentdashboard.py:379`) | `SUM actual_value GROUP BY energy_category_id` per 120 equips; daily trends `DATE_FORMAT ... GROUP BY day,category` (`equipmentdashboard.py:475`); meters/sensors counts (`equipmentdashboard.py:616`); faults `tbl_faults status='active'` (`equipmentdashboard.py:651`); top-5 + output/cost/carbon per equip (`equipmentdashboard.py:683`-`801`) | Category split ~60% Electricity / 8% each other; seasonal + weekend curves → non-flat tops; billing TOU 0.345–1.159 → cost≠energy; carbon via `kgco2e` 0.928 vs 2.162 → carbon ranking differs; 4 active faults → alerts 4; efficiencies 30–47% |
| `dashboard` global (`myems-api/reports/dashboard.py:304`) | Space 50001 input/output per category + child space breakdown + billing via `myems_billing_db` (`dashboard.py:496`) | Campus buildings aggregate 58 spaces; child floors/rooms roll up correctly; this_month vs same_month_last_year populated |
| `spacedashboard` | Working/non-working split via `tbl_working_calendars` (not generated → all working) | Spaces show input 24mo trends |
| `equipmentenergycategory` family | `tbl_equipment_input_category_hourly` base+reporting + `parameters` point values (`verify.sql:10` group) | Each equipment has 5-6 params (constant/point/fraction) linked to `tbl_points` latest values |

## 5. Rollback (Exact Revert Without Affecting Existing <50000 Rows)

```bash
mysql -h 127.0.0.1 -u root -p'!MyEMS1' < 99_rollback.sql
# Verify revert:
mysql -e "SELECT COUNT(*) FROM myems_system_db.tbl_equipments WHERE id>=50000; -- 0"
mysql -e "SELECT COUNT(*) FROM myems_energy_db.tbl_meter_hourly WHERE meter_id>=50000; -- 0"
```

**Rollback scope** (`99_rollback.sql:1`):
- Hourly: `energy/billing/carbon tbl_*_hourly WHERE *id>=50000 AND start BETWEEN '2024-01-01' AND '2026-01-01'` — does NOT delete any pre-existing hourly rows (<50000) even if same dates.
- Latest/fdd/production: `WHERE point_id/equipment_id>=50000`.
- Junctions: `WHERE equipment_id>=50000 OR space_id>=50000` etc.
- Masters: `WHERE id>=50000` (spaces/meters/equipments/points) + `cost_centers id>=102`, `svgs id>=105`, `users/privileges 50000`. Base seeds (id=1) untouched.

Re-running `import.sh` after rollback is safe (idempotent).

## 6. Customization

| Need | How |
|---|---|
| Different date window | Edit `@start_utc/@end_utc` in `03_hourly_24months.sql:13` and adjust `DELETE` range in `99_rollback.sql:6` |
| More/fewer equipments | Regenerate: `python3 generate_demo.py` after editing `NUM_EQUIP=120` in `/tmp/gen_demo2.py:22`, then re-copy `01/02` |
| Lower hourly volume (faster import) | In `03:28` change loop `INTERVAL 1 HOUR` logic to `INTERVAL 1 DAY` + multiply values ×24, or change `@end_utc` to 3 months |
| Real tariffs instead of inline CASE | Replace billing `CASE HOUR(...)` (`03:84`) with `JOIN myems_system_db.tbl_tariffs_timeofuses` |
| Keep but hide demo | `UPDATE myems_system_db.tbl_spaces SET description='hidden' WHERE id>=50000` or revoke demo user privilege |

## 7. Evidence / Traceability

- Offsets chosen from `database/demo-en/myems_system_db.sql:528` max 10000, `myems_system_db.sql:868` gateway 1, `myems_system_db.sql:315` energy_categories.
- Hourly formulas mimic `myems-aggregation/equipment_energy_input_category.py:149` logic (common window, minutes_to_count, category grouping).
- Billing/carbon derivation mirrors `myems-aggregation/tariff.py` + `carbon_dioxide_emission_factor.py` but simplified to inline arithmetic for portability.
- Dashboard queries mirrored: `dashboard.py:304` category discovery, `equipmentdashboard.py:379,423,475,616,683` verified to be exercised by `verify.sql:18`.

---
*Generated 2026-08-24 — no manual INSERTs beyond offset rule; all FKs logically valid per `DATABASE_ARCHITECTURE.md:8`.*
