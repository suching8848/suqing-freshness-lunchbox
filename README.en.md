# SuQing's Freshness Lunchbox / 蘇清的返鲜餐盒

Current item identity, visibility and upload status: [workshop-item.json](publishing/workshop-item.json). Frozen manifests under release/ retain their preparation-time state; an old uploaded=false value there does not describe the current Steam item.

Public Workshop release **0.2.0-rc.4** includes optional attached weight fix **0.1.0-rc.1**. [Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3834693433) · [Publication record](publishing/publication-20261111.json)

**0.2.0-rc.4** is a Project Zomboid B42.22.2 single-player batch restoration candidate. The mod ID is `SuQingFreshnessLunchbox` and the item ID is `SuQingFreshnessLunchbox.FreshnessLunchbox`.

Preserves Loot Tracker 1.8.5 search tracking and sealed-container restrictions when they share inventory selection.

The optional SuQing's Lunchbox Attached Weight Fix, `SuQingLunchboxAttachedWeight_4222`, applies the current container reduction to the contents of a backpack-bottom lunchbox. It supports B42.22.2 single-player and requires ZombieBuddy 2.3.4 and Java mod approval. The Workshop item contains both mods. Enable the weight fix separately alongside the lunchbox and ZombieBuddy, approve its Java mod, and fully restart. Disable the fix and restart to resume native attached weight. Native checks passed offline. The local game log confirms that ZombieBuddy loaded and applied the patch. Gameplay weight measurement is pending.

Load eligible food and start a batch from the lunchbox context menu. The sealed box can be moved as a whole. Access to its contents stays locked while the batch runs. At the deadline, the batch restores the recorded items to fresh and unlocks. An overdue batch completes once the box is loaded again. The clock follows game time.

The earlier **rc.5 ground-outline correction** follows the user's report that the remaining visible issue is outline alignment. That report does not establish exhaustive compatibility acceptance. A separate transparent 32×32 world sprite is rendered offline from the actual ground FBX, current material and native projection parameters, then selected through the native `UseWorldItem` fallback. Inventory art, models, freshness behavior, recipes, ordinary upgrades and sandbox rules are retained.

See the [outline fix record](docs/personal-outline-20261106.md) for this task's backup, verification and personal deployment. The [rc.4 hotfix record](docs/personal-hotfix-20261106.md) remains historical. No game was started or operated, and no Git commit or Workshop publication was made.

## Current release and validation scope (2026-11-07)

Includes the deployed backpack-bottom attachment, vehicle Set iteration, model-registration and concise-tooltip fixes, retaining rc.8’s0.08 upward adjustment of the regular bottom slot. Uses an existing normal/large/ALICE bedroll or tent slot, shared with its original item, without new slots or a mandatory backpack mod. Attached food access/restoration remain; detach and empty before ordinary upgrades/restoration. Supports exactly audited Coolingperf.1–8, avoiding unrelated lunchbox write scopes for ordinary cold food while preserving protected-food scopes and every hook-identity check.

Offline native model/vehicle-collection, attachment and Cooling combination checks pass; the user reported the rc.7 model displaying. Exact rc.8 fit, animations, Viewpoint, special equipment conversion and complete save/reload still need user acceptance. Lunchbox restoration rules, IDs, save records and selected cover/icon remain; no Java dependency is added. Optional native takeover belongs to the refrigeration base’s separate companion.

See the [current validation summary](docs/release-validation-20261107.md). Earlier per-stage figures and “not published” notes describe historical checkpoints, not current FPS or upload-status claims.

## rc.8-perf.7 background-snapshot compatibility (2026-11-07)

Precisely supports cooling perf.7 while retaining all prior gates. Cooling maintains complete UI signatures only for recently displayed food, avoiding three background getters per food per Tick while retaining native protection and values. Lunchbox changes only version support; restoration, records, capacity, models and attachments remain. Lua-only, no added Java dependency; live performance remains pending.

## rc.8-perf.6 deferred render-wrapper compatibility (2026-11-07)

Precisely supports cooling perf.6 while retaining prior versions and all identity checks. Cooling waits for proximity-selection and deferred first-normal-Tick search wrapping before installing its display context. Lunchbox restoration, records, capacity, models and attachments are retained. Live activation and FPS remain unverified.

## rc.8-perf.5 native-branch and display-precision compatibility (2026-11-07)

Precisely supports reviewed cooling perf.5 while retaining existing versions and identity checks. Only lunchbox gates/metadata change. Cooling recognizes native-selected P4 3.8.1/42.15 and checks ledger/native heat against separate snapshots. Lunchbox freshness, records, capacity, models and attachments remain.

## rc.8-perf.4 display-gate hotfix compatibility (2026-11-07)

Adds precise cooling perf.4 support while retaining reviewed older versions and all source/instance/hook identity checks. Only lunchbox version and bridge gates change. Cooling perf.4 corrects native Core version/build recognition; settlement and caching remain unchanged.

## rc.8-perf.3 cooling state-cache compatibility (2026-11-07)

Precisely supports the reviewed cooling perf.1/perf.2/perf.3 versions while retaining source/instance/native-aging/setter identity checks and ordinary-food delegation. Only lunchbox version and bridge gates change; caching, immediate event settlement and display reuse belong to the cooling mod. Lunchbox freshness, records, capacity and rc.8 attachments remain. Unknown cooling versions are still rejected. Personal deployment, offline checks and user acceptance are recorded separately.

## rc.8-perf.1 cooling bridge performance fix (2026-11-07)

Current-scene Lua stack samples identify cooling settlement as the main hotspot. Calls that need no lunchbox write scope now delegate directly to the original cooling function, avoiding unrelated container lookups, bridge checks and protected result tables. Scoped lunchbox food retains the protected call and restoration path. The cooling version gate, settlement cadence, freshness, temperature, restoration rules, save structure and rc.8 attachments remain. Sample shares and offline call counts are not measured FPS gains; the user must retest in-game performance.

## rc.8 regular bottom position calibration (2026-11-07)

The user's Legendary Backpack screenshot confirms the rc.7 model is visible but hangs too far below the bag. The water suffix is fluid display, not a different slot. Only regular bottom Z rises by0.08; depth, rotation, scale and Big/ALICE remain. The screenshot-based estimate is44–46px; actual fit still needs user acceptance. All backpacks using the shared regular bottom location inherit this height adjustment.

Full native registration, TRS delta, seven Lua compilations and freeze/ZIP preservation checks pass. The user subsequently confirmed exit and authorized deployment after verification. Personal mods now contain **rc.8**, with43 runtime hashes verified and184 protected files unchanged. rc.7 fixes and compact tooltips remain; no Workshop upload. See [position calibration](docs/rc8-position-calibration-20261107.txt).

## rc.7 vehicle scanning, model registration and compact tooltips (2026-11-07)

The user's rc.6 test exposed two offline coverage gaps: indexing the current vehicle HashSet disabled the freshness runtime, and an unsupported line comment prevented registration of the new attached model. rc.7 uses Set iteration and a supported block comment, and cuts item tooltip length by more than half. The vehicle misuse existed in rc.5; the model comment was introduced in rc.6.

Real collection/Lua-exposure and full native model-registration regressions reproduce the old failures and pass the fixes. Existing runtime mocks and all7 Lua compilations pass. After normal game exit, personal **rc.7** was deployed under user authorization:43 runtime hashes match the freeze and184 protected files remain unchanged. Geometry, textures, food rules, payment records and attachment scope remain. No Workshop upload; the latest verified private upload remains rc.5. See [the hotfix handoff](docs/rc7-vehicle-model-tooltip-hotfix-20261107.txt). In-game vehicle/model/tooltip/save-reload acceptance remains with the user.

## rc.6 backpack bottom attachment candidate (2026-11-07)

The development phase prepared a candidate only. The user subsequently authorized local deployment on2026-11-07: personal mods then contained **rc.6**, with both previous installation and old upload staging preserved. The latest verified private Workshop version remains rc.5; **no Workshop upload was performed**. See [the deployment record](docs/personal-attachment-deployment-20261107.txt) for the native directory readback, recovery paths and pending gameplay acceptance.

- A dedicated attachment type extends only existing `BedrollBottom`, `BedrollBottomBig` and `BedrollBottomALICE` slots. Legendary Backpacks and BackpackSystem are supported when they provide those native locations. No new slot is added. The lunchbox shares its location with the original tent/bedroll and uses native replacement/detach actions.
- A dedicated attached StaticModel reuses the current mesh and white/lavender texture with three item-side anchors. Existing hand models, ground model and outline remain. Upstream backpacks, skeletons and Workshop originals are untouched.
- A lunchbox actually attached to the current actor and directly owned by that actor's main inventory gains one container button for direct food access. Freshness restoration continues through its existing inventory ownership rules. Refreshes cannot duplicate buttons.
- Ordinary Container Upgrades 1.0.3 retains all five tiers and restoration. A narrow attached-lunchbox guard requires detaching and emptying before either operation; other targets, payment records, refunds and the existing EX crafting chain remain.
- Weight follows the current native `getHotbarEquippedWeight`: the ordinary attached path uses approximately 70% of the lunchbox's own weight plus contents. It does not use the hand/worn container WeightReduction or stack the backpack's reduction. Paid capacity/reduction values remain stored and normal native ownership rules resume after detaching. This candidate adds no special weight discount.
- Existing boxes obtain the current attachment type and StaticModel from the current item script when reloaded. No new item ID, recrafting, food migration or ModData conversion. Freshness calculations, sandbox options, crafting costs, food restrictions and existing art remain.
- This section records the earlier B42.21 single-player attachment checks. Native parser and simulated checks do not establish visuals or gameplay. Normal/Viewpoint rendering, walking/running/crouching, backpack changes/removal, slot replacement, food access and save/reload require user acceptance. Model anchors are calibrated offline; actual clipping/orientation remain unverified.

See `docs/attachment-candidate-20261107.txt` for the handoff. Historical frozen releases are retained. No enable lists, saves, user settings, Git commits or publication state are changed.

## rc.5 outline correction and limits

- Retain the independent inventory icon. Add `media/inventory/world/WItem_SuQingFreshnessLunchbox.png`, enable `UseWorldItem=true`, and retain unit `ScaleWorldIcon=1`.
- Render the actual mesh using its FBX node transform, original UVs and current material. The world sprite is not a reduced inventory icon or cover. Its ground anchor is (16,24) on a 32px canvas; the 3D ground ModelScript scale remains 0.4.
- A valid native model atlas remains preferred; the new world image is used only by the sprite fallback. Java, global rendering and PZO configuration are untouched.
- The fallback is a fixed-yaw=0 projection. It improves the former front-facing suitcase silhouette but does not promise exact arbitrary rotation, extended-placement or camera alignment. User gameplay acceptance is required.
- Existing lunchboxes read the current script and world texture after normal reload. No recrafting, item migration or save rollback is needed.

## Defaults and settings

- Capacity **4**, weight **1.0**, weight reduction **50%**, based on the installed vanilla `Base.Lunchbox`.
- Lunchbox sandbox settings cover the master switch, initial capacity, batch duration and rotten-food permission. The fridge uses its own settings.
- Base capacity defaults to 4, range 1–30, and applies once to new lunchboxes. Existing boxes and upgrades retain their capacity.
- `SuQingFreshnessLunchbox.BatchHours` defaults to **12 game hours**, range **0.25–24**. Each batch keeps the deadline set when it starts. The master switch controls new batches.
- Each batch accepts directly stored food with supported perishable lifetimes. Remove burnt food, fertilized eggs, tainted food and unsupported items before starting. Rotten-food eligibility follows the sandbox setting.
- Completion keeps the original items, including their portions, cooking state, poison and contamination, and restores the original spoilage and cooking attributes. Finish active batches before disabling or rolling back the mod. Mods that manipulate native inventories directly require separate validation.

The vanilla `MaxItemSize=1` is preserved and the container accepts standard Food only. Actual drag/drop and third-party food combinations require user acceptance; added capacity does not remove size restrictions. Continuous power and battery replacement are outside this candidate's mechanics.

## Crafting and optional upgrades

Native crafting offers two recipes with the same output. A screwdriver is retained in both:

1. One empty vanilla lunchbox, one pocket watch, one digital watch, one classic analog wristwatch and two electric wires.
2. Two small metal sheets, one pocket watch, one digital watch, one classic analog wristwatch and two electric wires.

Common vanilla digital/classic left/right and color variants are accepted as separate families; three distinct physical timepieces are required. Native crafting owns payment and cancellation, with no separate refund loop. The lunchbox conversion input must be empty, out of both hands and free of container-upgrade records. The metal-sheet route does not require an existing lunchbox.

Ordinary `SuQingContainerUpgrade_4221` main mod **1.0.3** includes support for this lunchbox. No separate lunchbox compatibility submod is required. The lunchbox has no dependency on ordinary Container Upgrades: crafting, food storage and freshness restoration work independently when that mod is absent or disabled.

With a supporting ordinary-upgrade version enabled, the original capacity targets 12/20/30/40/49, weight-reduction targets 90/93/95/97/99, material/skill requirements, paid ledger, precise restoration and 50% paid-material refunds are retained. Detach, empty and unhand the box before upgrading/restoring. Freshness initializes base capacity once and never writes an upgraded box back to 4. This support does not automatically add the box to EX/Auto.

This outline correction updates only Freshness Lunchbox to 0.1.0-rc.5; the installed ordinary Container Upgrades 1.0.3 stays unchanged. The historical deployment record covers the original 1.0.0 backup and recovery directory, the save-only lunchbox addition and the unchanged new-save default. For other manual installations, exit the game normally and avoid duplicate loadable copies with the same Mod ID. The lunchbox still works independently without ordinary upgrades.

The existing `Codex_SuQingWearableCompat_4221` still handles other compatibility work, including HavenFall EX. Removing the lunchbox-specific companion is not a reason to disable it; retain its existing optional enablement.

The rc.3 correction to when the lunchbox crafting preflight is installed is retained to preserve the existing HavenFall EX crafting chain's strict checks, EX recipes and ledger protections. User acceptance still needs to cover HavenFall bag EX upgrades/restoration, ESHF native-conversion rejection for EX-ledger items, and both lunchbox recipes. This is a candidate correction for the current compatibility chain; in-game behavior remains unverified.

## Art, provenance and acceptance

Left/right skinned models and XML, ground model and texture are independently derived from the installed vanilla lunchbox with separate paths/GUIDs, retaining their respective bones, weights and holding poses. Original assets are preserved. The mesh provenance is Project Zomboid vanilla-derived, not an entirely original mesh. Asset evidence is retained under `art/model`.

The cover references the user's original character sheet and approved freshness-fridge artwork. Small mod and transparent item icons are generated independently, never as resized covers. Masters, exact built-in imagegen prompts and exports are retained under `art`.

Offline checks cover the implemented logic, native parsers, Lua compilation, bilingual resources, models and compatibility boundaries. Actual inventory UI, hand switching, movement/other-hand coexistence, ground pickup, vehicles/furniture, save/reload and Viewpoint first/third-person visuals are tested by the user. Parser and model checks do not establish gameplay acceptance.

## perf.8 optional native-backend compatibility / 可选原生接管兼容

rc.8-perf.8: Adds exact Cooling Upgrades1.0.0-rc.2-perf.8 support while retaining perf.1–7 and every captured-identity/write-scope check. Covers its optional Java backend prototype; Lunchbox itself does not require Java, and items/attachment models remain. Source/offline only, not deployed, accepted in-game or published.
