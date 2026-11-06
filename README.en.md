# SuQing's Freshness Lunchbox / 蘇清的返鲜餐盒

Workshop item: [uploaded and verified private item](https://steamcommunity.com/sharedfiles/filedetails/?id=3834693433). Source repository: [suching8848/suqing-freshness-lunchbox](https://github.com/suching8848/suqing-freshness-lunchbox). Private upload and native content readback completed on2026-11-06. The item is not public; gameplay acceptance is unchanged.

**0.1.0-rc.5**, a Project Zomboid B42.21 single-player candidate. This project contains one Mod ID: `SuQingFreshnessLunchbox`. Item: `SuQingFreshnessLunchbox.FreshnessLunchbox`.

A separate native food container based on the vanilla lunchbox, with independent left/right one-hand appearances. Directly stored eligible Food keeps its original identity and gradually loses age according to its own native fresh-life interval. All foods are processed together. Supported positions include carried inventories, hands, ground, furniture and vehicles. Previously recorded food may earn unloaded game-time restoration only when item/box identity, switch state and actually enabled session/policy coverage remain provable. Real time outside the game, switched-off intervals and mod-disabled sessions earn no restoration.

This **rc.5 ground-outline candidate** follows the user's report that the remaining visible issue is outline alignment. That report does not establish exhaustive compatibility acceptance. A separate transparent 32×32 world sprite is rendered offline from the actual ground FBX, current material and native projection parameters, then selected through the native `UseWorldItem` fallback. Inventory art, models, freshness behavior, recipes, ordinary upgrades and sandbox rules are retained.

See the [outline fix record](docs/personal-outline-20261106.md) for this task's backup, verification and personal deployment. The [rc.4 hotfix record](docs/personal-hotfix-20261106.md) remains historical. No game was started or operated, and no Git commit or Workshop publication was made.

## rc.5 outline correction and limits

- Retain the independent inventory icon. Add `media/inventory/world/WItem_SuQingFreshnessLunchbox.png`, enable `UseWorldItem=true`, and retain unit `ScaleWorldIcon=1`.
- Render the actual mesh using its FBX node transform, original UVs and current material. The world sprite is not a reduced inventory icon or cover. Its ground anchor is (16,24) on a 32px canvas; the 3D ground ModelScript scale remains 0.4.
- A valid native model atlas remains preferred; the new world image is used only by the sprite fallback. Java, global rendering and PZO configuration are untouched.
- The fallback is a fixed-yaw=0 projection. It improves the former front-facing suitcase silhouette but does not promise exact arbitrary rotation, extended-placement or camera alignment. User gameplay acceptance is required.
- Existing lunchboxes read the current script and world texture after normal reload. No recrafting, item migration or save rollback is needed.

## Defaults and settings

- Capacity **4**, weight **1.0**, weight reduction **50%**, based on the installed vanilla `Base.Lunchbox`.
- Independent sandbox settings: master switch, initial base capacity, restoration hours and rotten-food support.
- Base capacity defaults to 4, range 1–30, and applies only on a new box's first initialization. Later slider changes never overwrite an existing instance or upgrade record.
- Restoration hours default to 10, range 0.25–1000. Every credited game hour subtracts `native fresh-life interval / RestoreHours` from age, down to 0. At 0.25, one complete fresh-life interval is recovered per 15 effective game minutes; deeply rotten food can take longer.
- Rotten food is allowed by default. Only directly stored standard perishable Food is processed. Burnt food, fertilized eggs and unsupported lifetimes are excluded. Portions, poison, contamination and cooking state are preserved.

If the world's vanilla rotten-food removal setting is nonnegative or cannot be read reliably, already rotten food is skipped and the context tooltip explains the restriction. The world setting is never changed. Rotten-food restoration requires a negative removal value; the candidate does not temporarily disguise rotten food as fresh to evade native deletion.

Catch-up retains at most 128 enabled/policy segments. First insertion, changed boxes, missing history, external Lua age edits or unprovable continuity establish a new starting point without past restoration. Intervals outside retained history receive no credit. Other mods directly changing both age and timestamps through Java cannot be identified completely and remain an unverified compatibility boundary.

The vanilla `MaxItemSize=1` is preserved and the container accepts standard Food only. Actual drag/drop and third-party food combinations require user acceptance; added capacity does not remove size restrictions. Continuous power and battery replacement are outside this candidate's mechanics.

## Crafting and optional upgrades

Native crafting offers two recipes with the same output. A screwdriver is retained in both:

1. One empty vanilla lunchbox, one pocket watch, one digital watch, one classic analog wristwatch and two electric wires.
2. Two small metal sheets, one pocket watch, one digital watch, one classic analog wristwatch and two electric wires.

Common vanilla digital/classic left/right and color variants are accepted as separate families; three distinct physical timepieces are required. Native crafting owns payment and cancellation, with no separate refund loop. The lunchbox conversion input must be empty, out of both hands and free of container-upgrade records. The metal-sheet route does not require an existing lunchbox.

Ordinary `SuQingContainerUpgrade_4221` main mod **1.0.3** includes support for this lunchbox. No separate lunchbox compatibility submod is required. The lunchbox has no dependency on ordinary Container Upgrades: crafting, food storage and freshness restoration work independently when that mod is absent or disabled.

With a supporting ordinary-upgrade version enabled, the original capacity targets 12/20/30/40/49, weight-reduction targets 90/93/95/97/99, material/skill requirements, paid ledger, precise restoration and 50% paid-material refunds are retained. Empty and unhand the box before upgrading/restoring. Freshness initializes base capacity once and never writes an upgraded box back to 4. This support does not automatically add the box to EX/Auto.

This outline correction updates only Freshness Lunchbox to 0.1.0-rc.5; the installed ordinary Container Upgrades 1.0.3 stays unchanged. The historical deployment record covers the original 1.0.0 backup and recovery directory, the save-only lunchbox addition and the unchanged new-save default. For other manual installations, exit the game normally and avoid duplicate loadable copies with the same Mod ID. The lunchbox still works independently without ordinary upgrades.

The existing `Codex_SuQingWearableCompat_4221` still handles other compatibility work, including HavenFall EX. Removing the lunchbox-specific companion is not a reason to disable it; retain its existing optional enablement.

The rc.3 correction to when the lunchbox crafting preflight is installed is retained to preserve the existing HavenFall EX crafting chain's strict checks, EX recipes and ledger protections. User acceptance still needs to cover HavenFall bag EX upgrades/restoration, ESHF native-conversion rejection for EX-ledger items, and both lunchbox recipes. This is a candidate correction for the current compatibility chain; in-game behavior remains unverified.

## Art, provenance and acceptance

Left/right skinned models and XML, ground model and texture are independently derived from the installed vanilla lunchbox with separate paths/GUIDs, retaining their respective bones, weights and holding poses. Original assets are preserved. The mesh provenance is Project Zomboid vanilla-derived, not an entirely original mesh. Asset evidence is retained under `art/model`.

The cover references the user's original character sheet and approved freshness-fridge artwork. Small mod and transparent item icons are generated independently, never as resized covers. Masters, exact built-in imagegen prompts and exports are retained under `art`.

Offline checks cover the implemented logic, native parsers, Lua compilation, bilingual resources, models and compatibility boundaries. Actual inventory UI, hand switching, movement/other-hand coexistence, ground pickup, vehicles/furniture, save/reload and Viewpoint first/third-person visuals are tested by the user. Parser and model checks do not establish gameplay acceptance.
