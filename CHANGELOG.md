# 0.2.0-rc.4 — 2026-11-11

与 Loot Tracker 1.8.5 共用库存选择接口时，保留搜刮记录及密封限制。

Preserves Loot Tracker 1.8.5 search tracking and sealed-container restrictions when they share inventory selection.

# 0.2.0-rc.3 — 2026-11-11

首次尝试封箱前核对库存锁定接口，接入启动阶段延迟安装的库存包装。

Finalizes inventory locks before the first seal, including wrappers installed late during startup.

# 0.2.0-rc.2 — 2026-11-10

批次时长下限调整为 0.25 游戏小时。

The minimum batch duration is now 0.25 game hours.

# 0.2.0-rc.1 — 2026-11-10

手动封盒批次返鲜。开始时记录一批食品，封盒期间锁定内容物，到期一次恢复新鲜并解锁。餐盒独立沙盒默认12游戏小时，范围0.5–24。批次进度随餐盒存档。

Adds manual sealed restoration batches. Start records one group of foods, locks access and restores freshness once at the deadline. Independent lunchbox sandbox duration defaults to 12 game hours, range 0.5–24. Batch state saves with the box.

# 0.1.0-rc.8-perf.9.1 — 2026-11-09

B42.22.2 单人适配候选，保留 B42.21 加载范围及 perf.9 的结算。沿用物品 ID、挂点、容器升级记录和食品账本。缺少冷藏升级或其 Java 后端时，餐盒继续使用自身 Lua 返鲜。便携冷藏和 Viewpoint 的新版联测需单独验收。

Single-player compatibility candidate for B42.22.2. It retains B42.21 loading and perf.9 settlement, using the same item ID, attachment slots, container upgrades and food ledger. The lunchbox runs its own Lua restoration when Refrigeration Upgrades or its Java backend is absent. Portable refrigeration and Viewpoint need separate B42.22.2 gameplay validation.

# 0.1.0-rc.8-perf.9 — 2026-11-09

中文：在稳定的餐盒结算中复用本轮归属与时间线校验。食品连续处于当前历史段时直接结算，历史缺口仍走完整校验。相同游戏时刻可跳过已确认无变化的年龄与记录写入。原生容器回调触发转移时按当前归属处理。适用于 B42.21 单人，沿用现有 Lua 返鲜时机、物品 ID 与存档记录。候选版，实机帧率待对照。

English: Reuses membership and timeline validation during a stable lunchbox pass. Food covered by the current segment takes the direct path. Gaps still go through full coverage checks. Verified unchanged age and record writes can be skipped at the same game time. Transfers during native container callbacks are checked against live ownership. Targets B42.21 single-player and retains the Lua settlement cadence, item IDs and save records. Candidate pending an in-game performance comparison.

# 0.1.0-rc.8-perf.8 — 2026-11-07

中文：合并已部署的背包底部挂点、车辆Set迭代、模型注册和简短提示修复，并保留普通底部位上提0.08的rc.8校准。使用背包已有普通／大型／ALICE睡袋或帐篷位，与原物品共用，不新增槽位或强制背包前置。挂载时保留食品取放与返鲜；普通容器升级／还原前须卸下并清空。精确支持已审冷藏perf.1–8，普通冷藏食品跳过无关餐盒写入scope，保留需要保护的食品及全部钩子身份检查。 原生模型与车辆集合、挂点及冷藏组合离线检查已通过；用户已反馈rc.7模型可显示。rc.8精确贴合、动画、Viewpoint、特殊装备转换与完整保存重进仍需用户验收。餐盒返鲜规则、ID、保存记录和已选封面／图标保持，不新增Java依赖；可选原生接管属于冷藏主模组的独立补丁。

English: Includes the deployed backpack-bottom attachment, vehicle Set iteration, model-registration and concise-tooltip fixes, retaining rc.8’s0.08 upward adjustment of the regular bottom slot. Uses an existing normal/large/ALICE bedroll or tent slot, shared with its original item, without new slots or a mandatory backpack mod. Attached food access/restoration remain; detach and empty before ordinary upgrades/restoration. Supports exactly audited Coolingperf.1–8, avoiding unrelated lunchbox write scopes for ordinary cold food while preserving protected-food scopes and every hook-identity check. Offline native model/vehicle-collection, attachment and Cooling combination checks pass; the user reported the rc.7 model displaying. Exact rc.8 fit, animations, Viewpoint, special equipment conversion and complete save/reload still need user acceptance. Lunchbox restoration rules, IDs, save records and selected cover/icon remain; no Java dependency is added. Optional native takeover belongs to the refrigeration base’s separate companion.
