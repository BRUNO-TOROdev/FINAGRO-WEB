"""Run FINAGRO SQL integration tests against Supabase local."""

from pathlib import Path
import sys

import psycopg


ROOT = Path(__file__).resolve().parent.parent
DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
TEST_FILES = (
    ROOT / "tests" / "business_invariants_smoke.sql",
    ROOT / "tests" / "p0_foundation.sql",
    ROOT / "tests" / "app_foundation_security.sql",
    ROOT / "tests" / "configuration_modules.sql",
)


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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
