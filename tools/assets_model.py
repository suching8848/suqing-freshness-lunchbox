"""Read original PZ lunchbox meshes and make offline debug projections only.

This does not run the game, load a world or generate/paint production artwork.
"""
from pathlib import Path
import math
import re
import struct
import zlib
import numpy as np
from PIL import Image

NUMBER = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


def numbers(text):
    return [float(v) for v in NUMBER.findall(text)]


def block(text, kind):
    match = re.search(r"\b" + re.escape(kind) + r"(?:\s+[^\s{]+)?\s*\{", text)
    if not match:
        raise ValueError("Missing " + kind)
    start = match.end()
    depth = 1
    cursor = start
    while cursor < len(text):
        if text[cursor] == "{":
            depth += 1
        elif text[cursor] == "}":
            depth -= 1
            if depth == 0:
                return text[start:cursor]
        cursor += 1
    raise ValueError("Unclosed " + kind)


def read_x(path):
    raw = Path(path).read_bytes()
    if not raw.startswith(b"xof 0303txt 0032"):
        raise ValueError("Expected native textual DirectX X")
    text = raw.decode("ascii")
    match = re.search(r"(?m)^\s*Mesh\s+([^\s{]+)\s*\{", text)
    if not match:
        raise ValueError("Missing actual mesh (not a template)")
    body = block(text[match.start():], "Mesh")
    values = iter(numbers(body[:body.index("MeshNormals")]))
    count = int(next(values))
    vertices = [[next(values), next(values), next(values)] for _ in range(count)]
    face_count = int(next(values))
    faces = []
    for _ in range(face_count):
        size = int(next(values))
        faces.append([int(next(values)) for _ in range(size)])
    uv_values = iter(numbers(block(body, "MeshTextureCoords")))
    uv_count = int(next(uv_values))
    uv = [[next(uv_values), next(uv_values)] for _ in range(uv_count)]
    skin = []
    for sw in re.finditer(r"\bSkinWeights\s*\{([^}]+)\}", body):
        name_match = re.match(r'\s*"([^"]+)"\s*;', sw[1])
        stream = iter(numbers(sw[1][name_match.end():]))
        size = int(next(stream))
        indices = [int(next(stream)) for _ in range(size)]
        weights = [next(stream) for _ in range(size)]
        matrix = [next(stream) for _ in range(16)]
        skin.append(dict(bone=name_match[1], indices=indices, weights=weights, offset_matrix=matrix))
    frames = re.findall(r"(?m)^\s*Frame\s+([^\s{]+)\s*\{", text)
    frame_matrices = [numbers(m[1]) for m in re.finditer(r"FrameTransformMatrix\s*\{([^}]+)\}", text)
                      if len(numbers(m[1])) == 16]
    assert count == uv_count
    triangles = []
    for face in faces:
        for i in range(1, len(face) - 1):
            ids = [face[0], face[i], face[i + 1]]
            triangles.append((ids, [uv[n] for n in ids]))
    return dict(format="DirectX text 0303 / float32", name=match[1], vertices=vertices,
                faces=faces, uv=uv, skin=skin, frames=frames, frame_matrices=frame_matrices,
                triangles=triangles, textures=re.findall(r'TextureFilename\s*\{\s*"([^"]+)"', text))


def read_fbx(path):
    raw = Path(path).read_bytes()
    if raw[:23] != b"Kaydara FBX Binary  \x00\x1a\x00":
        raise ValueError("Expected binary FBX")
    version = struct.unpack_from("<I", raw, 23)[0]
    if version >= 7500:
        raise ValueError("Only the original pre-7500 FBX layout is expected")

    def prop(offset):
        kind = chr(raw[offset]); offset += 1
        scalar = {"Y": "h", "C": "?", "I": "i", "F": "f", "D": "d", "L": "q"}
        if kind in scalar:
            fmt = "<" + scalar[kind]
            return struct.unpack_from(fmt, raw, offset)[0], offset + struct.calcsize(fmt)
        if kind in ("S", "R"):
            size = struct.unpack_from("<I", raw, offset)[0]; offset += 4
            value = raw[offset:offset + size]
            return (value.decode("utf-8", errors="replace") if kind == "S" else value), offset + size
        formats = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "?", "c": "b"}
        if kind not in formats:
            raise ValueError("Unsupported FBX property " + kind)
        count, encoding, size = struct.unpack_from("<III", raw, offset); offset += 12
        payload = raw[offset:offset + size]
        if encoding == 1:
            payload = zlib.decompress(payload)
        elif encoding != 0:
            raise ValueError("Unknown array compression")
        fmt = "<" + str(count) + formats[kind]
        assert len(payload) == struct.calcsize(fmt)
        return list(struct.unpack(fmt, payload)), offset + size

    def node(offset):
        end, count, length, name_length = struct.unpack_from("<IIIB", raw, offset)
        if end == 0:
            return None, offset + 13
        assert offset < end <= len(raw)
        cursor = offset + 13
        name = raw[cursor:cursor + name_length].decode("ascii"); cursor += name_length
        properties = []
        properties_start = cursor
        for _ in range(count):
            value, cursor = prop(cursor); properties.append(value)
        assert cursor - properties_start == length
        children = []
        while cursor < end:
            child, cursor = node(cursor)
            if child is None:
                break
            children.append(child)
        assert cursor == end
        return dict(name=name, properties=properties, children=children), end

    roots = []; cursor = 27
    while cursor + 13 <= len(raw):
        value, cursor = node(cursor)
        if value is None:
            break
        roots.append(value)

    def find(nodes, name):
        return next(n for n in nodes if n["name"] == name)

    objects = find(roots, "Objects")["children"]
    geometry = next(n for n in objects if n["name"] == "Geometry" and n["properties"][-1] == "Mesh")
    children = geometry["children"]
    vertices = np.asarray(find(children, "Vertices")["properties"][0]).reshape(-1, 3).tolist()
    polygon = find(children, "PolygonVertexIndex")["properties"][0]
    layer = find(children, "LayerElementUV")["children"]
    uv = np.asarray(find(layer, "UV")["properties"][0]).reshape(-1, 2).tolist()
    uv_index = find(layer, "UVIndex")["properties"][0]
    faces = []; face_uv = []; face = []; uv_face = []
    for i, encoded in enumerate(polygon):
        face.append(-encoded - 1 if encoded < 0 else encoded)
        uv_face.append(uv[uv_index[i]])
        if encoded < 0:
            faces.append(face); face_uv.append(uv_face); face = []; uv_face = []
    assert not face and len(polygon) == len(uv_index)
    triangles = []
    for face, coords in zip(faces, face_uv):
        for i in range(1, len(face) - 1):
            # FBX uses the opposite V origin to the DirectX hand UVs.
            triangles.append(([face[0], face[i], face[i + 1]],
                              [[u, 1 - v] for u, v in [coords[0], coords[i], coords[i + 1]]]))
    global_settings = find(find(roots, "GlobalSettings")["children"], "Properties70")["children"]
    settings = {n["properties"][0]: n["properties"][-1] for n in global_settings if n["name"] == "P"}
    model_nodes = []
    for obj in objects:
        if obj["name"] != "Model":
            continue
        props = next((n for n in obj["children"] if n["name"] == "Properties70"), None)
        model_nodes.append({
            "id": obj["properties"][0], "name": obj["properties"][1],
            "properties": {n["properties"][0]: n["properties"][4:]
                           for n in props["children"] if n["name"] == "P"} if props else {},
        })
    connections = find(roots, "Connections")["children"]
    geometry_parent = next(n["properties"][2] for n in connections
                           if n["name"] == "C" and n["properties"][:2] == ["OO", geometry["properties"][0]])
    return dict(format="FBX Binary", version=version, name=geometry["properties"][1],
                vertices=vertices, faces=faces, uv=uv, face_uv=face_uv, triangles=triangles,
                global_settings=settings, model_nodes=model_nodes, geometry_parent=geometry_parent)


def mesh_summary(mesh):
    vertices = np.asarray(mesh["vertices"])
    uv = np.asarray(mesh["uv"])
    return dict(format=mesh["format"], vertices=len(vertices), faces=len(mesh["faces"]),
                triangles=len(mesh["triangles"]), bounds=[vertices.min(0).tolist(), vertices.max(0).tolist()],
                uv_count=len(uv), uv_bounds=[uv.min(0).tolist(), uv.max(0).tolist()],
                skin=[dict(bone=v["bone"], vertices=len(v["indices"])) for v in mesh.get("skin", [])],
                bone_count=len(mesh.get("frames", [])))


def project(mesh, texture_path, yaw=35, size=512):
    """CPU-only orthographic mesh inspection, not a game visual acceptance test."""
    vertices = np.asarray(mesh["vertices"], dtype=float)
    if mesh.get("global_settings", {}).get("UpAxis") == 2:
        vertices = vertices[:, [0, 2, 1]]
        vertices[:, 2] *= -1
    vertices -= (vertices.min(0) + vertices.max(0)) / 2
    angle = math.radians(yaw)
    right = np.array([math.cos(angle), 0, -math.sin(angle)])
    up = np.array([-math.sin(angle) * .35, .94, -math.cos(angle) * .35]); up /= np.linalg.norm(up)
    forward = np.cross(right, up)
    coords = np.column_stack((vertices @ right, vertices @ up, vertices @ forward))
    span = max(np.ptp(coords[:, 0]), np.ptp(coords[:, 1]))
    coords[:, :2] *= size * .8 / span
    coords[:, 0] += size / 2; coords[:, 1] = size / 2 - coords[:, 1]
    tex = np.asarray(Image.open(texture_path).convert("RGB"))
    canvas = np.zeros((size, size, 4), dtype=np.uint8)
    canvas[:, :, :3] = (35, 31, 45); canvas[:, :, 3] = 255
    depth = np.full((size, size), -np.inf)
    light = np.array([-.3, .8, 1]); light /= np.linalg.norm(light)
    for ids, uv in mesh["triangles"]:
        p = coords[ids]; xyz = vertices[ids]
        normal = np.cross(xyz[1] - xyz[0], xyz[2] - xyz[0])
        norm = np.linalg.norm(normal)
        if norm < 1e-12:
            continue
        brightness = .6 + .4 * abs(float((normal / norm) @ light))
        low = np.maximum(0, np.floor(p[:, :2].min(0)).astype(int))
        high = np.minimum(size - 1, np.ceil(p[:, :2].max(0)).astype(int))
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
        zview = depth[low[1]:high[1] + 1, low[0]:high[0] + 1]
        mask = (u >= -1e-7) & (v >= -1e-7) & (w >= -1e-7) & (z > zview)
        coords_uv = u[..., None] * uv[0] + v[..., None] * uv[1] + w[..., None] * uv[2]
        tx = np.clip((coords_uv[:, :, 0] * tex.shape[1]).astype(int), 0, tex.shape[1] - 1)
        ty = np.clip((coords_uv[:, :, 1] * tex.shape[0]).astype(int), 0, tex.shape[0] - 1)
        color = np.clip(tex[ty, tx] * brightness, 0, 255).astype(np.uint8)
        view = canvas[low[1]:high[1] + 1, low[0]:high[0] + 1, :3]
        view[mask] = color[mask]; zview[mask] = z[mask]
    return Image.fromarray(canvas)
