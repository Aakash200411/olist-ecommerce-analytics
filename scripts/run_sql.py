"""
run_sql.py : run the analysis SQL files against the DuckDB database and
save every named query's result to outputs/results/<file>__<query>.csv

Each .sql file is split into blocks by lines of the form:
    -- name: some_query_name
Usage:
    python scripts/run_sql.py                 # run all numbered files
    python scripts/run_sql.py sql/03_*.sql    # run specific files
    python scripts/run_sql.py sql/03_*.sql --show   # also print results
"""
import re, sys
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "olist.duckdb"
OUT = ROOT / "outputs" / "results"

def split_blocks(text):
    parts = re.split(r"^-- name:\s*(\S+)\s*$", text, flags=re.M)
    # parts = [preamble, name1, body1, name2, body2, ...]
    return [(parts[i], parts[i + 1].strip()) for i in range(1, len(parts), 2)]

def main(argv):
    show = "--show" in argv
    files = [Path(a) for a in argv if not a.startswith("--")]
    if not files:
        files = sorted((ROOT / "sql").glob("0[1-9]_*.sql"))
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB))
    for f in files:
        text = f.read_text()
        blocks = split_blocks(text)
        if not blocks:                      # a file with no named blocks (e.g. views)
            con.execute(text)
            print(f"[{f.name}] executed")
            continue
        for name, body in blocks:
            body = body.rstrip().rstrip(";")
            first = next((l for l in body.splitlines() if not l.strip().startswith("--") and l.strip()), "")
            if first.upper().startswith(("CREATE", "DROP")):
                con.execute(body)
                print(f"[{f.name}] {name}: created")
                continue
            df = con.execute(body).df()
            df.to_csv(OUT / f"{f.stem}__{name}.csv", index=False)
            print(f"[{f.name}] {name}: {len(df)} rows")
            if show:
                print(df.to_string(index=False, max_rows=40), "\n")
    con.close()

if __name__ == "__main__":
    main(sys.argv[1:])
