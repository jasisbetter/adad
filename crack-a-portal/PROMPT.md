# Crack a Portal: write all the game's code

You are writing the code for **Crack a Portal**, Jas's Roblox game, starting from a working grey test. The job is every coding part of the brief's BUILD ORDER. Models, keyframe animations, choosing sound ids, thumbnails and publishing are done separately in Studio, so your code must leave clean hooks for them.

This folder contains:
- `BRIEF.md`: Jas's full design. **It is the spec. Read every line.** Where this prompt and the brief disagree, the brief wins, except for the hand-back rules at the end of this prompt.
- `NOTES.md`: what the grey test is, how the code is built, decisions taken so far, tuning results and gotchas learned. Read it all before writing anything.
- `src/`: the grey test's code (Rojo layout, mapped by `default.project.json`; the mapping table is in NOTES.md). **Build on it. Do not start over.**

## 0. Before you write code

1. **Skills: use every Roblox skill you have.** Check your skill list for new ones first, and read each skill before the part of the game it covers. At least: `roblox-game-builder`, `roblox-game-playbook`, `roblox-playtest-review`, `roblox-game-ui`, `roblox-animation`, `roblox-ai-models`, `blender-ai`, `roblox-ai-sound-effects`, `roblox-game-music`, `roblox-ads`, `roblox-game-ideas` (if a design question comes up), the roblox-dev set (`roblox-architecture`, `new-system`, `roblox-datastores`, `roblox-security`, `roblox-performance`, `roblox-testing`, `roblox-ui`, `luau-strict-typing`), the `roblox-reviewer` agent to audit the code at the end, and the Roblox Studio connector's own skills if Studio is connected. Where `roblox-game-ui` and `roblox-dev:roblox-ui` differ, follow `roblox-game-ui`. If a skill named here isn't available to you, tell Jas which ones are missing in your first message and carry on.
2. Read `BRIEF.md`, `NOTES.md` and every file in `src/`.
3. **Ask Jas once, up front**, in a single message: every permission you will need (for example installing tools such as Rojo, luau-analyze, selene or StyLua, or using Roblox Studio if it's connected) and every big decision you can see (see "Big decisions" below). After that, don't stop to ask about small things: pick them yourself and log them in `DECISIONS.md`. Jas wants to be asked only about big decisions.
4. Write `PLAN.md`: every new or changed module, its data shapes, the remotes (name, direction, arguments, rate limit), the save schema (with version), and the order you'll build in. Then build.

## 1. Rules that never bend

- **Server decides everything important**: hits and damage (range, arc, cooldowns, combo timing), drops, key kind and rarity, the pot, the random half, coins, upgrades, merges, sells, gates, rewards and purchases. Validate every remote's arguments (types, ranges, ownership, state) and rate-limit every remote with `RateLimit`. Never trust a number from the client.
- **Everything is data.** Monsters, bosses, attacks, gear types, key kinds, rarities, areas, odds, prices, quests, index rewards and Rift rules live in `Shared/Config.luau`. Pure maths lives in `Shared/Logic.luau` (no instances, so it can be tested). Adding a fifth area or a new monster must not need new code.
- **Everything is made by code.** Map, plots, gates, lighting, UI, templates, remotes, leaderboard boards. Studio must never need hand-made instances: Jas's Claude installs the files and runs `Build.run()`, nothing else.
- **Keep the architecture** in NOTES.md: one server Script with `Systems`, one client LocalScript with `Controllers`, shared modules, two-phase `init`/`start` in a fixed `ORDER` with `pcall`, remotes listed in `Net` and created by the server, Studio-only `DebugTools`.
- `--!strict` and typed everywhere. Modern APIs only: `task.*`, constraints (no BodyMovers), `Players:GetPlayers()`, `:GetAttribute()`. No deprecated calls.
- **Performance (phones first)**: no per-frame allocations in hot loops, pooled effects and damage numbers, every connection cleaned up when a player leaves or a character respawns, AI ticks at 10 Hz (not every frame), batched remotes, StreamingEnabled with Atomic models. Watch the monster count: up to 8 players × 15 alive + map monsters + the Rift. Measure whether Humanoid monsters are affordable. If they aren't, move to AnimationController rigs moved by the server (AlignPosition/AlignOrientation or CFrame) and keep the same `Monsters` API. Treat this as a big decision and ask.
- **Sound**: everything plays through `Shared/Sfx.luau` (client only). **Keep the Studio mute** (`StudioMuteUntil`, see NOTES.md). Jas must never hear a test. New sounds get rows with `id = 0` (silent). **Do not pick or invent sound or music ids**: Jas listens to every sound, and they are picked and measured later in Studio.
- **Never touch any other game or place. Never save to Roblox and never publish.** Jas does that after he says yes to pictures.
- Only original names and art. Don't copy another game's look.
- The game must be fun for **one player alone on an empty server**.
- No `TODO` stubs, no `...` placeholders, no half-written functions. Every file you hand back is complete and compiles.

## 2. What to build, in BUILD ORDER (the coding parts)

Keep the game runnable after every step. After each step, add it to `CHANGES.md` and run the tests.

### Step 1: core systems as data, plus saving
- **Keys**: 4 kinds (Ash, Ember, Frost, Void) × 3 rarities (Common, Rare, Legendary), with the brief's effects (Rare: 2× HP and damage, 2× coins, better gear odds, every 5th wave a 30% boss chance; Legendary: 4× HP and damage, 5× coins, best odds, a real Mythic chance, every 5th wave a boss). Map drops: 8% inner, 12% outer, with the brief's rarity tables (and the Luckier Keys tables). Key shop: Common and Rare of each unlocked kind, Ash Common 150 and Ash Rare 1,500, ×6 per area; Legendary is never sold. Free daily key: one Common of the best unlocked kind every 24 h. Rare key: pop-up, chime, blue glow. Legendary key: bigger pop-up, golden rays and a server message ("<name> found a Legendary Void Key!"). A key can only be used on your own plot.
- **Waves** (already working; keep them): 4 + wave monsters, at most 15 alive (stronger past that), ×1.15 HP and ×1.10 damage per wave, the kind's 3 types mixed with tougher ones later, a 3 s countdown banner, groups over 2–4 s, a 30% heal between waves, a 60 s idle auto-close. Leaving during a wave counts as a fall; leaving between waves keeps the whole pot.
- **Bosses**: one per kind with the brief's attacks; a boss health bar with its name at the top of the screen.
- **Chests**: normal (1 item, the next key rarity's odds), big every 5th wave (3 items, the best at least Epic), boss chest (3 items, the best at least Legendary; 15% Mythic from a Legendary-key boss chest), odds improving a little every 5 waves.
- **Gear**: weapon types Sword, Axe and Twin Blades (each with its own 3-hit combo timing and feel), and Armor (max health), in Ash, Ember, Frost and Void versions. Rarities Common to Mythic, always shown with the word. Weapon powers from Rare up (Ash stagger, Ember burn over time, Frost slow, Void double strike), stronger by rarity. Crits 10% ×2. Item levels: max by rarity 10/20/30/40/50, +6% main stat per level, cost = rarity base (20/60/200/700/2,500) × 1.2^level × area multiplier. Base stats chosen so that the next rarity at level 1 ≈ the one below at half its max level (the grey test already computes this; keep it). Each area is ~3× stronger and gives ~6× the coins. Merge: 3 identical items (same kind, type and rarity) → 1 of the next rarity at level 1 (Mythic can't merge). Sell: 10/50/250/1,250/6,250 × area multiplier, with "Are you sure?" only for Legendary and Mythic. Inventory: 100 items, with a warning before opening a portal when it's nearly full. Gear drops: 3% per wave monster, with the brief's odds per key rarity. Gear is visible on the character (hook: see section 3).
- **Portal levels** 1–20: 300 coins for level 2, then ×1.6 per level. +5% coins and gear-drop chance per level. Levels 5/10/15 unlock Ember, Frost and Void. The portal looks bigger every 5 levels (bigger arch, more runes, more glow), built in `Build`/`Plots` as tiers, so other players can see progress.
- **Saving** (`roblox-datastores`): session locking, retries with backoff, autosave, BindToClose, schema version and migrations. Save coins, gear with levels, keys, portal level, index, daily quests, daily key time, leaderboard stats, settings (music and SFX volume, camera shake, reduced motion), the tutorial flag and processed purchase receipts. **The pot is never saved.** In Studio without API access, run on in memory with one clear warning.
- **Pacing targets** (tune numbers to hit them, and show the maths in `PACING.md`, ideally from a small simulation built on `Logic`): first portal cracked inside 60 s, first gear upgrade inside 3 min, Ember at 20–30 min, Frost at ~2 h, Void at 6–8 h, portal level 20 at ~15 h or more, a normal opening lasting 3–8 min. List every number you changed and why.
- Turn the grey-test shortcut off (`Config.GreyTest`: map keys always Common).

### Step 2: the map (code side)
Extend `ServerStorage/Build.luau`: 8 plots in a ring around the stone courtyard (the Rift spot), then the 4 areas as rings going outward, each with an inner (weaker, 8% keys) and outer (stronger, 12% keys) band, and areas defined as data so more can be added. **Gates** labelled "Portal level X" that only let qualifying players through. Enforce this on the server (for example, a server check that returns anyone inside an area they haven't unlocked to its gate), not only with client collision. Gate opening effects from the brief (rubble crumbles, ice shatters, void fades). Per-area lighting on the client by zone: Future lighting, Atmosphere colour, Bloom, ColorCorrection, and particles (embers, heat haze, snow, void specks), blended as the player crosses. Dark stone, torches, banners, glowing runes on the portal arches. Use grey parts and materials, with hooks to swap in models by name.

### Step 5: combat feel and monster behaviour
Everything in the brief's FIGHTING, MONSTERS and COMBAT FEEL sections that is code: every monster's behaviour as data-driven attack modules (melee, charge line, slam circle, cone, many small circles, projectiles, beams with a thin line first, fire pools, teleport-behind with a flash, a frontal shield that blocks hits from the front, swoop from the air, pack circling, summons, a full-arena slam with safe spots shown), each with a red warning zone that fills up (circle, line, cone). Wind-ups of at least 0.4–0.5 s. Map monsters wander, notice the player, attack and give up the chase when the player runs far away (already working). Hit-stop 0.05–0.1 s (up to 0.15 s for heavy hits), a white flash, knockback (more on the Axe), sparks or slashes, damage numbers (gold and bigger for crits; orange for burn, blue for slow, purple for double hits), camera shake on big hits, boss slams and the portal crack (with a Settings switch), deaths that burst into the kind's colour, and weapon trails coloured by kind and brighter by rarity.

### Step 6: animated UI (all of it)
Follow `roblox-game-ui` and the brief's ANIMATED UI section exactly. **Write the style tokens down first** (in `Ui.luau` and `DECISIONS.md`). HUD phone first: coins top left; the pot top middle during an opening (wave number, coins, gear icons with the best first, "Keep half if you fall", and the boss bar under it); left side Inventory, Portal, Keys, Quests and Index (icon + word); right side STORE and SETTINGS; ATTACK and DODGE bottom right with the health bar above them; nothing important under the thumbs or the top bar. Windows grow out of the button that opened them, the content arrives as a quick wave, the main button lands last, closing is faster than opening, and only one window is open at a time. Screens: Inventory (a grid with filters, equip, upgrade, merge and sell), Gear card, Portal, Keys plus the key shop (show the exact Luckier Keys odds with and without the pass), Store, Daily Quests, Index (a book), Leaderboards, and Settings with **a music volume slider and a sound effects volume slider** (sliders, not switches; saved), camera shake and reduced motion. Reveals scale with rarity (under 2 s for Common, 5–6 s with rays, confetti and a shine for Legendary and Mythic; a tap skips). Legendary and Mythic get an animated border shine everywhere they appear. Can't afford: the button shakes and the price flashes red (no popup). Never animate a Robux button. Support Reduced Motion. Keep the grey test's pot, between panel, close and fall presentations, and restyle them to the tokens.

### Step 7: sound and music (code only)
Sfx rows (id 0) for every new moment: swing and hit per weapon type, growl, attack and death per monster, level up, merge, sell, rare key, legendary key, the Rift countdown, and so on. A music system per `roblox-game-music`: a calm track per area chosen by zone, combat music during openings that intensifies every 5 waves, boss music and Rift music, with crossfades, its own SoundGroup, the music slider and the Studio mute. All ids 0.

### Step 8: long-term
Daily key (24 h). Daily quests (3 a day from a data list such as reach wave 10, close a 5,000-coin pot, beat 100 monsters, open 3 portals, beat a boss, merge an item, help in a Rift; rewards: the first two give coins and a Common key, the third gives a Rare key; reset every 24 h). Index (a page per area: the 3 monsters and the boss beaten, every weapon and armour found by rarity; rewards: an area's monster section gives a Rare key, a rarity row gives coins, the whole index gives a title shown on the player). Leaderboards: Highest Wave and Biggest Pot, in the world near the courtyard and in the Leaderboards screen, with OrderedDataStores. Pots saved by Recover Loot don't count. **Server Rift**: about every 15 min in the courtyard, a 30 s countdown on every screen plus a server message and Rift music, 3 waves of mixed monsters, then a Rift Boss (rotating through the 4 bosses, bigger and glowing), HP × (1 + 0.6 per extra player), rewards per the brief (everyone who did damage gets 1 Rare key of an unlocked kind plus coins; the top 3 get a second Rare key and a 10% Legendary chance). Players in an opening are told and can join after closing.

### Step 9: money
Gamepass 2× Coins. Gamepass Luckier Keys (the brief's odds; show the exact odds with and without it; hide it where `PolicyService` says paid random items are restricted). **Recover Loot**: 3 developer products for small, medium and big lost pots, offered right after the fall reveal. It shows exactly which coins and items were lost and gives exactly those back. One tap skips it. It never pulses, flashes or counts down. Read prices from `MarketplaceService` product info and never hard-code them. `ProcessReceipt` must be idempotent: record receipt ids in the saved profile and return `PurchaseGranted` only after the grant is saved, so a purchase is never lost or given twice. Pass and product ids go in Config as 0 until Jas creates them (list them in `TODO_STUDIO.md`).

### Step 10: tutorial
The brief's 8-step spotlight tutorial: the screen dimmed, one bright circle on the thing to press, a big arrow, a short line of text, taps elsewhere do nothing until the step is done, and a Skip button. The spotlight must be centred on its target on every device (compare `AbsolutePosition + AbsoluteSize / 2` of both, and mind gotcha 1 in NOTES.md). The tutorial's wave 1 is 3 weak Ash Imps; after wave 2 the arrow points at CLOSE PORTAL; give enough coins for exactly one upgrade; finish with a ground arrow to the Ash monsters. Save the flag.

### Step 11: check
Run the `roblox-reviewer` agent on the whole codebase (remotes, DataStores, purchases, memory and leaks, performance, strict typing) and fix everything it finds. Run the tests. If Studio is connected to you, run `roblox-playtest-review` (muted). If it isn't, list in `TODO_STUDIO.md` exactly what must be checked in Studio.

## 3. Hooks for the work done outside code

Write the contract in `ASSETS.md` so the models and animations can be made to fit:
- **Models**: Config names each model, for example `ServerStorage.Assets.Monsters.AshImp`, `ReplicatedStorage.Assets.Gear.Ash.Sword`, `…Armor`, the portal tiers, chests and keys. When a model is missing, fall back to the grey template, so the game always runs. Say which parts and attachments each one must have (a root part, the weapon grip attachment, armour attach points, the eye/glow parts used by effects) and its size.
- **Animations**: per monster (idle, move, each attack's wind-up and strike, hit, death with a bounce, emerge (crawl/leap/burst), and for bosses the roar and each special) and per weapon type (3 combo hits with a `Hit` marker on the contact frame), plus the player's dodge roll, hit reaction, fall, victory pose and key use. Ids go in Config and are 0 until made. With id 0, keep the current code-driven placeholder (and its contact timing); with a real id, play it through the Animator so it replicates, and drive hit-stop, sound and effects from the `Hit` marker.
- **Sounds and music**: rows with id 0 (see Step 7).
- **Products and passes**: ids 0 in Config (see Step 9).

## 4. Big decisions (ask Jas these up front, with your recommendation)

Humanoid or AnimationController monsters (performance); whether the grey-test decisions listed in NOTES.md stay (for example auto-equip on close, keeping jump, endless waves); Recover Loot size thresholds; and anything else that changes how the game feels or costs Jas money. Everything else: decide it and log it in `DECISIONS.md`.

## 5. Testing

- Unit tests for `Logic` and the other pure modules (odds sum to 100%, random half rounds up, merge and sell values, level costs, pacing simulation, save migrations, receipt idempotency), as `src/ServerStorage/Tests/*.spec.luau` with a tiny runner that Studio can call (`require(game.ServerStorage.Tests.Run)()`).
- If you can install them: `luau-analyze` in strict mode with Roblox type definitions, plus `selene`. Fix every error.
- Extend `DebugTools` (Studio only) for every new system: give coins, set portal level, unlock areas, give any gear, force a boss wave, start the Rift now, reset data, skip or replay the tutorial.

## 6. How to work

Use helper agents at **medium effort**. Keep a task list and tick each task off the moment it's done. This is a big job: work in the BUILD ORDER steps, and keep `CHANGES.md` and `PLAN.md` current so a fresh session can pick up where you stopped if you run out of context.

## 7. Hand back (important: Jas gives your output to his Claude, which installs it into Studio)

Hand back one zip, `crack-a-portal-src.zip`, containing:
- `src/`: the **whole** project in the same Rojo layout (every file complete, not only the changed ones) and `default.project.json`.
- `CHANGES.md`: every file added, changed or deleted, one line each, grouped by BUILD ORDER step.
- `PLAN.md`, `DECISIONS.md` (every small pick), `PACING.md`, `ASSETS.md`, an updated `NOTES.md`.
- `TODO_STUDIO.md`: everything that needs Studio or the Roblox website: running `Build.run()`, enabling Studio API access for DataStores, creating the gamepasses and products and where their ids go, models, animations, sound and music ids, and what to check in game.

Finish with a short message to Jas in plain words: what's done, what's left for Studio, and any questions.
