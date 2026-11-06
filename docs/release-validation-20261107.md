# 0.1.0-rc.8-perf.8 发布验证 / Release validation

原生模型与车辆集合、挂点及冷藏组合离线检查已通过；用户已反馈rc.7模型可显示。rc.8精确贴合、动画、Viewpoint、特殊装备转换与完整保存重进仍需用户验收。餐盒返鲜规则、ID、保存记录和已选封面／图标保持，不新增Java依赖；可选原生接管属于冷藏主模组的独立补丁。

Offline native model/vehicle-collection, attachment and Cooling combination checks pass; the user reported the rc.7 model displaying. Exact rc.8 fit, animations, Viewpoint, special equipment conversion and complete save/reload still need user acceptance. Lunchbox restoration rules, IDs, save records and selected cover/icon remain; no Java dependency is added. Optional native takeover belongs to the refrigeration base’s separate companion.

本轮只同步授权源码和工坊资料；原物品、模组ID及既有启用顺序保持。不把其他场景的帧率或离线调用数当成本版本的量化FPS收益。

Only authorized source and publishing material are synchronized; item/Mod IDs and existing enabled order remain. Neither another scene’s frame rate nor offline call counts are claimed as this release’s quantified FPS gain.

离线：当前精确Main perf8/Lunch perf8/Fridge perf.1组合13场景2181断言通过；Java API缺失的既有native方法host范围，不能代替Java-active世界验收。精确门禁perf.1–8、未知版本与身份漂移拒绝另行通过。保留车辆Set、完整模型注册与挂点源回归。

Offline: exact Mainperf8/Lunchperf8/Fridgeperf.1 tuple passes13 cases/2181 assertions in the established API-absent native-method host, not a Java-active world. Exactperf.1–8 gates reject unknown versions and changed identities. Vehicle Set, full model registration and attachment source regressions are retained.

## 公开工坊发布核验 / Public Workshop verification

版本`0.1.0-rc.8-perf.8`已于`2026-11-07T06:52:13.557388+08:00`经原生Steam SDK核验为公开（visibility 0），沿用条目`3834693433`。标题、描述、元数据中的内容树摘要、内容总字节数、标签、预览及依赖检查通过。公开摘要见[publication-20261107.json](../publishing/publication-20261107.json)。这不是远端逐文件下载SHA校验，也不增加游戏内验收范围。

Native Steam SDK verified version `0.1.0-rc.8-perf.8` on public item `3834693433` at `2026-11-07T06:52:13.557388+08:00`. Exact text, metadata tree hash, content-byte total, tags, preview policy and dependencies passed. This is not a remote per-file SHA download and does not extend gameplay acceptance.
