# Crack a Portal: grey test notes (12 Oct 2026)

Read this together with `BRIEF.md` (Jas's full design). This file describes the code in `src/` as it is now: a working grey test in plain grey parts that plays the whole loop with a clean console.

## Status

- Works end to end: map monster → key → USE KEY → key picker → crack sequence → wave banner → monsters leap out of the portal in groups → coins and gear fly into the pot → wave cleared → chest bursts out → OPEN CHEST → reveal card → between panel (CLOSE PORTAL / ONE MORE WAVE, 30% heal) → … → close (pot flies to the counter and the bag) or fall (exactly half the coins, random half of the gear, card-flip reveal).
- Checked in Studio: chest reveal, fall reveal, close, the 60 s idle auto-close, red circle (slam) and line (charge) warnings, dodge (keyboard Q reaches the server), map monster key drops and respawns, the Studio mute.
- Not done yet: the phone/tablet/PC layout pass. **Jas has not played the grey test yet**, so the brief's question ("does one more wave feel exciting?") is still open.
- Sounds: 23 placeholder sounds from Roblox's licensed library (ProSoundEffects), measured as soft. Nobody has listened to them yet. No music.

## Studio ↔ files (Rojo layout, `default.project.json`)

| File | Studio instance |
| --- | --- |
| `src/ServerScriptService/Server/init.server.luau` | Script `ServerScriptService.Server` |
| `src/ServerScriptService/Server/Systems/X.luau` | ModuleScript `ServerScriptService.Server.Systems.X` |
| `src/StarterPlayerScripts/Client/init.client.luau` | LocalScript `StarterPlayer.StarterPlayerScripts.Client` |
| `src/StarterPlayerScripts/Client/Controllers/X.luau` | ModuleScript `…Client.Controllers.X` |
| `src/ReplicatedStorage/Shared/X.luau` | ModuleScript `ReplicatedStorage.Shared.X` |
| `src/ServerStorage/Build.luau` | ModuleScript `ServerStorage.Build` (run once in Edit: `require(game.ServerStorage.Build:Clone()).run()`) |

Everything else is made by code: the map and plots (`Build.run()`), monster templates (`Monsters`, into `ServerStorage.MonsterTemplates` at runtime), remotes (`Net.create()` on the server, into `ReplicatedStorage.Remotes`), and all UI (built from code at runtime; StarterGui is empty). There are no hand-made instances to preserve.

## Architecture and conventions (keep these)

- One server Script and one client LocalScript. Each requires its modules in a fixed `ORDER`, calls `init()` on all of them, then `start()` on all of them, each wrapped in `pcall` so one broken system doesn't stop the rest.
- `--!strict` in every file, with exported types.
- **Data-driven**: every number, monster, key kind, rarity, odds table, gear type and area lives in `Shared/Config.luau`. Pure functions (odds, stats, wave specs, the random half) live in `Shared/Logic.luau` and touch no instances, so they can be unit tested.
- **Server-authoritative**: the server decides hits (combo timing, range, arc, crits), drops, the pot, the random half, coins and equips. Every remote goes through `RateLimit.allow(player, key, perSecond, burst)` and validates its arguments.
- Remotes are listed in `Shared/Net.luau` (`ToServer`, `ToClient`) and created by the server only. A `Debug` remote exists in Studio only.
- **UI** follows Jas's `roblox-game-ui` skill: `Ui.screen(name, order)` makes a ScreenGui with one `Root` frame and one `UIScale` (design pixels; scale = clamp(sqrt(min(w/667, h/330)), 0.85, 2.2)). Every motion goes through `Shared/Anim.luau` (the skill's module). Buttons: `Ui.button` (the face sinks on press, GuiState-driven, haptic, soft click).
- **Sound** goes through `Shared/Sfx.luau` (the `roblox-ai-sound-effects` kit). It is client-only. Rows have `id`/`ids`, `volume`, `speed`, `vary`, `region`, `voices`, `gap`, `range`. An id of 0 is silent and skipped. **Studio mute**: if `workspace:GetAttribute("StudioMuteUntil")` is later than `os.time()` when the client starts, all sound (and Roblox's own character sounds) is muted. Set it before every playtest. Jas must never hear a test.
- Collision groups: `Players`, `Monsters`, `Fx` (players and monsters don't collide). StreamingEnabled, with Atomic models.

## Systems (server, `Server/Systems`)

- `RateLimit`: a token bucket per player and key.
- `PlayerData`: the session profile (`coins`, `keys` as `"Ash|Common" → count`, `items`, `equipped`, `hp`, `maxHp`, `damage`, `lastHurt`, `nextId`). **Not saved yet** (the grey test has no saving). Functions: `recalc`, `snapshot` (a deferred `Profile` remote), `addCoins`, `addKey`, `takeKey`, `addItem` (ids `"iN"`), `equip`, `equipIfBetter`, `setHp`, `heal`, `fullHeal` (player attributes `HP`, `MaxHP`), `splitKey`, `keyId`. The `Equip` remote is blocked during an opening.
- `Plots`: reads `Workspace.Plots.PlotN` (Portal.Surface, PlayerSpawn, ChestSpot, MonsterSpawn, Platform, Walls), assigns plots, writes the name on the banner, and provides `isInside`, `clampInside`, `setWall` (ForceField walls during an opening) and `sendHome`.
- `Monsters`: Humanoid monsters, network-owned by the server, with AI ticked at 10 Hz. The states are emerging, idle, chase, windup, dash, recover and returning. Attack types are `melee`, `charge` (red line) and `slam` (red circle), and warnings go to the client through the `Warn` remote. `spawn(defId, cf, opts)`, `damage(mon, amount, by, dir, {heavy, knock})` (interrupts and knocks back), `kill`, `despawn`, `hittableBy`, `ownedBy`. Attributes: MonsterId, Def, HP, MaxHP, Owner, Windup, Dead, Vanish, Emerge. Tag `"Monster"`.
- `Combat`: `onAttack` (combo step, auto-face, arc, finisher radius on hit 3, crit, sends `Hits` to the client), `onDodge` (`invulnUntil`), `damagePlayer` (Fx `Dodged`/`Hurt`; at 0 HP it calls `Openings`' fall hook, or sends the player home on the map), and regen outside openings.
- `Openings`: the portal state machine: cracking → countdown → wave → chest → between → closing or fallen. `useKey` (rate limit, range check, on own plot), `startWave`, `spawnWave` (groups over 2–4 s, monsters leap out of the portal), `onMonsterDeath` (coins into the pot, 3% gear), `waveCleared` (heal 30%, roll and build the chest), `openChest`, `close`, `fall` (`Logic.keptCoins` and `Logic.randomHalf`), `onLeave` (leaving during a wave counts as a fall; between waves the player keeps everything), the 60 s idle auto-close, and `sendState` via the `Opening` remote.
- `MapMonsters`: one monster per `Workspace.Map.MonsterSpawns` point (attributes Area, Band, Monster). Outer band: HP ×1.4, damage ×1.25. Key drop on death (`Fx KeyGet`). Respawn after 12 s.
- `DebugTools`: **Studio only** (`RunService:IsStudio()`). BindableFunction `ServerStorage.DebugCall` with commands `key, heal, sethp, state (JSON), home, usekey, killwave, openchest, choice, fall, potgear, mapkill, monsters`, plus the `Debug` remote for the on-screen TEST buttons.

## Client (`Client/Controllers`)

`Ui` (theme: Oswald Bold display, BuilderSans body; helpers; rarity colours), `Store` (profile and opening state), `Effects` (shake by trauma plus `rumble` for continuous shakes, a pool of 36 damage-number billboards, sparks, dust, flash, slash, monster health bars, red warning zones that fill up, flying coins and icons, toasts, the hurt vignette), `Hud` (coins, keys, BAG, ATTACK and DODGE with a cooldown shade, health bar, the context button USE KEY / NO KEYS (grey) / OPEN CHEST on E, the Studio TEST panel, ATTACK placed beside Roblox's jump button on touch), `Windows` (Keys window with USE, Bag window with EQUIP, one at a time, dim layer), `OpeningUi` (pot panel, between panel, a queue of presentations: wave banner, chest reveal, close, fall card flips, crack sequence, chest arc and hop), and `Combat` (a code-driven placeholder 3-hit swing written into joint `Transform` in PreSimulation and restored in PreAnimation, a welded sword plus trail, the combo, auto-face, hit-stop, effects on the contact frame, the dodge roll with LinearVelocity, and input: hold ATTACK, click, Q/ButtonB dodge, ButtonX/R2 attack).

## Grey-test decisions Jas has not approved yet

Endless waves (the brief's grey test said 3; the full brief says endless). Better gear auto-equips on close. A simple BAG equip window. Map keys are always Common (`Config.GreyTest = true`). The spawn point was moved near the portal. Jump is kept, with ATTACK placed beside it on touch. Wave 1 = 5 imps (4 + wave; the tutorial wants 3). The placeholder swing is only visible to its owner. Studio TEST buttons (+KEY, +RARE, +LEG, HEAL).

## Tuning results (bot holding ATTACK, no gear, no dodging)

Waves 1–3 took no damage. Lowest HP: 79 on wave 4, 62 on wave 5, 66 on wave 6; the bot fell on wave 7 with a pot of 492 (about 2.5–3 min in total). A wave takes 10–17 s. About 3 waves ≈ 150 coins ≈ one Ash Common key. The Ash Imp was made gentler for wave 1 (damage 3, windup 0.45 s, cooldown 1.8 s). Rarity stat multipliers are computed so that the next rarity at level 1 equals the previous rarity at half its max level (+6% per level).

## Gotchas learned (read before touching the UI or combat)

1. **AbsoluteSize inside a UIScale root.** In Studio 0.742, `Root.AbsoluteSize` read 1120×479 on a 1626×695 safe area at UI scale 1.451: design pixels, not screen pixels. Descendants' AbsolutePosition looked the same way. `Ui.rootSize()` divides by the scale again (probably wrong), and `Hud.placeForTouch` mixes TouchGui screen pixels with root values. **Verify** with `PlayerGui:GetGuiObjectsAtPosition(x, y)` at real screen coordinates before relying on either. The safe source of the design size is `screenGui.AbsoluteSize / Ui.scale()` (a ScreenGui has no UIScale).
2. A disabled ScreenGui reports AbsoluteSize 0. Lay rows out with `UDim2.new(0.5, offset, …)` around the centre, not with absolute sizes.
3. Continuous shakes (the crack rumble) must set trauma (`Effects.rumble`), not add it every frame, or they pile up to the maximum.
4. Coin counters after close/fall: capture the start value when the Fx arrives (`Hud.pendingCoins`), because the Profile update can land first.
5. The presentation layer needs a token so that a clear from one reveal doesn't wipe the next one.
6. A new Sound and a new SoundGroup both start at volume 0.5. A world sound's default range is the whole map. `PitchShiftSoundEffect` starts at 1.25. The Sfx kit handles all of this.
7. `AssetService:SearchAudioAsync` returns whole-second durations. Measure ids silently with an AudioPlayer → AudioAnalyzer (no output device).
8. The code-driven swing (joint Transform) does not replicate. Real animations through the Animator will.

## Known gaps against the brief (the grey test left these out on purpose)

No saving, shop, upgrades, levels, merge, sell, portal levels, other areas or gates, bosses, Rift, daily key, quests, index, leaderboards, gamepasses, Recover Loot, tutorial, settings or music. Only the Sword and Armor gear types exist (no Axe or Twin Blades, no weapon powers), no inventory cap, no Rare/Legendary key effects or server messages, and only Ash kind monsters (Imp, Hound, Brute). Monsters and the sword are grey parts. The swing is code-driven.
