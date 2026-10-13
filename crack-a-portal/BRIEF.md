Build a new Roblox game called "Crack a Portal" in Roblox Studio. Use a new empty Baseplate. Do not touch any of my other games.

HOW TO WORK
- Build the GREY TEST at the bottom first. Playtest it, fix every error, then stop and let me play it. Do not build anything else until I say the grey test is fun.
- After that, build the rest in the BUILD ORDER near the bottom, and show me pictures at each checkpoint.
- Ask me only about big decisions. Pick small details yourself and list what you picked at each checkpoint.
- Before any long piece of work, ask me up front for every permission you will need (computer access, saving in Studio, Blender, Tripo, publishing), so nothing waits on me after I step away.
- Use these skills: roblox-game-builder, roblox-game-playbook, roblox-animation, roblox-ai-models, blender-ai, roblox-game-ui, roblox-dev:roblox-ui, roblox-game-music, roblox-ai-sound-effects, roblox-playtest-review, roblox-dev:roblox-datastores, roblox-dev:roblox-security, roblox-dev:roblox-performance.
- All numbers below are starting numbers. Tune them to hit the pacing targets, and tell me what you changed.
- This game must have GREAT animations, GREAT models and a GREAT animated UI. Those sections are as important as the systems.

THE GAME
Dark fantasy. Every player has a portal on their own plot. You beat monsters around the map to get keys. A key cracks your portal open and waves of monsters pour out to you, each wave harder with better loot. Everything you collect goes into a pot. Between waves you choose: close the portal and keep the whole pot, or risk one more wave. If a wave beats you, the portal slams shut and you keep only half. Players never go into the portal; monsters always come out of it.

THE CORE LOOP
1. Get a key: beat monsters on the map, claim the free daily key, or buy one in the key shop.
2. Use the key at your portal. It cracks open and monsters pour out.
3. Fight the wave. Monsters drop coins and sometimes gear into your pot. Clear the wave and a chest bursts out of the portal with a guaranteed piece of gear.
4. Between waves, choose: CLOSE PORTAL (keep the whole pot) or ONE MORE WAVE (harder, better loot).
5. If a wave beats you: keep exactly half the coins and a random half of the gear.
6. Spend coins on gear levels and portal upgrades. Portal levels unlock new areas with new kinds of keys.
7. Go again with better gear and a rarer key, and push to a higher wave.

PACING TARGETS (tune numbers to hit these)
- First portal cracked inside 60 seconds of joining.
- First gear upgrade inside 3 minutes.
- Ember area unlocked after about 20 to 30 minutes.
- Frost area after about 2 hours.
- Void area after about 6 to 8 hours.
- Portal level 20 (max at launch) after about 15 hours or more.
- A normal portal opening lasts 3 to 8 minutes.

THE FIRST MINUTE (tutorial, spotlight style)
Spotlight style: screen dimmed, a bright circle on the one thing to press, a big arrow pointing at it, a short line of text. Tap anywhere else does nothing until the step is done. A Skip button for players who know the game.
1. Player spawns on their plot next to their portal. They already have one free common Ash key. Spotlight on the portal: "Crack your portal!"
2. Key picker opens, spotlight on the key, then USE. The crack sequence plays.
3. Wave 1 is 3 weak Ash Imps. Spotlight on the attack button: "Tap to attack."
4. The first monster attack shows a red warning zone. Spotlight on dodge: "Dodge out of the red!"
5. Wave cleared, chest bursts out. Spotlight on the chest: "Open it!" The item flies into the pot. Spotlight on the pot: "Everything goes in your pot."
6. The between-waves panel appears. Spotlight on both buttons with: "Close to keep everything. Risk another wave for better loot. If you fall, you lose half." After wave 2, the arrow points at CLOSE PORTAL.
7. The pot flies into the inventory. Spotlight on Inventory, then on EQUIP for the new weapon, then on UPGRADE (give enough coins for one upgrade).
8. Last step: an arrow on the ground leads to the Ash monsters: "Beat monsters for more keys." Tutorial done.

THE MAP
- One map, one server of up to 8 players. 8 plots sit in a ring around a central stone courtyard. The courtyard is where the Server Rift opens.
- Each plot: a stone platform with the player's portal arch in the middle, the player's name on a banner, and room to fight.
- During a portal opening, the plot has a soft glowing wall: the owner can't leave, other players can't come in or hit those monsters. Solo only at launch.
- Beyond the plots are 4 areas, in a ring going outward. Each area is gated by portal level. Gates only let through players whose portal level is high enough, and show "Portal level X" on them.
  1. Ash Wastes (portal level 1): grey ash ground, dead trees, glowing orange embers, broken stone ruins.
  2. Ember Fields (portal level 5): black rock, rivers of lava, fire geysers, orange sky glow. Gate: a rubble wall that crumbles.
  3. Frost Hollow (portal level 10): ice caves, frozen lake, snow falling, blue light. Gate: an ice wall that shatters.
  4. Void Rift (portal level 15): floating broken islands, purple and black, stars, drifting void particles. Gate: a void barrier that fades.
- The inner part of each area has weaker monsters; the outer part has stronger ones with better key drops.
- Build areas so more can be added later as data.

KEYS
- Each key has a KIND (Ash, Ember, Frost, Void) and a RARITY (Common, Rare, Legendary).
- The kind decides which monsters and which gear come out of the portal. An Ember key brings Ember monsters and Ember gear, wherever you use it.
- The rarity decides how hard and how rich the opening is:
  - Common: normal monsters, normal loot, no bosses.
  - Rare: monsters 2x health and damage, 2x coins, better gear odds, and every 5th wave has a 30% chance to be a boss wave.
  - Legendary: monsters 4x health and damage, 5x coins, best gear odds and a real shot at mythic, and every 5th wave is a boss wave.
- Key drops from map monsters: 8% chance per monster in the inner part of an area, 12% in the outer part.
- Key rarity when one drops: inner part 85% Common, 14% Rare, 1% Legendary. Outer part 75% Common, 22% Rare, 3% Legendary.
- Free daily key: one Common key of the best kind the player has unlocked, every 24 hours.
- Key shop (coins): Common and Rare keys of each unlocked kind. Starting prices: Ash Common 150, Ash Rare 1,500; each area costs 6x the area before. Legendary keys are never sold. They only drop from monsters and the Server Rift.
- Getting a Rare key: pop-up, chime, blue glow. Getting a Legendary key: bigger pop-up, golden rays, a server message ("Jas found a Legendary Void Key!").
- Keys are kept in the Keys screen, grouped by kind and rarity. Players choose when to use them.
- To use a key the player must be on their plot. Walking up to the portal shows a "USE KEY" button that opens the key picker.

THE PORTAL
- Cracking it open: the player picks a key, the key flies into the portal, cracks of light in the key's colour spread across it, the ground rumbles, the camera shakes a little, then the portal bursts open and the first monsters crawl, leap or burst out.
- Portal level: 1 to 20 at launch, upgraded with coins on the Portal screen. Starting cost: 300 coins for level 2, then 1.6x more each level.
- Every portal level adds +5% to all coins and gear drop chances from openings.
- Portal levels 5, 10 and 15 unlock Ember Fields, Frost Hollow and Void Rift.
- The portal visibly grows every 5 levels: bigger arch, more runes, more glow. Other players can see how far you are by looking at your portal.

WAVES
- Waves are endless. Monster count: 4 + the wave number, up to 15 alive at once. Past that, monsters get stronger instead of more.
- Every wave: monster health x1.15 and damage x1.10 compared to the wave before.
- Waves mix the key kind's 3 monster types, with tougher types appearing more in later waves.
- A 3-second countdown with a "WAVE 6" banner before each wave. Monsters come out of the portal in small groups over 2 to 4 seconds, not all at once.
- Between waves the player heals 30% of their max health. Health carries over, so "one more wave" with low health is a real risk.
- Between waves there is no timer, but if the player does nothing for 60 seconds, the portal closes on its own and they keep the whole pot.
- If the player leaves the game during a wave, it counts as falling (random half kept). If they leave between waves, they keep the whole pot.

THE POT
- Everything from an opening goes into the pot: coins, gear from monsters, chest gear. Nothing goes to the inventory until the portal closes.
- The pot is always on screen at the top middle during an opening: coin total, the gear icons in it (best ones first, rarity coloured), and "Keep half if you fall" under it.
- The CLOSE PORTAL button only appears between waves, never mid-fight.
- Closing safely: the portal shrinks shut, the pot bursts and everything flies into the coin counter and the inventory, with a celebration sized to the pot.
- Falling (health hits 0 during an opening):
  - The portal slams shut. The pot cracks.
  - Coins: keep exactly half.
  - Gear: a random half is kept, chosen by the server. With an odd number of items, round up in the player's favour.
  - Show it: each gear item flips over one at a time like a card. Kept items glow in their rarity colour and fly to the inventory. Lost items shatter. The whole reveal takes about 3 seconds, and a tap skips it.
  - Then the Recover Loot offer appears (see MONEY).
- Falling on the map (outside an opening) costs nothing: the player just respawns on their plot.

CHESTS
- Normal chest: after every wave cleared. One piece of gear, always better than normal monster drops (use the next key rarity's odds).
- Big chest: every 5th wave (5, 10, 15...). Three pieces of gear; the best one is at least Epic.
- Boss chest: after a boss wave. Three pieces of gear; the best one is at least Legendary. A Legendary-key boss chest has a 15% chance of a Mythic.
- Chest odds get a little better every 5 waves, so wave 20 chests beat wave 5 chests.
- Chests burst out of the portal and land in front of the player. Tap to open.

GEAR
- Two slots: a weapon and armor. Gear is visible on the player's character.
- Weapon types (each with its own feel and its own 3-hit combo):
  - Sword: balanced speed and damage.
  - Axe: slow, heavy hits, extra knockback.
  - Twin Blades: fast, lower damage per hit.
- Armor: one armor set look per key kind. Armor decides max health.
- Every key kind has its own weapons and armor (Ash, Ember, Frost and Void versions of each), so each area's gear looks different.
- Rarities: Common, Rare, Epic, Legendary, Mythic. Always show the word as well as the colour.
- Weapon powers (Rare and up), by kind:
  - Ash: hits can stagger monsters for a moment.
  - Ember: hits set monsters on fire (damage over time).
  - Frost: hits slow monsters.
  - Void: hits have a chance to strike twice.
  Higher rarity = stronger power.
- Crits: 10% chance for double damage, shown with bigger gold damage numbers.
- Levels: each item has its own level, upgraded with coins. New items start at level 1, so switching means upgrading again.
- Max level by rarity: Common 10, Rare 20, Epic 30, Legendary 40, Mythic 50.
- Each level: +6% to the item's main stat. Upgrade cost: rarity base (Common 20, Rare 60, Epic 200, Legendary 700, Mythic 2,500) x 1.2 per level, x the area multiplier.
- Pick rarity base stats so that a level 1 item of the next rarity is about as strong as the rarity below it at half its max level. Switching should never feel like a step backwards.
- Each area's monsters and gear are about 3x stronger than the area before. Coins are about 6x.
- Merge: three of the same item (same kind, type and rarity) merge into one of the next rarity at level 1. Mythic can't merge.
- Sell: extra gear sells for coins (Common 10, Rare 50, Epic 250, Legendary 1,250, Mythic 6,250, x the area multiplier). Ask "Are you sure?" only for Legendary and Mythic.
- Inventory holds 100 items. When it's nearly full, show a warning before the player opens a portal.
- Gear drops from wave monsters: 3% chance per monster. Gear rarity odds by key:
  - Common key: 70% Common, 25% Rare, 5% Epic.
  - Rare key: 40% Common, 40% Rare, 17% Epic, 3% Legendary.
  - Legendary key: 40% Rare, 35% Epic, 20% Legendary, 5% Mythic.

FIGHTING
- Two buttons: ATTACK (big, bottom right) and DODGE (next to it). Thumbstick on the left for moving.
- Attacks auto-face the nearest monster in range, so there's no aiming. Tapping attack again chains the 3-hit combo.
- Dodge: a quick roll of about 0.35 seconds, the player can't be hit during it, 1.5-second cooldown shown on the button.
- Player starts at 100 health; armor adds more. A health bar sits above the attack buttons.
- Every big monster attack shows a red warning zone on the ground first (circle, line or cone), filling up until the hit lands. Small attacks don't need one.
- Bosses get a health bar at the top of the screen with their name.

MONSTERS (3 types plus 1 boss per area; the same monsters appear on the map and out of portals)
Ash Wastes:
- Ash Imp: small and fast, scratches, comes in groups.
- Cinder Hound: wolf that charges in a straight line (red line warning).
- Stone Brute: slow and big, ground slam (red circle warning).
- Boss, The Ashen Golem: ground slams, throws boulders (red circle where they land), roars to call Ash Imps.
Ember Fields:
- Flame Skeleton: sword swings, leaves embers.
- Lava Crawler: spider that leaves fire pools on the ground.
- Ember Bat: swoops down from the air (red line warning).
- Boss, The Molten Knight: fire sword sweeps (red cone), lava eruptions from the ground, charges.
Frost Hollow:
- Frost Wolf: comes in packs, circles and bites.
- Ice Wraith: floats, shoots ice shards in lines (red line warning).
- Glacier Troll: big, freezing stomp that slows (red circle).
- Boss, Frostmaw: giant ice beast, frost breath (red cone), icicle rain (many small circles), tail sweep.
Void Rift:
- Void Shade: teleports behind the player (a purple flash shows where first).
- Rift Eye: floating eye that fires a beam (thin red line, then the beam).
- Void Knight: shield that blocks hits from the front; hit it from the side or behind.
- Boss, The Hollow King: summons Void Shades, fires void orbs, and does a full-arena slam with safe spots shown.
- All names are original. Monsters on the map wander, notice the player, attack, and give up the chase if the player runs far away.

SERVER RIFT
- About every 15 minutes, a giant rift cracks open in the central courtyard. A 30-second countdown shows at the top of every player's screen, with a server message and different music.
- 3 waves of mixed monsters from the areas, then a Rift Boss (rotate through the 4 bosses, bigger and glowing).
- Health scales with how many players join: x(1 + 0.6 for each extra player), so one player alone can still beat it.
- Everyone who did damage gets 1 Rare key (a random kind they've unlocked) and coins. The top 3 by damage get a second Rare key and a 10% chance at a Legendary key.
- Players in the middle of a portal opening get the message and can join after closing.

COMBAT FEEL
- Every hit: hit-stop (freeze 0.05 to 0.1 seconds, up to 0.15 on heavy hits), a white hit flash on the monster, a punchy hit sound, a slash or spark effect, and a little knockback.
- Damage numbers pop out and float up, bigger and gold for crits, coloured for powers (orange burn, blue slow, purple double hit).
- Small camera shake on big hits, boss slams and the portal cracking open. Settings has a camera shake switch.
- Monsters die with their death animation, then burst into ash or particles in their kind's colour. Coins pop out and fly into the pot.
- Weapon trails on every swing, coloured by kind and brighter for higher rarity.

ANIMATIONS
- Build every custom animation with AnimKit from the roblox-animation skill. Look at the filmstrip, fix it, and only then use it. Never ship an animation nobody has looked at.
- Player movement: Roblox's own walk, run, jump and idle, restyled with a pack that fits dark fantasy.
- Player attacks: Sword, Axe and Twin Blades each get their own 3-hit combo with a clear wind-up, strike and follow-through. Hits alternate direction and flow into each other. Upper body only, so the player can move while attacking. "Hit" marker on the contact frame for sound, effects and hit-stop.
- Player also gets: dodge roll, hit reaction, a fall when a wave beats them, a victory pose when closing a big pot, and a key-use animation (holding the key up to the portal).
- Every monster gets: idle, move, attack (wind-up of at least 0.4 to 0.5 seconds so players can react), hit reaction, and death with a small bounce at the end. Each monster type moves and attacks differently.
- Bosses also get an intro roar when they come out of the portal and an animation for each special attack.
- Monsters come out of the portal by crawling, leaping or bursting out. They never just appear.
- Things that aren't characters (portal swirl, floating spinning keys, chest lids, coins, gear spinning in the inventory) use tweens and effects, not keyframe animation.
- Check every animation on phone and PC. No sliding feet, no feet under the floor, no knees bending the wrong way.

MODELS
- Monsters, bosses, the portal, keys, chests, weapons and armor are made with Tripo, fixed up in Blender, then imported into Studio. Use the Blender way, not Tripo's Roblox bridge.
- Ask me before spending Tripo credits. Plan for about 2,000 to 3,000 credits for the whole game.
- Write one locked style line before the first model and put it at the end of every prompt: dark fantasy, chunky stylized shapes, readable from far away, glowing accents. Judge every new model next to the ones already approved.
- Tripo HD models come in at millions of triangles. Retopo them down and keep them inside the triangle caps in the roblox-ai-models skill. Export textures at 1k, and shrink small props to 256 or 512.
- Tripo models come in tiny. Scale them in Blender before export.
- Humanoid-shaped monsters (Flame Skeleton, Stone Brute, Glacier Troll, Void Knight, Molten Knight, Hollow King) can use Tripo's Auto Rig, with skin weights fixed in Blender. Creature shapes (Imp, Hound, Crawler, Bat, Wolf, Wraith, Shade, Rift Eye, Golem, Frostmaw) can use part-based rigs from the roblox-ai-models skill if Tripo's rig stretches them.
- Each kind's monsters and gear share a clear look: Ash = grey stone and orange embers, Ember = black rock and lava, Frost = ice blue and white, Void = purple and black with stars.
- Rarer gear must look rarer, not just a different colour: more glow, particles, trails, and a bigger, cooler shape for Legendary and Mythic.
- Weapons and armor sit correctly on the character from every side.

THE LOOK OF THE WORLD
- Future lighting, Atmosphere fog coloured per area, Bloom so glows pop, and ColorCorrection per area.
- Each area has its own lighting and particles: drifting embers in Ash, heat haze and lava glow in Ember, falling snow in Frost, floating void specks in Void.
- Plots and the courtyard: dark stone, torches, banners, glowing runes on the portal arches.
- Use parts and generated materials for floors, walls and paths. Use Tripo models for creatures and hero props.
- Everything must look great on a phone at low graphics too.

ANIMATED UI
- Follow the roblox-game-ui skill. All UI motion goes through one Anim module.
- Style: dark fantasy. Near-black panels with a subtle gradient, one gold accent, thin gold strokes, bevelled corners, coloured glows from UIShadow, one bold display font and one clean body font. Write these tokens down before building any screen.
- Rarity colours with the word always shown: Common grey, Rare blue, Epic purple, Legendary gold, Mythic red. Legendary and Mythic get an animated shine on their border everywhere they appear.
- HUD (phone first):
  - Top left: coins (big and easy to read).
  - Top middle during an opening: wave number, the pot, "Keep half if you fall". Boss health bar under it during boss waves.
  - Left side: Inventory, Portal, Keys, Quests, Index buttons, each with an icon and a word.
  - Right side: STORE and SETTINGS.
  - Bottom right: ATTACK and DODGE. Bottom left: thumbstick. Health bar above the attack buttons.
  - Nothing important under the thumbs or the top bar.
- Every button: hover on PC, press down and spring back on release, a soft click sound. Tap answers within 0.1 seconds.
- Windows grow out of the button that opened them, the content arrives as a quick wave, the main button lands last. Closing is faster than opening. One window at a time.
- Screens: Inventory (grid of gear with filters, equip, upgrade, merge, sell), Gear card (stats, level, power, upgrade cost), Portal (level, next bonus, cost, next area unlock), Keys (your keys and the key shop), Store (gamepasses), Daily Quests, Index, Leaderboards, Settings.
- The pot: coins and gear icons fly from monsters into the pot on a curve, the number counts up and pops, and the pot glows brighter as it grows.
- Wave banner: "WAVE 6" slams in, holds briefly, then gets out of the way.
- Between waves: a clear panel with the pot, CLOSE PORTAL (gold) and ONE MORE WAVE (red), big and easy to tap, and the player's health shown so the risk is clear.
- Reveals for chests, keys and gear scale with rarity: under 2 seconds for Common, 5 to 6 seconds with rays, confetti and a shine for Legendary and Mythic. Tap skips to the result.
- Closing safely: the pot bursts into coins that fly into the coin counter. Falling: the pot cracks, then the card-flip reveal of the random half.
- Can't afford something: the button shakes and the price flashes red. No error popup.
- Never animate a Robux button to push a purchase. Recover Loot never pulses, flashes or counts down.
- Support Reduced Motion the way the roblox-game-ui skill describes.

SOUND AND MUSIC
- Every weapon type has its own swing and hit sounds. Monsters have their own growls, attacks and deaths. The portal crack has a deep rumble and a burst. Chests, rarity reveals, coins (pitch rising as they stack), level ups, close and fall each get their own sound.
- No sounds that are harsh, static-y or too high pitched. Measure them as the skills describe.
- Music: a calm dark fantasy track for each area, combat music during openings that gets more intense every 5 waves, boss music, and Server Rift music.
- Settings: a music volume slider and a sound effects volume slider, not just on and off switches. Plus camera shake on or off.
- Mute the music and sounds when testing in Studio.

LONG-TERM
- Daily quests: 3 a day from a list (for example: reach wave 10, close a pot worth 5,000 coins, beat 100 monsters, open 3 portals, beat a boss, merge an item, help in a Server Rift). The first two reward coins and a Common key; the third rewards a Rare key. Reset every 24 hours.
- Index: a book with a page per area. Each page shows the 3 monsters and the boss beaten, and every weapon and armor found by rarity. Rewards: finishing an area's monster section gives a Rare key; finishing a rarity row gives coins; finishing the whole index gives a special title.
- Two leaderboards, in the world near the courtyard and in the Leaderboards screen: Highest Wave ever reached, and Biggest Pot ever closed. Pots saved with Recover Loot don't count.

MONEY
- Gamepass 2x Coins: double coins from everything.
- Gamepass Luckier Keys: better key rarity when a key drops (inner part 75% Common, 22% Rare, 3% Legendary; outer part 65% Common, 30% Rare, 5% Legendary). This is a paid random item: show the exact odds with and without the pass in the Store and the Keys screen, and hide it for players in countries where paid random items are restricted (check with PolicyService).
- Recover Loot: a one-time purchase, not a gamepass. Offered right after the fall reveal. It shows exactly which coins and items were lost and gives all of them back. Use 3 developer products at different prices for small, medium and big lost pots. Skippable with one tap.
- Never hard-code prices. Read them from the product info. Handle purchases safely so a purchase is never lost or given twice.

SAVING
- Save coins, gear (with levels), keys, portal level, index, daily quests, daily key time and leaderboard stats. Use session locking, retries, autosave and saving on shutdown, as the roblox-datastores skill describes.
- The pot is never saved. Leaving follows the rules in WAVES.

SECURITY
- The server decides everything important: hits and damage (check range and cooldowns), drops, key rarity and kind, the pot, the random half, coins, upgrades, merges, sells and purchases. Never trust the client.
- Rate-limit every remote.
- Test commands only work in Studio, never in the live game.

PHONES AND SPEED
- Phones first. At most 15 monsters alive per player. Pool effects and damage numbers. Use StreamingEnabled.
- Keep every model inside its triangle cap and texture size. Check the busiest moment (a boss wave with effects) on a phone and keep it smooth.

FOR LATER UPDATES (do not build yet)
- Friends joining your portal to fight together.
- More gear slots, like a helmet or a pet.
- A beam that shoots up from your plot when a rare boss comes out.
- Rebirth or a skill tree.
- More areas and key kinds.

RULES FOR BUILDING
- The game must be fun for one player alone on an empty server.
- Monsters, bosses, gear, key kinds, areas and odds are data in tables, so new ones can be added without new code.
- Only original names and art. Don't copy another game's look.
- No game was called "Crack a Portal" when searched on 12 Oct 2026. Search Roblox again before anything is published.
- Check every change in game with the roblox-playtest-review skill, including animations and sounds, on phone, tablet and PC.
- Show me pictures and wait for my yes before publishing.

BUILD ORDER (after I say the grey test is fun; show me pictures after each)
1. Core systems as data: keys, waves, the pot and random half, chests, gear, levels, merge, sell, portal levels, saving.
2. The map: plots, courtyard, the 4 areas and their gates, lighting.
3. Models: style line first, then the portal, the Ash monsters and boss, Ash gear. Show me before doing the other areas.
4. Animations: player combos, dodge and reactions, then each monster and boss.
5. Combat feel: hit-stop, effects, damage numbers, trails, camera shake.
6. Animated UI: tokens, HUD, every screen, the pot, reveals, the fall reveal.
7. Sound and music.
8. Long-term: daily key, daily quests, index, leaderboards, Server Rift.
9. Money: gamepasses and Recover Loot.
10. Tutorial.
11. Full check with roblox-playtest-review, then pictures for my yes.

GREY TEST (build this first, in plain grey parts, 1 to 2 days)
- A few grey monsters on the map that drop a common key.
- One plain portal on the player's plot.
- Three waves of grey monsters that get harder, dropping coins and gear (one weapon and one armor).
- A chest after each wave.
- The pot on screen, CLOSE PORTAL and ONE MORE WAVE between waves, 30% heal between waves.
- Falling keeps exactly half the coins and a random half of the gear, with a simple version of the card-flip reveal.
- Attack and dodge buttons, red warning zones, a simple placeholder swing, plus hit-stop, damage numbers and hit sounds.
- No Tripo models, no final animations, no shop, no saving, no other areas, no rift and no upgrades yet.
The test must answer one thing: does "one more wave?" feel exciting?

STOP NUMBER (for after it is published)
Once about 300 new players have tried the game, at least 1 in 3 should still be playing at five minutes. If not, we fix the start or move on to the next game.