# Crack a Portal: where the code stands (stopped on 13 Oct 2026)

Jas asked to stop. This is an honest snapshot of the work so far. **It is not playable yet: there is no client code and the portal/wave system isn't written.** Don't install it over the working grey test in Studio yet.

## Read this first
- Only 5 of the grey test's files reached this session (`Anim`, `Sfx`, `Logic`, `Net`, `Build`). The other 19 files described in NOTES.md never arrived, so they are being **rebuilt** from those descriptions, using the same names and APIs.
- `PLAN.md` is the contract every file is written against: modules, remotes, save schema and attributes.
- `notes/*.md` are the helpers' notes: what each one built, its API, its decisions and the Studio checks it needs.

## Done (compiles, 82 of 82 offline tests pass, selene clean)
| Part | Files |
| --- | --- |
| All game data | `Shared/Config.luau`: 4 key kinds, 3 key rarities, 5 gear rarities, Sword/Axe/Twin Blades/Armor with their own combos, weapon powers, 16 monsters (12 + 4 bosses), 30 attacks, 4 ring areas with their looks, odds tables (with Luckier Keys), portal levels, quests, index, Rift, passes and products (ids 0), music and animation rows (ids 0) |
| Pure maths | `Shared/Logic.luau` (all grey-test functions kept, plus levels, upgrade costs, merge, sell, portal costs, key prices, map key rolls, boss waves, chests, Recover Loot tiers, quests, index rewards), `Shared/CombatMath.luau`, `Shared/Geometry.luau` |
| Shared libraries | `Types`, `Net` (every remote, rate limits, an unreliable effects remote), `Signal`, `Assets` (find a model by name), `Templates` (grey fallback models: every monster, gear, 5 portal tiers, chests, keys), `AnimHooks` (animation id 0 = code placeholder) |
| Saving | `Server/Lib/SaveSchema.luau` (version 1 and migrations), `Systems/Save.luau` (session lock, retries, Studio memory mode with one warning, `StudioTempData` switch), `Systems/PlayerData.luau` (profile, autosave, BindToClose, `loaded` guard, settings, snapshots), `Lib/Receipts.luau` (purchases never given twice) |
| Map | `ServerStorage/Build.luau`: 8 plots around the courtyard, 4 area rings with inner and outer bands, gates labelled "Portal level X", props, torches, world leaderboard boards, lighting. `Systems/Plots.luau` (portal grows in 5 tiers), `Systems/Gates.luau` (the server returns players to their allowed area) |
| Monsters | `Systems/Monsters.luau` and `Lib/Attacks.luau`: AnimationController rigs moved by the server, 10 Hz AI, every attack shape in the brief with red warning zones (melee, charge, slam, cone, rain, projectiles, beam, fire pools, teleport, swoop, summon, arena slam with safe spots), boss roar and boss bar, statuses (`Lib/Status.luau`) |
| Combat (server) | `Systems/Combat.luau`: 3-hit combos per weapon type, auto-face, crits, weapon powers, the Void Knight's shield, dodge, player damage, regen, a teleport check |
| Other | `Systems/Notify.luau` (toasts and server messages), `Systems/Appearance.luau` (gear visible on the character, trails, title), `Systems/RateLimit.luau`, `init.server.luau` (boot order, skips missing systems) |
| Tools | `tools/check.luau` (compile check), `tools/test.luau` (offline tests), `src/ServerStorage/Tests/` (11 spec files; `require(game.ServerStorage.Tests.Run)()` in Studio) |

## Not written yet
- **Server:** `Openings` (portal opening, waves, pot, chests, close/fall, Recover Loot offer), `MapMonsters`, `Rift`, `Economy` (equip, upgrade, merge, sell, portal upgrade, key shop), `Purchases`, `Daily` (daily key, quests), `Index`, `Leaderboards`, `Tutorial`, `DebugTools`.
- **Pacing:** `Sim/Pacing.luau` and `PACING.md`. The numbers in Config are starting values only. The design digest worked out that at grey-test income Ember would take about 55 minutes, not 20–30, so the numbers need tuning.
- **Client: everything.** `init.client`, Ui tokens and builders, Store, Windows and every screen, HUD, OpeningUi, Reveal, Effects, MonsterFx, client Combat, Zones (lighting), Music, Sfx rows, Tutorial, RiftUi.
- **Final steps:** the full `roblox-reviewer` audit, and the hand-back docs (`CHANGES.md`, `DECISIONS.md`, `ASSETS.md`, `TODO_STUDIO.md`).

## Decisions taken (Jas said "go with whatever")
- Monsters use AnimationController rigs moved by the server, not Humanoids, so 8 openings plus the map and the Rift run on phones. Still to measure in Studio.
- Endless waves, keep jump, spawn near the portal, Studio TEST buttons Studio-only.
- Better gear does **not** auto-equip, except into an empty slot, because the tutorial teaches EQUIP.
- Recover Loot sizes, by lost value (coins plus the sell value of lost items) divided by the area's coin multiplier: small under 1,000, medium under 10,000, big 10,000 and up.
- 2× Coins doubles earned coins, not coins from selling.
- Map monsters drop keys only, no coins.
- One to check with Jas: because coins can be doubled with Robux, coin-bought keys might count as paid random items. Plan: show the gear odds in the Keys screen too.

## How to carry on
Start a new session with this folder. Give it `PLAN.md`, `notes/HELPERS.md` and this file. Build the missing server systems, then the client, then run the review and write the docs. All of it is listed in `PLAN.md` section 12.
