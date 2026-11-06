# 餐盒模型与材质 / Lunchbox meshes and material

本版为 Project Zomboid 原版 `Base.Lunchbox` 的独立衍生资源：左右手模型、地面模型、XML、GUID、ModelScript 和材质分别使用新路径，不覆盖原版。首版保留原几何、UV、骨架、权重和绑定矩阵，主要变化为独立白紫色 ImageGen 材质；不将原网格宣称为完全重新建模。

This candidate derives independent resources from the vanilla `Base.Lunchbox`. It preserves the native geometry, UVs, skeleton, weights and bind matrices. XML/GUIDs, mesh paths, ground ModelScript and the white/lavender ImageGen material are independent. Vanilla files are never overwritten; the original meshes are not claimed as newly modeled originals.

## 运行接口 / Runtime interface

- `ReplaceInPrimaryHand = SuQingFreshnessLunchbox_RHand holdingbagright`
- `ReplaceInSecondHand = SuQingFreshnessLunchbox_LHand holdingbagleft`
- `WorldStaticModel = SuQingFreshnessLunchbox_Ground`
- 共享纹理 / shared texture: `Clothes/Bag/SuQingFreshnessLunchbox`, real RGB PNG, 256×256.
- 地面模型 / ground: independent binary FBX7300 copy, native ModelScript scale `0.4`.
- 左右手注册 / hand registration: `media/fileGuidTable.xml` maps both independent clothing XML paths to their existing unique GUIDs.
- 独立物品图标 / independent item icon: RGBA PNG `32×32`, size-only export from `art/item-icon-source.png`; separate mod icon stays `128×128`.

右手模型保留 `Bip01_R_Hand` 与 `Bip01_Prop1` 的64／112顶点分组；左手模型保留 `Bip01_L_Forearm` 与 `Bip01_Prop2` 的64／112分组。没有用右手镜像代替左手。每个文本X手模为176顶点／148三角面、36骨节点；地面FBX原始几何为80顶点／148三角面。原生Assimp按面展开UV后读出的三种模型都是444顶点／148面，这不是网格内容变化。

The right and left native skins remain distinct. Each textual X hand mesh has 176 source vertices, 148 triangles and 36 frame nodes. The ground FBX has 80 source positions and 148 triangles. The installed native Assimp importer expands all three to 444 vertices/148 faces because of per-face attributes; original and derived native geometry and UV buffers match exactly.

## 生成与验证 / Reproduction and verification

- `tools/assets_build.py --texture <ImageGen atlas>`：仅从原版复制独立模型引用，并对已生成材质做尺寸导出；不绘画、不手工补色。模型文件和材质引用可以复现。
- `tools/assets_validate.py`：输出 `art/model/asset_validation.json`，核对原件SHA-256、真实PNG、独立GUID、模型／纹理引用、UV、蒙皮权重及绑矩阵，并调用当前游戏的原生Assimp和ModelScript解析器做独立读回。
- `source-provenance.json`：原版来源路径／哈希、修改范围和本次纹理输入。
- `native_model_probe.txt`：原生解析对照结果；没有初始化游戏、世界、角色或OpenGL。
- `native_clothing_load_probe.txt`：实际`Item.Load → OutfitManager → ClothingItemAssetManager`独立异步加载回归；重现缺少GUID表时两手资产为null，补表后两手资产均READY。
- `uv_wireframe.png`、`uv_texture_debug_overlay.png`：仅用于UV检查，不是游戏贴图。
- `model_static_preview.png`：CPU网格投影，模型居中展示；不是实际角色手持姿势或Viewpoint实机截图。

The build script copies independent native model bindings and resizes the ImageGen atlas; it never repaints or manually repairs the production image. Validation includes original hashes, PNG decoding, independent GUIDs/references, exact UV/skin/bind preservation, and standalone installed Assimp/ModelScript parser checks. UV diagrams and centered CPU mesh projections are diagnostic artifacts only.

## 用户实测后修正 / Corrections after user testing

原候选虽然通过网格和XML解析，却没有提供模组`media/fileGuidTable.xml`。当前原生`OutfitManager.loadAllClothingItems`先查询此表，查询不到时不加载手持替换资产；XML内的GUID不能代替这一步注册。修正只增加两条映射，保持模型路径、GUID、原几何、蒙皮和材质不变。新增回归使用真实原生异步XML资产管理器，在隔离文件映射下验证双手资产READY；没有创建世界、人物或OpenGL上下文。

The previous candidate parsed correctly but omitted its mod GUID table. The native OutfitManager requires that table before loading either hand replacement; a GUID inside clothing XML alone is insufficient. The fix adds two mappings while retaining the models, GUIDs, geometry, skins and materials. The new standalone regression uses the actual asynchronous XML asset manager with isolated file mappings and verifies both assets reach READY without a world, character or OpenGL context.

用户截图中的巨大地面轮廓来自128像素物品图标与原版32像素图标的尺寸差异。原生FBO轮廓的sprite回退分支使用纹理宽高，单独缩`ScaleWorldIcon`不能可靠修正该分支。修正将既有独立生成的物品图标导出为32像素，保留高分辨率母版、模组icon、封面和地面3D模型`scale=0.4`。实际32像素查看仍能辨认紫白餐盒、提手和金色钟表；实际地面轮廓仍由用户游戏内验收。

The oversized ground outline is consistent with the 128px item icon versus vanilla's 32px texture. The native FBO sprite fallback uses texture dimensions, so changing ScaleWorldIcon alone does not reliably resize that path. The existing independently generated icon is exported at 32px; its master, mod icon, cover and ground 3D scale remain intact. The actual 32px icon remains readable as a purple/white lunchbox with handle and gold clock. Ground-outline appearance still requires user gameplay acceptance.

## Viewpoint与验收边界 / Viewpoint and acceptance limits

本机Viewpoint的 `Characters.snapshot → ModelCapture.capture/add/palette` 读取原生人物 ModelSlot、ModelInstanceRenderData、模型纹理及原生SkinningData／AnimationPlayer矩阵。首版按这条人物蒙皮链路准备资源，没有将世界冰箱OBJ ModelPack绑定当作手模适配依据。此项为代码静态审计；不宣称新盒已通过Viewpoint实机验收。

The installed Viewpoint character pipeline consumes native character model instances, textures and skin matrices. This candidate follows that native skinned-item path; the fridge's world OBJ ModelPack mechanism is not used as evidence for held-item support. This is a static compatibility assessment, not in-game acceptance.

用户需分别验收普通视角及Viewpoint第一／第三人称下的左右手装备、换手、走跑转身、另一手持物、餐盒比例／提柄贴合／遮挡，以及落地显示、拾取、保存重进。CPU预览和原生解析均不能代替这些操作。

The user must test left/right equip and switching, walking/running/turning, another held item, handle alignment, scale/occlusion, ground display/pickup and save/reload in ordinary and Viewpoint first/third-person views. Parser checks and CPU previews do not replace that acceptance session.


## rc.5 世界物品回退 / World-sprite fallback

新增 `media/inventory/world/WItem_SuQingFreshnessLunchbox.png`，32×32 RGBA透明，`UseWorldItem=true`、`ScaleWorldIcon=1`。背包icon保持原文件。`tools/assets_world_sprite.py` 从实际地面FBX节点变换、原UV和现有材质离线渲染三角网格，按原生投影估计校准落地点(16,24)；不使用旧CPU预览的自动居中/80%填幅。生产贴图不来自封面或库存图标缩图。

The separate transparent 32×32 world sprite is rendered from the actual ground mesh/node transform, original UVs and current material. The native sprite anchor is (16,24); the inventory icon and 0.4 model scale are retained. This does not use the older preview's automatic centering or 80% bounds fit.

此图只处理模型图集不可用时的sprite回退，为固定yaw=0投影；有效原生图集优先。没有强塞atlas缓存、改Java或全局渲染。任意旋转、扩展摆放及绝对相机对齐仍需用户验收，不能将离线投影称作游戏截图。记录见 `world-sprite-manifest.json`；默认 `assets_validate.py` 只做静态检查，`--native` 才显式运行限额JVM解析器，不把历史rc.4原生结果当本轮执行。

This is a fixed-yaw=0 fallback, with a valid native model atlas still preferred. No forced atlas cache, Java or global rendering patch is added. Arbitrary rotation, extended placement and absolute camera alignment remain user acceptance. `world-sprite-manifest.json` records provenance; `assets_validate.py` defaults to static-only checks and requires explicit `--native` for bounded standalone JVM parsers. Historical rc.4 parser results are not reported as newly executed.
