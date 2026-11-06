"""Render the actual ground mesh into its separate native world-sprite fallback.

This is a geometry render, not a resized inventory icon or a newly painted asset.
No game, JVM, OpenGL context or external modeling service is started.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import numpy as np
from PIL import Image
from assets_model import read_fbx

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "mods/SuQingFreshnessLunchbox/42/media"
MESH = MEDIA / "models_X/WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground.fbx"
MATERIAL = MEDIA / "textures/Clothes/Bag/SuQingFreshnessLunchbox.png"
OUTPUT = MEDIA / "inventory/world/WItem_SuQingFreshnessLunchbox.png"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rotation(axis, degrees):
    result = np.eye(4)
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    a, b = ((1, 2), (2, 0), (0, 1))[axis]
    result[a, a] = result[b, b] = c
    result[a, b], result[b, a] = -s, s
    return result


def project_vertices(mesh, size=32, yaw=0.0):
    node = next(n for n in mesh["model_nodes"] if n["id"] == mesh["geometry_parent"])
    props = node["properties"]
    # This vanilla-derived asset only has X-axis pre/local/geometric rotations.
    # Refuse a changed FBX hierarchy instead of silently rendering a wrong mask.
    for name in ("PreRotation", "Lcl Rotation", "GeometricRotation"):
        if not np.allclose(props.get(name, [0, 0, 0])[1:], 0):
            raise ValueError("Recalibrate the projection for a changed FBX rotation: " + name)
    translation = np.eye(4)
    translation[:3, 3] = props.get("Lcl Translation", [0, 0, 0])
    scale = np.diag([*props.get("Lcl Scaling", [1, 1, 1]), 1])
    transform = (translation @ rotation(0, props.get("PreRotation", [0])[0])
                 @ rotation(0, props.get("Lcl Rotation", [0])[0]) @ scale
                 @ rotation(0, props.get("GeometricRotation", [0])[0]))
    raw = np.asarray(mesh["vertices"], dtype=float)
    xyz = (np.column_stack((raw, np.ones(len(raw)))) @ transform.T)[:, :3]
    camera = rotation(0, 30)[:3, :3] @ rotation(1, 135)[:3, :3] @ np.diag([-1, 1, 1])
    view = xyz @ rotation(1, yaw)[:3, :3].T @ camera.T
    pixels_per_unit = 1920 * ((math.sqrt(2) / 2 / 10) / 1.5) * 1.5
    model_scale = 0.4  # Same ModelScript scale as the unchanged 3D ground model.
    projected = np.column_stack((size / 2 + pixels_per_unit * model_scale * view[:, 0],
                                size * 3 / 4 - pixels_per_unit * model_scale * view[:, 1],
                                view[:, 2]))
    return projected, xyz, transform, props, pixels_per_unit


def render(output=OUTPUT):
    size, samples, yaw = 32, 8, 0.0
    mesh = read_fbx(MESH)
    projected, xyz, transform, props, pixels_per_unit = project_vertices(mesh, size, yaw)
    if (projected[:, :2] < 1).any() or (projected[:, :2] > size - 1).any():
        raise ValueError("World projection clips the canvas; recalibrate the fixed world fallback.")
    coords = projected.copy()
    coords[:, :2] *= samples
    material = np.asarray(Image.open(MATERIAL).convert("RGB"))
    canvas = np.zeros((size * samples, size * samples, 4), dtype=np.uint8)
    depth = np.full(canvas.shape[:2], -np.inf)
    light = np.array([-.3, .8, 1.0]); light /= np.linalg.norm(light)
    for ids, uv in mesh["triangles"]:
        p = coords[ids]
        normal = np.cross(xyz[ids[1]] - xyz[ids[0]], xyz[ids[2]] - xyz[ids[0]])
        length = np.linalg.norm(normal)
        if length < 1e-12:
            continue
        brightness = .6 + .4 * abs(float(normal @ light / length))
        low = np.maximum(0, np.floor(p[:, :2].min(0)).astype(int))
        high = np.minimum(size * samples - 1, np.ceil(p[:, :2].max(0)).astype(int))
        if (high < low).any():
            continue
        xs, ys = np.meshgrid(np.arange(low[0], high[0] + 1) + .5,
                             np.arange(low[1], high[1] + 1) + .5)
        a, b, c = p[:, :2]
        determinant = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(determinant) < 1e-12:
            continue
        u = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / determinant
        v = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / determinant
        w = 1 - u - v
        z = u * p[0, 2] + v * p[1, 2] + w * p[2, 2]
        zv = depth[low[1]:high[1] + 1, low[0]:high[0] + 1]
        mask = (u >= -1e-7) & (v >= -1e-7) & (w >= -1e-7) & (z > zv)
        tuv = u[..., None] * uv[0] + v[..., None] * uv[1] + w[..., None] * uv[2]
        tx = np.clip((tuv[..., 0] * material.shape[1]).astype(int), 0, material.shape[1] - 1)
        ty = np.clip((tuv[..., 1] * material.shape[0]).astype(int), 0, material.shape[0] - 1)
        rgba = canvas[low[1]:high[1] + 1, low[0]:high[0] + 1]
        rgba[..., :3][mask] = np.clip(material[ty, tx] * brightness, 0, 255).astype(np.uint8)[mask]
        rgba[..., 3][mask] = 255
        zv[mask] = z[mask]
    image = Image.fromarray(canvas).convert("RGBa").resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    manifest = {
        "method": "Offline triangle/UV/depth-buffer render of the actual ground FBX and current material",
        "mesh": str(MESH), "mesh_sha256": sha(MESH), "material_sha256": sha(MATERIAL),
        "output": str(output), "output_sha256": sha(output), "size": [size, size],
        "alpha_bbox": image.getchannel("A").getbbox(), "world_yaw_degrees": yaw,
        "model_scale_unchanged": .4, "ScaleWorldIcon": 1, "sprite_anchor": [size / 2, size * .75],
        "pixels_per_model_unit": pixels_per_unit, "mesh_transform": transform.tolist(),
        "fbx_node_properties": props, "projected_bounds": [projected[:, :2].min(0).tolist(), projected[:, :2].max(0).tolist()],
        "retained_inventory_icon_sha256": sha(MEDIA / "textures/Item_SuQingFreshnessLunchbox.png"),
        "limitations": "Fixed-yaw fallback only; exact arbitrary rotation/placement and camera alignment require user gameplay acceptance.",
        "game_started": False, "in_game_verified": False,
    }
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    result = render(args.output)
    manifest_path = ROOT / "art/model/world-sprite-manifest.json"
    manifest_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
