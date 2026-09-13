#!/usr/bin/env python3
"""Validate a maintainer-supplied SSH receipt against the release checkout/package."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fields(value, names):
    require(isinstance(value, dict) and set(value) == set(names.split()), "invalid receipt fields")


def timestamp(value):
    require(isinstance(value, str), "invalid receipt timestamp")
    try:
        parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("invalid receipt timestamp") from None
    require(parsed.tzinfo is not None, "receipt timestamp must include timezone")
    return parsed


def validate(receipt, sha, archive_sha):
    fields(receipt, "schema transport source_sha runtime_sha256 acceptance restoration")
    require(type(receipt["schema"]) is int and receipt["schema"] == 1, "unsupported receipt schema")
    require(receipt["transport"] == "ssh", "SSH acceptance receipt required")
    require(re.fullmatch(r"[0-9a-f]{40}", sha) is not None and receipt["source_sha"] == sha,
            "release source SHA differs from SSH receipt")
    require(receipt["runtime_sha256"] == archive_sha, "runtime archive digest differs from SSH receipt")
    acceptance = receipt["acceptance"]
    fields(acceptance, "schema result last_case distro version source_sha finished_at exit_code source_clean cases")
    require(type(acceptance["schema"]) is int and acceptance["schema"] == 1, "unsupported acceptance schema")
    require(acceptance["source_sha"] == sha and acceptance["source_clean"] is True,
            "acceptance source is different or dirty")
    require(acceptance["result"] == "success" and acceptance["last_case"] == "complete"
            and type(acceptance["exit_code"]) is int and acceptance["exit_code"] == 0,
            "real lifecycle acceptance did not complete successfully")
    require(acceptance["distro"] == "debian" and isinstance(acceptance["version"], str)
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", acceptance["version"]) is not None,
            "Debian acceptance required")
    cases = acceptance["cases"]
    require(isinstance(cases, list) and 0 < len(cases) <= 1000
            and all(isinstance(case, str) and re.fullmatch(r"[a-z0-9-]+ passed", case) for case in cases),
            "missing or invalid completed cases")
    restoration = receipt["restoration"]
    checks = "original_deployment_restored managed_firewall_restored protected_services_restored protected_config_unchanged backup_verified"
    fields(restoration, "result source_sha finished_at " + checks)
    require(restoration["result"] == "success" and restoration["source_sha"] == sha
            and all(restoration[key] is True for key in checks.split()), "host restoration was not verified")
    require(timestamp(restoration["finished_at"]) >= timestamp(acceptance["finished_at"]),
            "restoration receipt predates acceptance")


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "duplicate JSON key")
        value[key] = item
    return value


def main(receipt_path, source, archive_path):
    source, archive = Path(source).resolve(), Path(archive_path).resolve()
    with Path(receipt_path).open("rb") as stream:
        raw = stream.read(65537)
    require(len(raw) <= 65536, "receipt exceeds 64 KiB")
    receipt = json.loads(raw, object_pairs_hook=unique_object)
    sha = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True, timeout=30).strip()
    subprocess.run(["git", "-C", str(source), "diff", "--quiet", "HEAD", "--"], check=True, timeout=30)
    # Unrelated developer scratch files may remain; packaging inputs must be clean.
    inputs = ["sing-box-deve.sh", "version", "LICENSE", "lib", "providers", "rulesets",
              "scripts/runtime-archive.py", "scripts/nohup-run.sh", "scripts/bounded-log.py", "scripts/egress-link.py", "scripts/package-run.py"]
    dirty = subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--ignored",
                                     "--untracked-files=all", "--", *inputs], text=True, timeout=30)
    require(not dirty, "runtime packaging inputs are dirty")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    require(archive.with_name(archive.name + ".sha256").read_text() == f"{digest}  {archive.name}\n",
            "runtime archive checksum sidecar differs")
    validate(receipt, sha, digest)
    print(f"[OK] SSH acceptance, restoration and runtime digest verified for {sha}")


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 4, "usage: verify-release-receipt.py RECEIPT SOURCE ARCHIVE")
        main(*sys.argv[1:])
    except (ValueError, OSError, TypeError, subprocess.SubprocessError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        sys.exit(1)
