#!/usr/bin/env python3
"""Build and validate the small runtime distribution (standard library only)."""
import gzip
import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile

PREFIX = "sing-box-deve-runtime"
LIMIT_BYTES = 64 * 1024 * 1024
LIMIT_FILES = 2048
ROOT_FILES = {"sing-box-deve.sh", "version", "LICENSE", "runtime-files.txt", "checksums.txt"}
RUNTIME_SCRIPTS = {"scripts/runtime-archive.py", "scripts/nohup-run.sh", "scripts/bounded-log.py", "scripts/egress-link.py"}


def allowed(name):
    p = PurePosixPath(name)
    return (not p.is_absolute() and str(p) == name and ".." not in p.parts
            and "\\" not in name and not any(c.isspace() for c in name)
            and (name in ROOT_FILES or name in RUNTIME_SCRIPTS
                 or name.startswith(("lib/", "providers/", "rulesets/"))))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify(root):
    root = Path(root)
    files = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"symlink in runtime: {path}")
        if path.is_file():
            name = path.relative_to(root).as_posix()
            if not allowed(name):
                raise ValueError(f"unexpected runtime path: {name}")
            files[name] = path
    if len(files) > LIMIT_FILES or sum(p.stat().st_size for p in files.values()) > LIMIT_BYTES:
        raise ValueError("runtime exceeds size/file limit")
    inventory = (root / "runtime-files.txt").read_text().splitlines()
    if len(set(inventory)) != len(inventory) or set(inventory) != set(files):
        raise ValueError("runtime inventory mismatch")
    sums = {}
    for line in (root / "checksums.txt").read_text().splitlines():
        checksum, name = line.split("  ", 1)
        if name in sums or not allowed(name) or len(checksum) != 64:
            raise ValueError("invalid checksum inventory")
        sums[name] = checksum
    if set(sums) != set(files) - {"checksums.txt"}:
        raise ValueError("incomplete checksum inventory")
    for name, checksum in sums.items():
        if digest(files[name].read_bytes()) != checksum:
            raise ValueError(f"checksum mismatch: {name}")
    for name in ("sing-box-deve.sh", "version", "lib/common.sh"):
        if name not in files:
            raise ValueError(f"required file missing: {name}")
    return files


def pack(source, output, legacy=False):
    source, output = Path(source), Path(output)
    payload = {}
    for name in (ROOT_FILES - {"checksums.txt", "runtime-files.txt"}) | RUNTIME_SCRIPTS:
        path = source / name
        if legacy and name in RUNTIME_SCRIPTS and not path.exists():
            continue
        if path.is_symlink():
            raise ValueError(f"symlink source: {name}")
        payload[name] = path.read_bytes()
    for directory in ("lib", "providers", "rulesets"):
        for path in sorted((source / directory).rglob("*")):
            if path.is_symlink():
                raise ValueError(f"symlink source: {path}")
            if path.is_file():
                name = path.relative_to(source).as_posix()
                if not allowed(name):
                    raise ValueError(f"invalid runtime source: {name}")
                payload[name] = path.read_bytes()
    names = sorted(set(payload) | {"runtime-files.txt", "checksums.txt"})
    payload["runtime-files.txt"] = ("\n".join(names) + "\n").encode()
    payload["checksums.txt"] = "".join(f"{digest(data)}  {name}\n" for name, data in sorted(payload.items())).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as archive:
        for name, data in sorted(payload.items()):
            info = tarfile.TarInfo(f"{PREFIX}/{name}")
            info.size = len(data)
            info.mode = 0o755 if name.endswith((".sh", ".py")) else 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    output.with_name(output.name + ".sha256").write_text(f"{digest(output.read_bytes())}  {output.name}\n")


def extract(archive_path, destination):
    destination = Path(destination)
    if not destination.is_dir() or any(destination.iterdir()):
        raise ValueError("extraction destination must be an empty directory")
    with tarfile.open(archive_path, "r|gz") as archive:
        seen, total = set(), 0
        for member in archive:
            name = member.name[len(PREFIX) + 1:]
            if not member.name.startswith(PREFIX + "/") or not member.isfile() or not allowed(name) or name in seen:
                raise ValueError(f"unsafe archive member: {member.name}")
            total += member.size
            seen.add(name)
            if total > LIMIT_BYTES or len(seen) > LIMIT_FILES:
                raise ValueError("archive exceeds size/file limit")
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as src, path.open("xb") as dst:
                shutil.copyfileobj(src, dst)
            path.chmod(0o755 if path.suffix in (".sh", ".py") else 0o644)
    verify(destination)


def fsync_tree(root):
    root = Path(root)
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as f:
                os.fsync(f.fileno())
    directories = [p for p in root.rglob("*") if p.is_dir() and not p.is_symlink()]
    for path in sorted(directories, key=lambda p: len(p.parts), reverse=True) + [root]:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


if __name__ == "__main__":
    try:
        command, *args = sys.argv[1:]
        {"pack-legacy": lambda *a: pack(*a, legacy=True), "pack": pack, "extract": extract, "verify": verify, "fsync": fsync_tree}[command](*args)
    except (ValueError, OSError, KeyError, tarfile.TarError, TypeError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        sys.exit(1)
