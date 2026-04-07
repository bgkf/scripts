#!/usr/bin/env python3
"""
csv-json-agent: A CLI agent to convert CSV → JSON and JSON → CSV.

Usage:
    python converter.py --input data.csv --output data.json
    python converter.py --input data.json --output data.csv
    python converter.py --input data.csv                        # auto-names output
    python converter.py --input data.csv --delimiter ";"
    python converter.py --input data.csv --indent 4
    python converter.py --input data.csv --no-header
    python converter.py --input data.csv --no-type-inference
    python converter.py --input data.json --pretty              # pretty-print check
"""

import argparse
import csv
import json
import os
import sys
from pathlib import Path


# ── ANSI colours ─────────────────────────────────────────────────────────────

GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
CYAN   = "\033[36m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):    print(f"{GREEN}✔{RESET}  {msg}")
def info(msg):  print(f"{CYAN}ℹ{RESET}  {msg}")
def warn(msg):  print(f"{YELLOW}⚠{RESET}  {msg}")
def err(msg):   print(f"{RED}✘{RESET}  {msg}", file=sys.stderr)


# ── Type inference ────────────────────────────────────────────────────────────

def infer_type(value: str):
    """Try to cast a string cell to int, float, bool, or None."""
    stripped = value.strip()
    if stripped == "":
        return None
    if stripped.lower() == "true":
        return True
    if stripped.lower() == "false":
        return False
    if stripped.lower() in ("null", "none", "na", "n/a"):
        return None
    try:
        return int(stripped)
    except ValueError:
        pass
    try:
        return float(stripped)
    except ValueError:
        pass
    return stripped


# ── CSV → JSON ────────────────────────────────────────────────────────────────

def csv_to_json(
    input_path: Path,
    output_path: Path,
    delimiter: str = ",",
    has_header: bool = True,
    type_inference: bool = True,
    indent: int = 2,
) -> int:
    """Convert a CSV file to a JSON array of objects. Returns row count."""
    info(f"Reading  {input_path}")

    rows = []
    with input_path.open(newline="", encoding="utf-8-sig") as f:
        if has_header:
            reader = csv.DictReader(f, delimiter=delimiter)
            for row in reader:
                if type_inference:
                    rows.append({k: infer_type(v) for k, v in row.items()})
                else:
                    rows.append(dict(row))
        else:
            reader = csv.reader(f, delimiter=delimiter)
            for row in reader:
                if type_inference:
                    rows.append({f"col{i}": infer_type(v) for i, v in enumerate(row)})
                else:
                    rows.append({f"col{i}": v for i, v in enumerate(row)})

    if not rows:
        warn("CSV file is empty — writing an empty JSON array.")

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, indent=indent, ensure_ascii=False)
        f.write("\n")

    return len(rows)


# ── JSON → CSV ────────────────────────────────────────────────────────────────

def json_to_csv(
    input_path: Path,
    output_path: Path,
    delimiter: str = ",",
) -> int:
    """Convert a JSON array of objects to CSV. Returns row count."""
    info(f"Reading  {input_path}")

    with input_path.open(encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError(
            "JSON root must be an array of objects. "
            "Got: " + type(data).__name__
        )
    if not data:
        warn("JSON array is empty — writing a header-only CSV.")
        with output_path.open("w", newline="", encoding="utf-8") as f:
            pass
        return 0

    # Collect all keys across all objects (preserves insertion order in 3.7+)
    fieldnames = list(dict.fromkeys(k for row in data for k in row))

    with output_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
            delimiter=delimiter,
            extrasaction="ignore",
        )
        writer.writeheader()
        for row in data:
            writer.writerow({k: ("" if v is None else v) for k, v in row.items()})

    return len(data)


# ── Auto-detect conversion direction ─────────────────────────────────────────

def detect_format(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".csv":
        return "csv"
    if ext == ".json":
        return "json"
    # Sniff the first non-empty line
    try:
        with path.open(encoding="utf-8-sig") as f:
            first = f.read(512).lstrip()
        if first.startswith("[") or first.startswith("{"):
            return "json"
    except Exception:
        pass
    return "csv"


def auto_output_path(input_path: Path, target_fmt: str) -> Path:
    ext = ".json" if target_fmt == "json" else ".csv"
    return input_path.with_suffix(ext)


# ── CLI ───────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="converter",
        description="Convert CSV ↔ JSON from the command line.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  python converter.py --input sales.csv
  python converter.py --input sales.csv --output out/sales.json --indent 4
  python converter.py --input data.json --output data.csv --delimiter ";"
  python converter.py --input data.csv --no-header --no-type-inference
        """,
    )
    p.add_argument("--input",  "-i", required=True,  metavar="FILE", help="Input file (.csv or .json)")
    p.add_argument("--output", "-o", default=None,   metavar="FILE", help="Output file (auto-named if omitted)")
    p.add_argument("--delimiter", "-d", default=",", metavar="CHAR", help="CSV delimiter (default: comma)")
    p.add_argument("--indent",  type=int, default=2, metavar="N",    help="JSON indent spaces (default: 2; use 0 to minify)")
    p.add_argument("--no-header",         dest="has_header",      action="store_false", help="Treat CSV as having no header row")
    p.add_argument("--no-type-inference", dest="type_inference",  action="store_false", help="Keep all CSV values as strings")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    input_path = Path(args.input)

    if not input_path.exists():
        err(f"Input file not found: {input_path}")
        sys.exit(1)

    src_fmt = detect_format(input_path)
    tgt_fmt = "json" if src_fmt == "csv" else "csv"

    output_path = Path(args.output) if args.output else auto_output_path(input_path, tgt_fmt)

    # Create parent dirs if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print()
    print(f"{BOLD}csv-json-agent{RESET}")
    print(f"  {src_fmt.upper()} → {tgt_fmt.upper()}")
    print()

    try:
        if src_fmt == "csv":
            count = csv_to_json(
                input_path,
                output_path,
                delimiter=args.delimiter,
                has_header=args.has_header,
                type_inference=args.type_inference,
                indent=args.indent if args.indent > 0 else None,
            )
        else:
            count = json_to_csv(
                input_path,
                output_path,
                delimiter=args.delimiter,
            )

        size = output_path.stat().st_size
        size_str = f"{size / 1024:.1f} KB" if size >= 1024 else f"{size} B"

        print()
        ok(f"Converted  {count} row{'s' if count != 1 else ''}")
        ok(f"Written to {output_path}  ({size_str})")
        print()

    except json.JSONDecodeError as e:
        print()
        err(f"Invalid JSON: {e}")
        sys.exit(1)
    except csv.Error as e:
        print()
        err(f"CSV parse error: {e}")
        sys.exit(1)
    except ValueError as e:
        print()
        err(str(e))
        sys.exit(1)
    except Exception as e:
        print()
        err(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
