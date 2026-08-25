"""Build a deterministic source release artifact without development files."""
from pathlib import Path
import argparse, os, shutil, zipfile

EXCLUDED = {".git", ".codebase-memory", "tests", "node_modules", "tmp", "temp", "logs", ".vscode", ".idea"}
EXCLUDED_SUFFIXES = {".log", ".pyc"}

def build(root: Path, output: Path) -> Path:
    version = "unknown"
    for line in (root / "fxmanifest.lua").read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("version"):
            version = line.split("'", 2)[1]; break
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists(): output.unlink()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or any(part in EXCLUDED for part in path.relative_to(root).parts): continue
            if path.suffix in EXCLUDED_SUFFIXES or path.name.startswith(".env"): continue
            archive.write(path, Path("gnsh-portops") / path.relative_to(root))
    return output

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--root", type=Path, default=Path(__file__).parents[1]); parser.add_argument("--output", type=Path)
    args = parser.parse_args(); out = args.output or Path.cwd() / "gnsh-portops-release.zip"; print(build(args.root, out))
