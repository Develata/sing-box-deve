#!/usr/bin/env python3
"""Exercise fail-closed release evidence validation, without SSH or publication."""
import copy
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import tempfile

gate = runpy.run_path(str(Path(__file__).with_name("verify-release-receipt.py")))
sha, digest = "1" * 40, "2" * 64
receipt = {
    "schema": 1, "transport": "ssh", "source_sha": sha, "runtime_sha256": digest,
    "acceptance": {"schema": 1, "result": "success", "last_case": "complete", "distro": "debian",
                   "version": "13", "source_sha": sha, "finished_at": "2026-09-11T03:00:00+00:00",
                   "exit_code": 0, "source_clean": True, "cases": ["install-lite passed", "uninstall passed"]},
    "restoration": {"result": "success", "source_sha": sha, "finished_at": "2026-09-11T03:01:00+00:00",
                    "original_deployment_restored": True, "managed_firewall_restored": True,
                    "protected_services_restored": True, "protected_config_unchanged": True, "backup_verified": True},
}
gate["validate"](receipt, sha, digest)
rejected = 0


def reject(candidate):
    global rejected
    try:
        gate["validate"](candidate, sha, digest)
    except (ValueError, TypeError):
        rejected += 1
    else:
        raise AssertionError("invalid release evidence accepted")


for path, value in [
    (("schema",), True), (("source_sha",), "3" * 40), (("runtime_sha256",), "4" * 64),
    (("transport",), "mock"), (("acceptance", "source_sha"), "5" * 40),
    (("acceptance", "source_clean"), False), (("acceptance", "source_clean"), "true"),
    (("acceptance", "exit_code"), 1), (("acceptance", "exit_code"), False),
    (("acceptance", "result"), "failure"), (("acceptance", "last_case"), "uninstall"),
    (("acceptance", "distro"), "ubuntu"), (("acceptance", "cases"), []),
    (("acceptance", "cases"), ["install failed"]), (("acceptance", "cases"), ["secret://credential"]),
    (("restoration", "source_sha"), "6" * 40), (("restoration", "result"), "failure"),
    (("restoration", "finished_at"), "2026-09-11T02:00:00Z"),
    (("restoration", "finished_at"), "2026-09-11T03:01:00"),
] + [(("restoration", key), False) for key in receipt["restoration"] if key.endswith(("restored", "unchanged", "verified"))]:
    candidate = copy.deepcopy(receipt)
    parent = candidate
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = value
    reject(candidate)
candidate = copy.deepcopy(receipt)
del candidate["restoration"]
reject(candidate)
candidate = copy.deepcopy(receipt)
candidate["password"] = "must-not-be-published"
reject(candidate)
try:
    json.loads('{"schema":1,"schema":1}', object_pairs_hook=gate["unique_object"])
except ValueError:
    rejected += 1
else:
    raise AssertionError("duplicate JSON keys accepted")

# Exercise checkout and sidecar checks through the actual CLI boundary.
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / "repo"
    source.mkdir()
    (source / "version").write_text("v1.1.0\n")
    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], stderr=subprocess.DEVNULL, text=True).strip()
    git("init", "-q")
    git("add", "version")
    git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
    archive = root / "runtime.tar.gz"
    archive.write_bytes(b"opaque digest fixture")
    actual_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    sidecar = archive.with_name(archive.name + ".sha256")
    sidecar.write_text(f"{actual_digest}  {archive.name}\n")
    actual = copy.deepcopy(receipt)
    for block in (actual, actual["acceptance"], actual["restoration"]):
        block["source_sha"] = git("rev-parse", "HEAD")
    actual["runtime_sha256"] = actual_digest
    evidence = root / "receipt.json"
    evidence.write_text(json.dumps(actual))
    gate["main"](evidence, source, archive)
    # Even an unchanged runtime archive cannot transfer A's acceptance to B.
    git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "new target SHA")
    try:
        gate["main"](evidence, source, archive)
    except ValueError as error:
        assert "source SHA" in str(error)
        rejected += 1
    else:
        raise AssertionError("old receipt accepted for a new release commit")
    for block in (actual, actual["acceptance"], actual["restoration"]):
        block["source_sha"] = git("rev-parse", "HEAD")
    evidence.write_text(json.dumps(actual))
    for mutation in ("sidecar", "tracked", "untracked-runtime", "ignored-runtime"):
        if mutation == "sidecar":
            sidecar.write_text("wrong digest\n")
        elif mutation == "tracked":
            (source / "version").write_text("v9.9.9\n")
        elif mutation == "untracked-runtime":
            (source / "lib").mkdir()
            (source / "lib/extra.sh").write_text("echo unexpected\n")
        else:
            (source / ".git/info/exclude").write_text("lib/\n")
        try:
            gate["main"](evidence, source, archive)
        except (ValueError, subprocess.CalledProcessError):
            rejected += 1
        else:
            raise AssertionError(f"accepted {mutation}")
        sidecar.write_text(f"{actual_digest}  {archive.name}\n")
        (source / "version").write_text("v1.1.0\n")
print(f"[OK] release receipt validation passed; {rejected} invalid evidence cases rejected")
