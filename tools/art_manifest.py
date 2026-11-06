"""Record untouched imagegen masters and final raster exports; no image editing."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
paths = sorted((ROOT / "art").glob("*.png")) + sorted((ROOT / "art/icon-exports").glob("*.png"))
result = []
for path in paths:
    with Image.open(path) as image:
        image.load()
        result.append({"file": path.relative_to(ROOT).as_posix(), "size": list(image.size),
                       "format": image.format, "mode": image.mode,
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(ROOT / "art/image-manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Recorded", len(result), "image masters/exports; runtime atlas master: art/lunchbox-texture-final-v3.png")
