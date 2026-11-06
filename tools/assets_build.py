"""Build independent lunchbox model bindings and export an ImageGen-made atlas.

Only source geometry and existing image size exports are processed here. The
production atlas must be independently edited/generated with ImageGen first.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import shutil
import uuid
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw
from assets_model import read_x, read_fbx, mesh_summary, project

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MEDIA = ROOT / "mods/SuQingFreshnessLunchbox/42/media"
ART = ROOT / "art/model"
TEXTURE_REL = "textures/Clothes/Bag/SuQingFreshnessLunchbox.png"
NATIVE_TEXTURE = GAME / "media/textures/Clothes/Bag/PlasticLunchBox_01.png"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def generate(texture_source=None):
    ART.mkdir(parents=True, exist_ok=True)
    sources = [NATIVE_TEXTURE, GAME / "media/scripts/generated/items/container.txt",
               GAME / "media/scripts/generated/models_items.txt"]
    outputs = []; models = {}
    guid_table = ET.Element("fileGuidTable")
    for hand in ("RHand", "LHand"):
        old_name = "PlasticLunchBox_" + hand
        new_name = "SuQingFreshnessLunchbox_" + hand
        old_mesh = GAME / ("media/models_X/Skinned/BackPacks/" + old_name + ".x")
        new_mesh = MEDIA / ("models_X/Skinned/BackPacks/" + new_name + ".x")
        new_mesh.parent.mkdir(parents=True, exist_ok=True)
        raw = old_mesh.read_bytes()
        assert raw.count(b'"PlasticLunchBox.png"') == 1
        new_mesh.write_bytes(raw.replace(b'"PlasticLunchBox.png"', b'"SuQingFreshnessLunchbox.png"'))
        old_xml = GAME / ("media/clothing/clothingItems/Bag_Lunchbox_" + hand + ".xml")
        new_xml = MEDIA / ("clothing/clothingItems/" + new_name + ".xml")
        tree = ET.parse(old_xml)
        node = tree.getroot()
        model_path = "media\\models_X\\Skinned\\BackPacks\\" + new_name + ".x"
        node.find("m_MaleModel").text = model_path
        node.find("m_FemaleModel").text = model_path
        node.find("m_GUID").text = str(uuid.uuid5(uuid.NAMESPACE_URL, "SuQingFreshnessLunchbox:" + hand))
        node.find("textureChoices").text = "Clothes\\Bag\\SuQingFreshnessLunchbox"
        new_xml.parent.mkdir(parents=True, exist_ok=True)
        tree.write(new_xml, encoding="utf-8", xml_declaration=True)
        pair = ET.SubElement(guid_table, "files")
        ET.SubElement(pair, "path").text = "media/clothing/clothingItems/" + new_name + ".xml"
        ET.SubElement(pair, "guid").text = node.findtext("m_GUID")
        sources.extend([old_mesh, old_xml]); outputs.extend([new_mesh, new_xml])
        models[hand] = read_x(new_mesh)

    # OutfitManager resolves replacement clothing through FileGuidTable before
    # it schedules XML loading; the GUID inside clothingItem XML is insufficient.
    guid_path = MEDIA / "fileGuidTable.xml"
    ET.indent(guid_table, space="    ")
    ET.ElementTree(guid_table).write(guid_path, encoding="utf-8", xml_declaration=True)
    sources.append(GAME / "media/fileGuidTable.xml"); outputs.append(guid_path)

    old_ground = GAME / "media/models_X/WorldItems/Clothing/PlasticLunchBox_Ground.fbx"
    new_ground = MEDIA / "models_X/WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground.fbx"
    new_ground.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(old_ground, new_ground)
    sources.append(old_ground); outputs.append(new_ground)
    models["Ground"] = read_fbx(new_ground)
    script = MEDIA / "scripts/models_FreshnessLunchbox.txt"
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("module Base\n{\n    model SuQingFreshnessLunchbox_Ground\n    {\n"
                      "        mesh = WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground,\n"
                      "        texture = Clothes/Bag/SuQingFreshnessLunchbox,\n"
                      "        scale = 0.4,\n    }\n}\n", encoding="utf-8")
    outputs.append(script)
    shutil.copy2(NATIVE_TEXTURE, ART / "native_atlas_reference.png")
    with Image.open(NATIVE_TEXTURE) as image:
        image.resize((1024, 1024), Image.Resampling.NEAREST).save(ART / "native_atlas_reference_1024.png")

    # Scientific UV diagram, not edited production artwork.
    wire = Image.new("RGB", (1024, 1024), (245, 243, 250))
    draw = ImageDraw.Draw(wire)
    for x in range(0, 1024, 64):
        draw.line([(x, 0), (x, 1023)], fill=(215, 210, 225))
        draw.line([(0, x), (1023, x)], fill=(215, 210, 225))
    for _, uv in models["RHand"]["triangles"]:
        points = [(u * 1023, v * 1023) for u, v in uv]
        draw.line(points + [points[0]], fill=(95, 51, 145), width=2)
    wire.save(ART / "uv_wireframe.png")
    save(ART / "uv-layout.json", {
        "native_texture_dimensions": [128, 128],
        "hand_uv_origin": "DirectX texture-top V for the debug diagram; hand UV arrays are preserved exactly.",
        "Ground": {"uv_origin": "FBX bottom V; debug projection flips V", "summary": mesh_summary(models["Ground"])},
        "hands": {h: {"summary": mesh_summary(models[h]), "uv": models[h]["uv"],
                       "faces": models[h]["faces"]} for h in ("RHand", "LHand")},
    })

    texture = MEDIA / TEXTURE_REL
    if texture_source:
        texture_source = Path(texture_source).resolve(strict=True)
        if texture_source != ART / "texture-source.png":
            shutil.copy2(texture_source, ART / "texture-source.png")
        with Image.open(texture_source) as image:
            assert image.width == image.height, "Atlas must be square, with the original UV layout"
            texture.parent.mkdir(parents=True, exist_ok=True)
            image.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS).save(texture)
        outputs.append(texture)
    if texture.exists() and texture not in outputs:
        outputs.append(texture)
    item_icon_master = ROOT / "art/item-icon-source.png"
    item_icon = MEDIA / "textures/Item_SuQingFreshnessLunchbox.png"
    with Image.open(item_icon_master) as image:
        image.convert("RGBA").resize((32, 32), Image.Resampling.LANCZOS).save(item_icon)
    outputs.append(item_icon)
    # The world sprite is a real mesh projection; the independently generated
    # inventory icon remains unchanged and is never used as the world mask.
    from assets_world_sprite import render as render_world_sprite
    world_sprite = MEDIA / "inventory/world/WItem_SuQingFreshnessLunchbox.png"
    save(ART / "world-sprite-manifest.json", render_world_sprite(world_sprite))
    outputs.append(world_sprite)
    chosen = texture if texture.exists() else NATIVE_TEXTURE
    # Diagnostic UV overlay only. This is never used as a production material.
    with Image.open(chosen) as image:
        overlay = image.convert("RGB").resize((1024, 1024), Image.Resampling.NEAREST)
    overlay_lines = ImageDraw.Draw(overlay)
    for _, uv in models["RHand"]["triangles"]:
        points = [(u * 1023, v * 1023) for u, v in uv]
        overlay_lines.line(points + [points[0]], fill=(230, 60, 80), width=1)
    overlay.save(ART / "uv_texture_debug_overlay.png")
    preview = Image.new("RGB", (1024, 1120), (35, 31, 45))
    views = [("Ground", 35), ("Ground", 215), ("RHand", 35), ("LHand", 35)]
    for i, (kind, yaw) in enumerate(views):
        preview.paste(project(models[kind], chosen), ((i % 2) * 512, (i // 2) * 550 + 28))
    label = ImageDraw.Draw(preview)
    for i, (kind, yaw) in enumerate(views):
        label.text(((i % 2) * 512 + 18, (i // 2) * 550 + 8),
                   kind + " / centered source mesh, CPU debug projection", fill=(240, 230, 255))
    label.text((18, 1100), "Not an in-game pose, model-loader or Viewpoint acceptance test.", fill=(240, 230, 255))
    preview.save(ART / "model_static_preview.png")

    originals = {str(p): dict(sha256=sha(p), bytes=p.stat().st_size) for p in sources}
    save(ART / "source-provenance.json", {
        "checkedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "source": "Local original Project Zomboid Lunchbox assets, derived with independent names and materials.",
        "originals": originals,
        "modifications": ["Independent XML names/GUIDs and texture references.",
                          "Replacement clothing GUIDs registered in the mod's media/fileGuidTable.xml for OutfitManager loading.",
                          "Hand X geometry, skeleton, UVs, weights and bind matrices retained; only the embedded texture name changes.",
                          "Independent ground FBX copy, unchanged geometry; distinct ModelScript/texture and native 0.4 scale.",
                          "Production texture is a separately ImageGen-edited atlas; this script only exports its size.",
                          "Independent ImageGen item icon master is exported at native 32px for world-outline fallback sizing; mod icon and cover are separate."],
        "original_files_written": False,
        "texture_input": str(Path(texture_source).resolve()) if texture_source else None,
        "texture_source_sha256": sha(ART / "texture-source.png") if (ART / "texture-source.png").exists() else None,
        "item_icon_input": str(item_icon_master),
        "item_icon_master_sha256": sha(item_icon_master),
        "item_icon_size": [32, 32],
    })
    result = {
        "status": "TEXTURE_EXPORTED" if texture.exists() else "PENDING_IMAGEGEN_TEXTURE",
        "checkedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "interface": {"primary": "SuQingFreshnessLunchbox_RHand holdingbagright",
                      "secondary": "SuQingFreshnessLunchbox_LHand holdingbagleft",
                      "world_static_model": "SuQingFreshnessLunchbox_Ground",
                      "texture": "Clothes/Bag/SuQingFreshnessLunchbox"},
        "outputs": {p.relative_to(MEDIA).as_posix(): dict(bytes=p.stat().st_size, sha256=sha(p)) for p in outputs},
        "models": {name: mesh_summary(model) for name, model in models.items()},
        "game_started": False, "in_game_tested": False,
        "viewpoint": "Static audit: native character ModelSlot/skin palette path; user visual acceptance required.",
    }
    save(ART / "model_manifest.json", result)
    print(json.dumps({"status": result["status"], "outputs": len(outputs), "models": result["models"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--texture", type=Path, help="ImageGen-edited square atlas; no repainting occurs here")
    arguments = parser.parse_args()
    generate(arguments.texture)
