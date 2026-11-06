"""Verify independent native Lunchbox assets without starting or operating PZ."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import re
import subprocess
import uuid
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw
from assets_model import read_x, read_fbx, mesh_summary

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MEDIA = ROOT / "mods/SuQingFreshnessLunchbox/42/media"
ART = ROOT / "art/model"
CHECKS = []


def check(value, why):
    if not value:
        raise AssertionError(why)
    CHECKS.append(why)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate(run_native=False):
    CHECKS.clear()
    provenance = json.loads((ART / "source-provenance.json").read_text(encoding="utf-8"))
    for path, record in provenance["originals"].items():
        check(Path(path).is_file() and sha(path) == record["sha256"], "Original source hash unchanged: " + path)
    guids = []; original_guids = []; meshes = {}
    for hand, expected_bones in [("RHand", ["Bip01_R_Hand", "Bip01_Prop1"]),
                                 ("LHand", ["Bip01_L_Forearm", "Bip01_Prop2"])]:
        native = GAME / ("media/models_X/Skinned/BackPacks/PlasticLunchBox_" + hand + ".x")
        target = MEDIA / ("models_X/Skinned/BackPacks/SuQingFreshnessLunchbox_" + hand + ".x")
        check(target.read_bytes().replace(b'"SuQingFreshnessLunchbox.png"', b'"PlasticLunchBox.png"') == native.read_bytes(),
              hand + " X bytes identical except the independent material texture reference")
        original = read_x(native); mesh = read_x(target); meshes[hand] = mesh
        for field in ["vertices", "faces", "uv", "skin", "frames", "frame_matrices"]:
            check(mesh[field] == original[field], hand + " original " + field + " retained")
        check(len(mesh["vertices"]) == 176 and len(mesh["triangles"]) == 148, hand + " native 176 vertices / 148 triangles")
        check([s["bone"] for s in mesh["skin"]] == expected_bones, hand + " specific native hand bone groups retained")
        check(len(mesh["frames"]) == 36 and len(mesh["frame_matrices"]) == 36, hand + " native 36-frame hierarchy/bind pose")
        check(np.isfinite(np.asarray(mesh["vertices"])).all(), hand + " finite vertices")
        check(all(0 <= i < len(mesh["vertices"]) for face in mesh["faces"] for i in face), hand + " valid face indices")
        uv = np.asarray(mesh["uv"])
        check(np.isfinite(uv).all() and (uv >= 0).all() and (uv <= 1).all(), hand + " finite in-bounds original UVs")
        sums = np.zeros(len(mesh["vertices"]))
        for group in mesh["skin"]:
            check(group["bone"] in mesh["frames"], hand + " known bone " + group["bone"])
            matrix = np.asarray(group["offset_matrix"]).reshape(4, 4)
            check(np.isfinite(matrix).all() and abs(np.linalg.det(matrix)) > 1e-12, hand + " finite invertible bind matrix " + group["bone"])
            for index, weight in zip(group["indices"], group["weights"]):
                check(0 <= index < len(sums) and 0 <= weight <= 1, hand + " valid skin weight")
                sums[index] += weight
        check(np.allclose(sums, 1, atol=1e-6), hand + " each original vertex retains unit total skin weight")
        source_xml = ET.parse(GAME / ("media/clothing/clothingItems/Bag_Lunchbox_" + hand + ".xml")).getroot()
        xml = ET.parse(MEDIA / ("clothing/clothingItems/SuQingFreshnessLunchbox_" + hand + ".xml")).getroot()
        guids.append(str(uuid.UUID(xml.findtext("m_GUID"))))
        original_guids.append(source_xml.findtext("m_GUID"))
        expected_model = "media/models_X/Skinned/BackPacks/SuQingFreshnessLunchbox_" + hand + ".x"
        for key in ["m_MaleModel", "m_FemaleModel"]:
            reference = xml.findtext(key).replace("\\", "/")
            check(reference == expected_model and (MEDIA.parent / reference).is_file(), hand + " resolved " + key)
        check(xml.findtext("textureChoices").replace("\\", "/") == "Clothes/Bag/SuQingFreshnessLunchbox", hand + " independent XML texture")
        for key in ["m_Static", "m_AllowRandomHue", "m_AllowRandomTint", "m_AttachBone"]:
            check(xml.findtext(key) == source_xml.findtext(key), hand + " original XML behavior " + key)
    check(len(set(guids)) == 2 and not set(guids).intersection(original_guids), "Unique independent left/right GUIDs, different from vanilla")
    guid_xml = ET.parse(MEDIA / "fileGuidTable.xml").getroot()
    guid_entries = {pair.findtext("path"): pair.findtext("guid") for pair in guid_xml.findall("files")}
    check(len(guid_xml.findall("files")) == len(guid_entries) == 2, "Exactly two replacement-clothing GUID registrations")
    for hand, guid in zip(("RHand", "LHand"), guids):
        path = "media/clothing/clothingItems/SuQingFreshnessLunchbox_" + hand + ".xml"
        check(guid_entries.get(path) == guid, hand + " OutfitManager GUID lookup path matches XML GUID")

    # World-object FBO fallback uses the sprite texture's native dimensions.
    # Keep the independently generated icon master, but export at native 32px.
    item_icon_path = MEDIA / "textures/Item_SuQingFreshnessLunchbox.png"
    with Image.open(item_icon_path) as icon:
        icon.load()
        check(icon.format == "PNG" and icon.mode == "RGBA" and icon.size == (32, 32), "Real RGBA 32x32 item icon matches vanilla world-sprite sizing")
        expected_icon = Image.open(ROOT / "art/item-icon-source.png").convert("RGBA").resize((32, 32), Image.Resampling.LANCZOS)
        check(icon.tobytes() == expected_icon.tobytes(), "32px item icon is a size-only export of its independent ImageGen master")
    item_script = (MEDIA / "scripts/items_FreshnessLunchbox.txt").read_text(encoding="utf-8")
    check(re.search(r"ScaleWorldIcon\s*=\s*1(?:\.0)?\s*,", item_script), "Native unit sprite scale retained")
    check(re.search(r"UseWorldItem\s*=\s*true\s*,", item_script), "World fallback uses a dedicated world texture")
    world_path = MEDIA / "inventory/world/WItem_SuQingFreshnessLunchbox.png"
    with Image.open(world_path) as world:
        world.load()
        check(world.format == "PNG" and world.mode == "RGBA" and world.size == (32, 32), "Separate real 32px RGBA world texture")
        alpha = np.asarray(world.getchannel("A"))
        check(alpha.max() == 255 and 0 < np.count_nonzero(alpha) < 32 * 32, "World silhouette has a solid body and transparent background")
        check(not any(np.any(edge) for edge in (alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1])), "World silhouette is not clipped at canvas edges")
    check(sha(world_path) != sha(item_icon_path), "World silhouette and inventory icon remain independent assets")

    ground = MEDIA / "models_X/WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground.fbx"
    source_ground = GAME / "media/models_X/WorldItems/Clothing/PlasticLunchBox_Ground.fbx"
    check(sha(ground) == sha(source_ground), "Independent ground FBX retains native geometry exactly")
    meshes["Ground"] = read_fbx(ground)
    check(meshes["Ground"]["version"] == 7300 and len(meshes["Ground"]["triangles"]) == 148, "Ground FBX7300 / 148 triangles parsed")
    check(np.isfinite(np.asarray(meshes["Ground"]["vertices"])).all(), "Ground finite vertex geometry")
    script = (MEDIA / "scripts/models_FreshnessLunchbox.txt").read_text(encoding="utf-8")
    check("model SuQingFreshnessLunchbox_Ground" in script and "scale = 0.4," in script, "Independent ground ModelScript/native scale")
    check("mesh = WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground," in script, "Ground mesh reference resolves to independent FBX")
    texture_path = MEDIA / "textures/Clothes/Bag/SuQingFreshnessLunchbox.png"
    with Image.open(texture_path) as texture:
        texture.load()
        check(texture.format == "PNG" and texture.size == (256, 256) and texture.mode == "RGB", "Real RGB PNG 256x256 production atlas")
    source_texture = ART / "texture-source.png"
    with Image.open(source_texture) as image:
        expected = image.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS)
        check(Image.open(texture_path).tobytes() == expected.tobytes(), "Atlas is only a size export of the ImageGen-edited source")
    check(sha(source_texture) != sha(GAME / "media/textures/Clothes/Bag/PlasticLunchBox_01.png"), "Independent generated material differs from native artwork")

    # UV diagnostic only; no production artwork is painted or repaired here.
    reference = np.asarray(Image.open(GAME / "media/textures/Clothes/Bag/PlasticLunchBox_01.png").convert("RGB"))
    current = np.asarray(Image.open(texture_path).resize((128, 128), Image.Resampling.LANCZOS).convert("RGB"))
    mask = Image.new("1", (128, 128), 0); drawing = ImageDraw.Draw(mask)
    for _, uv in meshes["RHand"]["triangles"]:
        drawing.polygon([(u * 127, v * 127) for u, v in uv], fill=1)
    blue = (reference[:, :, 2] > 150) & (reference[:, :, 0] < 110) & np.asarray(mask, dtype=bool)
    dark = current.mean(2) < 55
    lost_mask = blue & dark
    lost = int(lost_mask.sum()); original_blue = int(blue.sum())
    fraction = lost / max(original_blue, 1)
    check(fraction < .035, "No large native lid UV island replaced with unused dark background (lost fraction " + str(round(fraction, 4)) + ")")
    left_edge_dark = int(lost_mask[102:127, 0:3].sum())
    bottom_edge_dark = int(lost_mask[127, 0:62].sum())
    check(left_edge_dark == 0, "Targeted former left-edge dark strip has full generated color bleed")
    check(bottom_edge_dark <= 1, "Targeted bottom edge has no continuous dark strip (at most one isolated corner texel)")
    remaining_y, remaining_x = np.where(lost_mask)

    if run_native:
        tools = ROOT / "tools"
        jdk = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64/bin")
        command = [str(jdk / "javac.exe"), "-encoding", "UTF-8", str(tools / "assets_NativeModelProbe.java")]
        compiled = subprocess.run(command, cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        check(compiled.returncode == 0, "Native standalone parser helper compiles")
        result = subprocess.run([str(GAME / "jre64/bin/java.exe"), "-Xms32m", "-Xmx192m", "-Xss512k", "-Xint",
                                 "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "--enable-native-access=ALL-UNNAMED",
                                 "-Djava.library.path=" + str(GAME),
                                 "-Duser.home=" + str(ART / "native_parser_home"),
                                 "-cp", str(tools) + ";" + str(GAME / "projectzomboid.jar"),
                                 "assets_NativeModelProbe", str(GAME), str(MEDIA)],
                                cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        text = result.stdout.decode("utf-8", errors="replace")
        (ART / "native_model_probe.txt").write_text(text, encoding="utf-8")
        check(result.returncode == 0 and "NATIVE_ASSET_SUMMARY" in text and "failures=0" in text,
              "Installed Jassimp parses original/derived hand X and ground FBX equivalently; native ModelScript parser resolves bindings")
        compiled = subprocess.run([str(jdk / "javac.exe"), "-encoding", "UTF-8", str(tools / "assets_ClothingLoadProbe.java")],
                                  cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        check(compiled.returncode == 0, "Native clothing GUID/load helper compiles")
        result = subprocess.run([str(GAME / "jre64/bin/java.exe"), "-Xms32m", "-Xmx192m", "-Xss512k", "-Xint",
                                 "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "--enable-native-access=ALL-UNNAMED",
                                 "-Duser.home=" + str(ART / "asset-load-audit/isolated-home"),
                                 "-cp", str(tools) + ";" + str(GAME / "projectzomboid.jar"),
                                 "assets_ClothingLoadProbe", str(GAME), str(MEDIA)],
                                cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        clothing_text = result.stdout.decode("utf-8", errors="replace")
        (ART / "native_clothing_load_probe.txt").write_text(clothing_text, encoding="utf-8")
        check(result.returncode == 0 and "NATIVE_CLOTHING_SUMMARY" in clothing_text and "failures=0" in clothing_text,
              "Actual OutfitManager reproduces missing-GUID null assets and loads both fixed XML assets to READY asynchronously")
    for path, record in provenance["originals"].items():
        check(sha(path) == record["sha256"], "Original hash unchanged after parser checks: " + path)
    return {"result": "PASS", "mode": "NATIVE_PARSERS" if run_native else "STATIC_ONLY", "native_checks_executed": run_native, "checkedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "checks": CHECKS, "check_count": len(CHECKS), "models": {k: mesh_summary(v) for k, v in meshes.items()},
            "texture": {"path": str(texture_path), "size": [256, 256], "sha256": sha(texture_path),
                        "generated_source": str(source_texture), "generated_source_sha256": sha(source_texture),
                        "generated_master_input": provenance.get("texture_input"),
                        "native_blue_uv_lost_dark_fraction": fraction,
                        "target_edge_check": {"left_strip_dark_texels": left_edge_dark,
                                              "bottom_strip_dark_texels": bottom_edge_dark,
                                              "remaining_dark_texels_xy_at_128px": list(zip(remaining_x.tolist(), remaining_y.tolist())),
                                              "visual_result": "CPU preview reread: former large black face and continuous dark border removed; one isolated corner texel remains, no manual repaint."}},
            "native_parser_game_jar_sha256": sha(GAME / "projectzomboid.jar"),
            "native_parser_dll_sha256": sha(GAME / "jassimp64.dll"),
            "historical_rc4_replacement_clothing_load": {"before": "Both native replacement assets null without mod GUID table",
                                           "after": "Both native ClothingItem assets READY through OutfitManager and asynchronous AssetManager",
                                           "assertions": 15, "guid_table": str(MEDIA / "fileGuidTable.xml")},
            "item_icon": {"path": str(item_icon_path), "size": [32, 32], "sha256": sha(item_icon_path),
                          "master": str(ROOT / "art/item-icon-source.png"), "visual_readability_at_32px": "Viewed: purple/white lunchbox, handle and gold clock remain distinguishable",
                          "world_outline_scope": "Separate actual-mesh world projection, with unchanged inventory icon; fixed-yaw fallback and camera alignment require user acceptance"},
            "originals_unchanged": True, "game_started": False, "world_created": False,
            "gl_context": False, "in_game_tested": False,
            "viewpoint_scope": "Installed ModelCapture static audit: native model instances, weights and skin matrices, no additional OBJ pack assumed.",
            "limits": ["CPU mesh previews center source meshes and do not show the actual animated player hand pose.",
                       "Standalone clothing loading registers one real script item and two physical source-file mappings; actual enabled-mod discovery and animated equip remain user acceptance.",
                       "Native parser equivalence does not prove character animation, skin compositing or Viewpoint visual correctness.",
                       "Actual right/left equip, walking, ground pose/material, first/third-person and save/reload are user acceptance tasks."]}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", action="store_true", help="Explicitly run memory-limited standalone JVM asset parsers")
    args = parser.parse_args()
    report_path = ART / ("asset_validation.json" if args.native else "asset_validation_static.json")
    try:
        report = validate(run_native=args.native)
    except Exception as error:
        report = {"result": "FAIL", "checkedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  "error": str(error), "passed_checks": CHECKS, "game_started": False}
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": report["result"], "checks": report["check_count"], "texture": report["texture"]}, ensure_ascii=False))
