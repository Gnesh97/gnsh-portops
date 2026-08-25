"""Build a deterministic source release artifact without development files."""
from pathlib import Path
import argparse, re, zipfile

EXCLUDED = {".git", ".codebase-memory", "tests", "node_modules", "tmp", "temp", "logs", ".vscode", ".idea"}
EXCLUDED_SUFFIXES = {".log", ".pyc"}

def _version(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*version(?:\s*=\s*|\s+)['\"]([^'\"]+)['\"]", line)
        if match:
            return match.group(1)
    raise ValueError(f"version is missing from {path}")


def _validate_archive(path: Path, version: str) -> None:
    forbidden = (".git", ".codebase-memory", "tests", "node_modules", ".vscode", ".idea")
    with zipfile.ZipFile(path) as archive:
        names = [entry.filename for entry in archive.infolist()]
        if "gnsh-portops/fxmanifest.lua" not in names:
            raise ValueError("release archive does not contain fxmanifest.lua")
        for name in names:
            parts = Path(name).parts
            if any(part in forbidden for part in parts) or Path(name).name.startswith(".env"):
                raise ValueError(f"forbidden release entry: {name}")
            if Path(name).suffix in EXCLUDED_SUFFIXES:
                raise ValueError(f"development artifact in release: {name}")
        manifest = archive.read("gnsh-portops/fxmanifest.lua").decode("utf-8")
        if f"version '{version}'" not in manifest and f'version "{version}"' not in manifest:
            raise ValueError("release manifest version is inconsistent")


def build(root: Path, output: Path) -> Path:
    version = _version(root / "fxmanifest.lua")
    config_version = _version(root / "config" / "config.lua")
    if config_version != version:
        raise ValueError(f"manifest/config versions differ: {version} != {config_version}")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists(): output.unlink()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or any(part in EXCLUDED for part in path.relative_to(root).parts): continue
            if path.suffix in EXCLUDED_SUFFIXES or path.name.startswith(".env"): continue
            archive.write(path, Path("gnsh-portops") / path.relative_to(root))
    _validate_archive(output, version)
    return output

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--root", type=Path, default=Path(__file__).parents[1]); parser.add_argument("--output", type=Path)
    args = parser.parse_args(); out = args.output or Path.cwd() / "gnsh-portops-release.zip"; print(build(args.root, out))
