"""Run FINAGRO SQL integration tests against Supabase local."""

from pathlib import Path
import json
import sys

import psycopg


ROOT = Path(__file__).resolve().parent.parent
DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
TEST_FILES = (
    ROOT / "tests" / "business_invariants_smoke.sql",
    ROOT / "tests" / "p0_foundation.sql",
    ROOT / "tests" / "app_foundation_security.sql",
    ROOT / "tests" / "configuration_modules.sql",
    ROOT / "tests" / "finagro_chart_template.sql",
)


def verify_canonical_template() -> None:
    canonical = json.loads((ROOT / "docs" / "data" / "finagro-chart-template-v1.json").read_text(encoding="utf-8"))
    expected = sorted(canonical["items"], key=lambda item: item["code"])
    with psycopg.connect(DATABASE_URL) as connection:
        rows = connection.execute(
            """select id::text,parent_item_id::text,code,name,managerial_type,nature,
                      participates_dre,participates_cashflow,requires_farm,allows_allocation,
                      requires_crop_season,display_order,source_name,source_type,source_origin,source_aliases
                 from public.chart_account_template_items
                where template_id=%s order by code""",
            (canonical["template"]["id"],),
        ).fetchall()
    actual = [
        {
            "id": row[0], "parent_id": row[1], "code": row[2], "display_name": row[3],
            "managerial_type": row[4], "nature": row[5], "participates_dre": row[6],
            "participates_cashflow": row[7], "requires_farm": row[8], "allows_allocation": row[9],
            "requires_crop_season": row[10], "display_order": row[11], "source_name": row[12],
            "source_type": row[13], "source_origin": row[14], "source_aliases": row[15],
        }
        for row in rows
    ]
    comparable = [
        {key: item[key] for key in actual[0].keys()}
        for item in expected
    ] if actual else []
    if actual != comparable:
        raise AssertionError("database template differs from the canonical FINAGRO JSON")


def main() -> int:
    for test_file in TEST_FILES:
        sql = test_file.read_text(encoding="utf-8")
        try:
            with psycopg.connect(DATABASE_URL) as connection:
                connection.execute(sql)
        except Exception as error:  # PostgreSQL error detail is the test report.
            print(f"FAIL {test_file.name}: {error}", file=sys.stderr)
            return 1
        print(f"PASS {test_file.name}")
    try:
        verify_canonical_template()
    except Exception as error:
        print(f"FAIL finagro-chart-template-v1.json: {error}", file=sys.stderr)
        return 1
    print("PASS finagro-chart-template-v1.json (154 exact records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
