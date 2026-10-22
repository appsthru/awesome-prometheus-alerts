#!/usr/bin/env python3
"""Render _data/rules.yml through dist/template.yml exactly like .github/workflows/test.yml
(one file per exporter under test/rules/<service>/<slug>.yml), then run `promtool check rules`.

Usage: python3 .claude/scripts/check_rules.py [slug ...]   (no argument = every exporter)
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import liquid
import yaml

ROOT = Path(__file__).resolve().parents[2]


def ruby_split(value, sep):
    """Liquid's `split` as the Ruby gem implements it (String#split): a single space splits on any run
    of whitespace, and trailing empty strings are dropped (python-liquid keeps them)."""
    value = "" if value is None else str(value)
    parts = value.split() if sep == " " else value.split(str(sep))
    while parts and parts[-1] == "":
        parts.pop()
    return parts


def load_template():
    # dist/template.yml is written for the Ruby Liquid gem the CI uses. python-liquid rejects two of its
    # constructs, so rewrite them into equivalents before parsing: `rule.for` (`for` is a reserved word)
    # and a `split:` argument that is a literal newline inside quotes (passed as a variable instead).
    source = (ROOT / "dist/template.yml").read_text()
    source = source.replace("rule.for", 'rule["for"]').replace('split: "\n"', "split: newline")
    env = liquid.Environment()
    env.filters["split"] = ruby_split
    return env.from_string(source)


def main(only):
    template = load_template()
    # Round-trip through JSON so the template sees the same plain values as the CI (yq -o json | liquid).
    data = json.loads(json.dumps(yaml.safe_load((ROOT / "_data/rules.yml").read_text())))

    out_dir = ROOT / "test/rules"
    shutil.rmtree(out_dir, ignore_errors=True)
    files = []
    for group in data["groups"]:
        for service in group["services"]:
            subdir = out_dir / "-".join(service["name"].lower().split(" "))
            for exporter in service["exporters"]:
                if only and exporter["slug"] not in only:
                    continue
                subdir.mkdir(parents=True, exist_ok=True)
                path = subdir / f"{exporter['slug']}.yml"
                path.write_text(template.render(**exporter, newline="\n"))
                files.append(str(path))
    if not files:
        sys.exit(f"No exporter matches: {', '.join(only)}")

    # Rendering alone already proves the YAML loads and the template applies; without promtool, stop there.
    if shutil.which("promtool") is None:
        print(f"WARNING: promtool not found, skipped `promtool check rules` ({len(files)} file(s) rendered in test/rules/).",
              file=sys.stderr)
        return 0

    ok = subprocess.run(["promtool", "check", "rules", *files], stdout=subprocess.DEVNULL).returncode == 0
    # Re-run verbosely only when something failed, so a green run stays short.
    if not ok:
        subprocess.run(["promtool", "check", "rules", *files])
    print(f"promtool: {len(files)} rule file(s) {'OK' if ok else 'FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
