蘇清的返鲜餐盒 / SuQing's Freshness Lunchbox 0.2.0-rc.4
B42.22.2 单人批次候选。放入食品后右键开启返鲜，封盒期间锁住取放。到期统一恢复新鲜。餐盒独立沙盒默认12游戏小时，范围0.25–24。
背包底部挂点仍可搬运餐盒。批次结束后再清空升级、停用或回退。

B42.22.2 single-player batch candidate. Load eligible food and start from the context menu. Contents stay sealed until completion. The separate sandbox duration defaults to 12 game hours, range 0.25–24.
The box can still be carried on a backpack attachment. Finish batches before upgrading, disabling or rolling back.

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
