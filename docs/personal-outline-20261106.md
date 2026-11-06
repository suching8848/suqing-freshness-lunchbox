# 返鲜餐盒地面轮廓修正 / Ground-outline correction

2026-11-06T17:33:32.791324+08:00，个人餐盒安装更新至 **0.1.0-rc.5**。本轮由用户授权修复轮廓；游戏进程检查与Steam近期退出状态一致，未启动或操作游戏。用户此前反馈除轮廓贴合外未见其他明显问题，这不等同于完整兼容验收。

## 修改与判断

当前原生轮廓优先采用有效的WorldItemAtlas投影；有效图集缺失时退回sprite。当前餐盒原sprite来自正面箱形库存icon，而实际地面模型为原版薄餐盒衍生。静态检查未发现强制atlas命中的物品参数，也无法确定用户当帧是放置状态、图集未就绪、尺寸检查还是其他运行条件触发回退。因此本轮只修可验证的局部回退资源，不调整3D模型大小、不强塞图集缓存、不改Java或全局渲染。

新增 `42/media/inventory/world/WItem_SuQingFreshnessLunchbox.png`，并在物品脚本设 `UseWorldItem=true`、`ScaleWorldIcon=1.0`。世界贴图使用真实FBX网格、FBX节点变换、原UV和原有材质进行离线三角面/深度渲染。32×32透明画布、8倍采样、落地点(16,24)，不自动居中或按包围盒放大；模型缩放保持0.4。

保留库存icon、封面、服装GUID、左右手/地面模型、材质、返鲜Lua、两条配方和普通容器升级1.0.3。实际mod差异是新增1张PNG与修改5个旧文件（物品脚本、mod.info、CN/CH/EN介绍），没有删除；其余34个旧文件哈希不变。固定yaw=0回退图只用于原生图集不可用时，不能承诺任意旋转、扩展摆放及绝对相机偏移逐像素贴合。

## 验证与正式安装

- Python静态资产检查 **443项通过**，包括原资源哈希、几何/骨骼/UV/GUID、独立world路径、PNG格式/透明背景/边缘无裁切等。此次没有运行JVM或重复原生玩法测试；历史rc.4原生加载记录单独保留，不当作本轮执行结果。
- 新贴图投影与原生sprite锚点经协作者独立只读复核，无阻断项；库存icon和所有模型/材质保持原SHA。
- 当前JAR只读字节码确认旧物品读档会采用当前ScriptItem.UseWorldItem和世界贴图，不需要重新制作或物品迁移。
- **40个安装文件逐项SHA读回通过**；独立恢复目录中的39个原文件也与备份基线相同。
- **97项保护文件哈希不变**：包含正式档沙盒/启用名单/玩家与世界关键数据、新档名单、游戏/PZO设置、普通容器升级和返鲜冰箱文件。正式档餐盒/冰箱速率均保留0.25小时。
- 已安装：`C:\Users\15792\Zomboid\mods\SuQingFreshnessLunchbox`。

## 备份与恢复

仅备份餐盒模组及本轮涉及的开发资料，未新建大型世界副本：
`D:\GameBackups\ProjectZomboid\返鲜餐盒轮廓修复_20261106_172250`。

原安装完整归档：`D:\GameBackups\ProjectZomboid\返鲜餐盒轮廓修复_20261106_172250\installed-lunchbox-rc4-before.zip`，39文件；ZIP逐成员内容与源一致，SHA-256为 `3c75404582ae60594baf7099bf6c474f497f50e93d48c0a40b5a1bf9d429d854`。源码涉及文件另有独立归档，两个开发工具新增修改前副本保留于同目录。

原rc.4目录保留在mods扫描路径外：
`C:\Users\15792\Zomboid\CodexDeploymentRecovery\返鲜餐盒轮廓修复_20261106_172250\previous-lunchbox-rc4`。

需要回退时，先正常退出游戏，核对当时是否已有后续餐盒修改，再只恢复本轮备份的餐盒目录；不要覆盖世界、map_sand.bin、名单或其他模组。此处未执行回退。

## 用户验收

正常重启游戏，使用原有餐盒放地后悬停/选中，检查薄盒形状、大小、落地点和边缘。再比较摆放/旋转状态，记录仍有偏差的角度；必要时保存重进。离线投影不是游戏截图，真实贴合、Viewpoint与任意旋转仍待用户确认。未提交Git或发布工坊。

## English

Installed **0.1.0-rc.5** to the existing personal lunchbox after a verified 39-file backup. A separate transparent 32px world fallback is rendered from the actual ground FBX, node transform, original UVs and current material; `UseWorldItem=true` selects it while the inventory icon stays unchanged. The fixed-yaw projection uses the native (16,24) sprite anchor and retains the 0.4 ground-model scale. A valid native model atlas remains preferred. This corrects the fallback resource; it does not guarantee pixel-exact arbitrary rotations, extended placement or camera alignment.

443 static asset checks passed, 40 installed files were read back, and 97 protected-file hashes stayed unchanged. No JVM, game or gameplay automation was started. All freshness Lua, recipes, models, material, ordinary Container Upgrades 1.0.3 and save settings remain unchanged; both personal restoration rates stay at 0.25 hours. Existing lunchboxes adopt the current world texture on normal reload and need no recrafting. Actual visual acceptance belongs to the user. Recovery is limited to the backed-up lunchbox directory; no save rollback, Git commit or Workshop publication was performed.
