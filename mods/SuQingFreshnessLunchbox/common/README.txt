蘇清的返鲜餐盒 / SuQing's Freshness Lunchbox 0.1.0-rc.8-perf.8
B42.21 单人离线候选；个人部署以交付回执为准，本候选未上传工坊。游戏内效果待用户验证。
接入背包已有底部睡袋／帐篷位（普通、大型、ALICE），与帐篷共用位置。挂上后仍可取放食品与返鲜；强化／还原前先卸下并清空。外挂负重按原生规则，不套用手持容器减重。

B42.21 single-player offline candidate; see the delivery receipt for personal deployment. This candidate is not uploaded to Workshop. Gameplay acceptance pending.
Uses an existing normal/large/ALICE backpack bottom bedroll/tent slot, shared with its original item. Attached food access and freshness restoration remain available. Detach and empty before upgrades/restoration. Attached weight follows native rules, without hand-container weight reduction.

rc.7：修复车辆Set迭代与外挂模型注释注册，精简物品悬浮说明。
rc.7: Fix vehicle Set iteration and attached-model comment parsing; shorten item tooltips.

rc.8：普通底部挂点上提0.08模型单位，以传奇背包为校准参照；深度、旋转和大小保留。
rc.8: Raises the regular bottom slot by0.08 model units, using Legendary Backpack as the reference; depth, rotation and scale remain.

rc.8-perf.1：普通冷藏食品跳过无需的餐盒写入作用域，减少无关检查和临时表；实际餐盒食品保持作用域保护。冷藏版本门禁、结算频率、返鲜、温度、存档及rc.8挂点保持。
rc.8-perf.1: Ordinary refrigerated food bypasses unnecessary lunchbox write scopes, avoiding unrelated checks and result tables. Scoped lunchbox food retains protection. Cooling gates, cadence, restoration, temperature, saves and rc.8 attachments remain.

rc.8-perf.3：精确支持冷藏升级1.0.0-rc.2-perf.1／perf.2／perf.3；保留既有餐盒写入作用域及原生调用链校验，未知版本继续拒绝。物品、挂点、配方、返鲜规则及存档键保持。
rc.8-perf.3: Supports exactly Cooling Upgrades 1.0.0-rc.2-perf.1/perf.2/perf.3. Existing lunchbox write scopes and native hook checks remain; unknown versions stay rejected. Items, attachments, recipes, restoration rules and save keys remain.

rc.8-perf.4：新增冷藏升级1.0.0-rc.2-perf.4的精确兼容门禁；该冷藏热修校正物品栏显示复用的游戏版本识别。其余餐盒逻辑及调用链校验保持。
rc.8-perf.4: Adds the exact compatibility gate for Cooling Upgrades 1.0.0-rc.2-perf.4, whose hotfix corrects game-version recognition for inventory display reuse. Other lunchbox logic and hook checks remain.

rc.8-perf.5：新增冷藏升级1.0.0-rc.2-perf.5的精确兼容门禁，配合其已审物品栏分支及显示快照修复；保留原有餐盒写入作用域及调用链校验。
rc.8-perf.5: Adds the exact compatibility gate for Cooling Upgrades 1.0.0-rc.2-perf.5 and its audited inventory-branch and display-snapshot fixes. Existing lunchbox write scopes and hook checks remain.

rc.8-perf.6：新增冷藏升级1.0.0-rc.2-perf.6的精确兼容门禁，配合其显示包装链延后安装；保留餐盒写入作用域及调用链校验。
rc.8-perf.6: Adds the exact gate for Cooling Upgrades 1.0.0-rc.2-perf.6 and its deferred display-wrapper-chain installation. Existing lunchbox write scopes and hook checks remain.

rc.8-perf.7：新增冷藏升级1.0.0-rc.2-perf.7的精确兼容门禁，配合其Lua结算开销优化；保留餐盒写入作用域、原生调用链校验及返鲜规则。
rc.8-perf.7: Adds the exact gate for Cooling Upgrades 1.0.0-rc.2-perf.7 and its Lua settlement overhead optimization. Lunchbox write scopes, native hook checks and restoration rules remain.

rc.8-perf.8：精确新增冷藏升级1.0.0-rc.2-perf.8门禁，保留perf.1–7与全部既有身份／写入作用域检查。配合其可选Java接管原型；餐盒自身不要求Java、物品及挂点模型不变。源码离线阶段，未部署／游戏验收／发布。
rc.8-perf.8: Adds exact Cooling Upgrades1.0.0-rc.2-perf.8 support while retaining perf.1–7 and every captured-identity/write-scope check. Covers its optional Java backend prototype; Lunchbox itself does not require Java, and items/attachment models remain. Source/offline only, not deployed, accepted in-game or published.
