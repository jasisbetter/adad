# server-monsters helper notes

## Files
- `src/ServerScriptService/Server/Systems/Monsters.luau` (rebuilt from NOTES.md, extended): every monster (opening / map / Rift). AnimationController rigs moved by the server with AlignPosition + AlignOrientation, one 10 Hz AI loop (emerge, idle/wander, chase by behaviour, give up + return home, windup/attack/recover, stagger, roar, dead), damage/knockback/kill/despawn, boss bar, animation hooks, Status integration, Attacks context.
- `src/ServerScriptService/Server/Lib/Attacks.luau` (new): `Attacks.run` for all 12 Config shapes (melee, charge, slam, cone, rain, projectile, beam, pool, teleport, swoop, summon, arena), Warn remote zones, hazards ticked at 2 Hz damage, plus the pure AI helpers.
- `src/ServerStorage/Tests/Attacks.spec.luau` (new): 10 tests for the pure helpers (wind-up floor, slam centre, shot fans, rain points, teleport-behind point, shield arc, summon cap, attack choice and boss rotation, approach/circle/strafe points).

## API
Monsters (all PLAN section 7 + Extra hooks):
- `spawn(defId, cf, opts: SpawnOpts): Mon` (errors on an unknown id)
- `damage(mon, amount, by: Player?, dir: Vector3?, opts: { heavy, knock, crit, power }?): boolean` (true = killed; `power = "burn"` skips knockback/interrupt)
- `kill(mon, by: Player?)`, `despawn(mon)`, `fromModel(model): Mon?`, `all(): { Mon }` (copy), `hittableBy(player): { Mon }`, `ownedBy(player): { Mon }`, `countOwned(player): number` (alive opening monsters), `setTarget(mon, player?)`
- `setPlayerDamage(fn(player, amount, src))`, `onDamage(fn(mon, amount, by?))`, `onDeath(fn(mon, killer?))`, `blocks(mon, fromPos): boolean`, `send(mon): { Player }`
- extras: `despawnOwned(player)` (also clears that player's hazards), `count(): number` (alive monsters)
- types: `Monsters.Mon`, `Monsters.SpawnOpts`, `Monsters.DamageOpts` (defined in `Attacks`, re-exported)
- `Mon` = PLAN fields + `opts: SpawnOpts`, `boss: boolean`, `lastBy: Player?`, `seq: number` (attack sequence; bumped by interrupts/death). `mon.data.summoned = true` and `mon.data.summoner = <Mon>` on summoned monsters.

Attacks (Lib):
- `run(mon, attackId, target: Player?)` (yields), `bind(ctx)`, `tick(now)` (hazards), `clear(mon)`, `hazardCount()`
- pure: `windupFor(a)`, `slamAtSelf(a)`, `spreadDirs(dir, count, spreadDeg)`, `rainPoints(center, count, spread, rng)`, `behindPoint(pos, look, dist)`, `blocks(origin, look, arcDeg, fromPos)`, `summonRoom(current, cap, wanted)`, `chooseAttack(ids, ready, now, dist, startIndex, rotate): (id?, nextIndex)`, `approachPoint`, `circlePoint`, `strafePoint`
- types: `Attacks.Mon`, `Attacks.SpawnOpts`, `Attacks.HurtSrc = { mon: Mon?, status: StatusDef?, heavy: boolean?, attack: string? }`, `Attacks.Ctx`

## Deviations from PLAN.md
- `Attacks.run(mon, attackId, target)` keeps PLAN's signature but needs `Attacks.bind(ctx)` first (Monsters does it in init) so Lib never requires Monsters.
- Monsters fires **`MonsterBeaten(killer, monsterId, mode)` and `BossBeaten`** on every kill with a killer (all modes, summons included). **Openings, MapMonsters and Rift must NOT fire them again** (they still update `profile.stats`).
- Status has a single burn handler: **Monsters owns `Status.setBurnHandler`** and dispatches: monsters -> `Monsters.damage(..., { power = "burn" })`, players -> the injected player-damage fn with `src = { heavy = false, attack = "burn" }`. Combat must not call `setBurnHandler` (it currently doesn't). Monsters also owns `setStaggerHandler` (stagger cancels a non-boss attack).
- Root keeps `CanQuery = false` (hit tests are by distance; nothing needs to raycast monsters). Visual parts CanCollide/CanTouch/CanQuery off, Massless. All parts in collision group `Monsters`.
- Emerge direction: Build's `MonsterSpawn` marker faces *into* the portal, so for `opts.plot` + `opts.emerge` the monster comes out towards the plot's bounding-box centre; otherwise along `cf.LookVector`.
- Death Fx: `Fx Death` (reliable) to the owner, `FxU Death` to everyone else within 150 studs (not both to the owner).
- Bosses: heavy hits and stagger do not interrupt their attacks; knockback x0.15. Emerging monsters are invulnerable and not in `hittableBy`.
- Extra Fx `k` values: `Emerge { style, pos, kind, model }` (owner reliable + FxU near), and `kind` added to `Projectile`, `Beam`, `Hazard` events. `style` = the attack id (e.g. `GolemBoulder`, `IceWraithShards`); beam warning lines use style `"thin"`.

## Needs from others
- **Openings**: spawn with `Monsters.spawn(id, Plots.spot(plot, "MonsterSpawn"), { mode = "opening", owner, plot, hpMult = spec.hpMult, dmgMult = spec.dmgMult, coinMult, emerge = true, boss = bossWave })`. Summoned monsters (`mon.data.summoned`) also fire `onDeath`: give their coins but don't count them toward the wave's `left`; at wave clear call `Monsters.despawnOwned(player)` (or despawn `ownedBy` leftovers) so summons don't linger. Don't fire `MonsterBeaten`/`BossBeaten`.
- **Rift**: boss spawn opts `{ mode = "rift", hpMult = waveHp * Config.Rift.bossHp * Logic.riftHpMult(n), scale = Config.Rift.bossScale, glow = true, boss = true, emerge = true }` (summons divide out `Rift.bossHp`). Set player attribute `InRift = true` for participants (Monsters also counts anyone within riftRadius + 12 of the centre who is not in an opening). Track damage with `Monsters.onDamage`.
- **MapMonsters**: spawn with `{ mode = "map", home = cf, band, area, hpMult, dmgMult }`; respawn via `onDeath`.
- **Effects / MonsterFx (client)**: Warn shapes: `line` (cf at start on the ground facing dir, `length`, `width`), `cone` (cf at apex facing dir, `length` = `radius` = reach, `angle` full opening), `circle` (cf at centre, `radius`), `rain` (`circles` list + `radius`, one Warn per staggered group of 3, 0.15 s apart), `arena` (cf centre, `radius`, `safe`, `safeRadius`). Monster attributes for placeholder motion: `State` (emerging, idle, wander, chase, return, windup, attack, recover, stagger, roar, dead), `Attack` (attack id during windup/attack), `Windup` (server time the wind-up ends), `Emerge` (style while emerging), `HitAt` (server time of the last hit: white flash), `Dead`, `HP`, `MaxHP`, `Boss`, `Kind`, `Def`, `MonsterId`, `Owner`, `Mode`, plus Status's `Burn`/`Slow`/`Stagger`.
- **init.server** already registers the groups; Monsters registers them again (idempotent, in pcall) and also makes `Fx` non-collidable with `Default`.

## Decisions
- AI 10 Hz (`Config.MapMonsters.tickHz`), one `while task.wait` loop, per-monster `pcall`, walks the list backwards (swap-remove on despawn).
- AlignPosition: OneAttachment on `RootAttachment`, MaxForce 1e7, Responsiveness 40, MaxVelocity = speed x `Status.speedMult` (x1.4 returning home, x0.45 wandering, x1.35 wolf dash-in). AlignOrientation: MaxTorque 1e7, Responsiveness 30, MaxAngularVelocity 12 rad/s (bosses 4, Void Knight 1.6 so players can flank).
- Ground: one cached RaycastParams (exclude Workspace.Monsters, Workspace.Fx, characters; RespectCanCollide), ray only when the goal moves > 1.5 studs. Align targets written only when they move > 0.1 stud / 0.02 rad.
- Emerge: crawl 1.2 s from below ground, 5 studs out; leap 0.9 s, 9 studs, 5-stud arc; burst 0.45 s, 6 studs, small hop + Emerge Fx. Random +-2.5 studs sideways so groups spread.
- Boss intro roar 1.5 s invulnerable, Shake 0.5 to recipients; first attack 0.4 s after it.
- Knockback: knock x 0.3 studs over 0.25 s (default knock 6), bosses x0.15. Death despawn 0.9 s.
- Map: notice/giveUp/leash from Config; a chase ends when the player is past `giveUp` or more than `leash + engage + 6` from home; return home at 1.4x speed and heal fully on arrival; wander every 3-7 s within min(12, leash x 0.3); asleep beyond `MapMonsters.activeRadius`.
- Pack (Frost Wolf): circle at 9 studs (spin 1.1 rad/s, golden-angle offsets so wolves spread), dash in for 1.8 s every 1.5-3 s, bite only during a dash. Float: keep 0.6 x longest attack range (8-24 studs) away, drift 4 studs sideways, switch side every 2.5-4 s. Melee/boss/shield/teleport: stop at 0.8 x shortest attack range.
- Attack choice: normal monsters take the ready attack with the shortest range that reaches; bosses rotate through their list. Global gap after an attack = wind-up + 0.5 s, recover 0.35 s. Summons capped at `Waves.maxAlive + 4` per opening / Rift, 2x count per map caster; no room -> retry in 2 s.
- Attacks: player reach pad 1.5 studs; height tolerance -4.5/+9 studs from the shape's ground; dashes/shots simulated every 0.05 s; melee tracks the target for half its wind-up then commits; teleport appears 3.5 studs behind the target, strikes 0.35 s later; beams/breath hurt each player once per attack; hazards tick every 0.5 s (dps x monster damage), max 48 hazards, 4 per rain attack, and an opening's hazards stop once that owner has no monsters left. Heavy attacks: Shake 0.6 to those hit, 0.3 to recipients nearby. Arena: plot bounding box centre (radius clamped to the plot) / Rift circle / around the caster on the map.
- Rift boss glow: PointLight (brightness 3) in Root and Neon parts recoloured to the kind's glow; size via `Model:ScaleTo`.
- Boss bar: `{ name = bossTitle or name, hp, maxHp, kind, rift }`, sent on HP change at most every 0.2 s, refreshed every 1 s for recipient changes, `false` on death/despawn or when a player stops being a recipient, re-sent on `PlayerData.onReady`.

## Humanoid vs AnimationController (how it was implemented)
- No Humanoids. Each monster = Assets/Templates rig with `AnimationController > Animator`; Root unanchored, Massless false, `SetNetworkOwner(nil)`; AlignPosition/AlignOrientation in Root; HP lives in the Mon table and the `HP` attribute. Movement is only align-target writes at 10 Hz; no Humanoid state machine, no MoveTo, no per-monster scripts or connections.
- Studio must measure (MicroProfiler + Script Performance, server and a phone client) with 8 openings x 15 monsters + ~80 map monsters (several players spread so most are awake) + a Rift wave: the `Monsters` loop time per tick (target < 2 ms), physics step time for ~200 aligned assemblies, replication bandwidth (Network stats), client frame time on a phone. If physics is too costly, the fallback is anchored Roots moved by `PivotTo` with client-side smoothing (same API).

## Studio checks
- Spawn each monster in an opening: emerge style reads (crawl from under the floor, leap arc, burst pop), lands inside the plot in front of the portal, no falling through the floor or floating; flyers hover at `hover`.
- Ground ray under the MonsterSpawn marker does not hit the portal arch (monsters should not land on top of it).
- Every attack: warning shape matches the damage area (line, cone, circles, rain groups, arena safe spots), wind-up feels fair, charge/swoop dashes follow the line, teleport flash then strike, beam lasts its duration, fire pools hurt while standing in them and stop after the wave.
- Void Knight blocks from the front only; turning is slow enough to flank. Frost Wolves circle and take turns biting.
- Map monsters: notice, chase, give up at the leash, walk home and heal; asleep beyond 160 studs.
- Boss: intro roar (invulnerable 1.5 s, camera shake), boss bar updates and disappears on death; Rift boss scaled and glowing.
- Knockback distance with Sword vs Axe; heavy hit cancels a wind-up.
- Performance measurement above.

## Assets/anim/sound hooks
- Models: `ServerStorage.Assets.Monsters.<MonsterId>` (Assets.monster contract: PrimaryPart `Root` at the bottom centre facing -Z, `AnimationController > Animator`, `RootAttachment` in Root (made if missing)). Scripts inside are removed.
- Animation ids (Config.Monsters[id].anims, 0 = none): `idle` (looped, Idle), `move` (looped, Movement), `hit` (Action2), `death` (Action4), `emerge` (Action3), `roar` (Action3), `attacks[attackId]` (Action; played at the start of the wind-up, `Hit` marker should sit at the wind-up end). Tracks load once per rig via AnimHooks and are cleared on despawn.
- Sounds: none on the server; clients play `def.sounds.*` from the `State`/`Attack` attributes and Fx events.
