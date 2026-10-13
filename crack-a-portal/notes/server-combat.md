# server-combat helper notes

## Files
- `src/ServerScriptService/Server/Systems/Combat.luau` (rebuilt from NOTES.md + extended): Attack/Dodge handlers, server-decided combo, auto-face, arc/range/finisher radius, crits, shield blocks, weapon powers (stagger/burn/slow/double), Hits batch + FxU MonsterHit, damagePlayer (dodge i-frames, slow/burn on players, Hurt/Shake Fx, onDown chain, default map fall), 4 Hz loop (regen, anti-teleport samples, player burn, slow WalkSpeed), per-player cleanup.
- `src/ReplicatedStorage/Shared/CombatMath.luau` (new): pure combo/arc maths shared with the client: `stepTime`, `nextStep`, `targetRadius`, `inSwing`, `faceDirection`, `nearest`, `speedOk`, `hitAmount`.
- `src/ServerStorage/Tests/CombatMath.spec.luau` (new): 11 tests (combo window/ignore/reset, every weapon chains its combo, arc/range/body radius, finisher radius, height, face/nearest, speed check, hit amounts).

## API
Combat (PLAN section 7 + extras):
- `init()`, `start()`
- `onAttack(player)`, `onDodge(player)` (connected to the Attack / Dodge remotes in `init`)
- `damagePlayer(player, amount: number, src: DamageSrc?)` where `DamageSrc = Attacks.HurtSrc` `{ mon: Mon?, status: { kind, amount?, dps?, duration }?, heavy: boolean?, attack: string? }`
- `isInvuln(player): boolean`, `speedMult(player): number` (Status.speedMult)
- `onDown(fn: (Player) -> boolean)` (registration order; first `true` owns the fall)
- extras: `isFlagged(player): boolean` (anti-teleport window: no attacks, no loot credit), `noteTeleport(player)` (call right before a server move of a character), `_test = { math = CombatMath }`
CombatMath (Shared, pure):
- `LATENCY = 0.08`, `VERTICAL_SLACK = 6`
- `stepTime(step): number`
- `nextStep(prevStep, prevStepTime, elapsed, comboLen, reset, grace, latency?): number?` (nil = too early, ignored)
- `targetRadius(size: Vector3): number`
- `inSwing(origin, dir, pos, targetRadius, range, arc, radius?, height?): boolean`
- `faceDirection(origin, fallback, target?): Vector3`, `nearest(origin, points, radii, range): number?`
- `speedOk(a, b, dt, maxSpeed): boolean`, `hitAmount(base, mult, crit, critMult): number`

## Deviations from PLAN.md
- Extra character attribute `SwingStep` (1..3). Order written per swing: `SwingType`, `SwingStep`, then `Swing` (counter, +1 per swing). Client Combat should react to `Swing` and read the other two.
- Unarmed swings use `SwingType = "Sword"` (Sword timings, `Config.Combat.fistDamage`), so the client can always look up `Config.GearTypes[SwingType]`.
- Player burn is ticked by Combat (4 Hz, own state, player attribute `Burn` = server-time expiry), not by Status, so player burn never depends on Monsters' Status loop. Player slow goes through `Status.apply(player, "slow", ...)`. `src.status.dps` is absolute damage per second.
- FxU `MonsterHit` carries extra fields `by` (attacker UserId) and `blocked` (shield). `Notify.fxNear` also reaches the attacker: **client must skip MonsterHit where `by == LocalPlayer.UserId`** (it has the Hits batch already).
- Hits remote is sent only when the swing hit something (no empty batches).

## Needs from others
- Monsters (already matches): `hittableBy`, `blocks`, `damage(mon, amount, player, dir, { heavy, knock, crit, power })`, `setPlayerDamage`, burn handler forwarding Player targets to the injected function.
- Rift / Openings / DebugTools: call `Combat.noteTeleport(player)` right before moving a character far (e.g. into the Rift circle), otherwise a > 160 studs/s jump that doesn't land on the player's own plot or the SpawnLocation blocks attacks for 3 s.
- Openings / MapMonsters / Rift: when giving loot or kill credit, skip players where `Combat.isFlagged(player)` is true.
- Openings / Rift `onDown` handlers: Combat clears burn after the handlers run; they own healing afterwards (damage is ignored while HP is 0).
- Client Combat: dodge movement on `Dodging` attribute (server sets it for `Config.Combat.dodge.duration`; the client should start the roll on input, the server only grants i-frames + cooldown). Hit-stop/flash/numbers from `Hits` (`blocked` hits: amount 0, show a clank). Fx `Dodged` / `Hurt { amount, pos, status }` / `Shake { amount = 0.45 }` (trauma 0..1).
- Effects/MonsterFx: FxU `MonsterHit { model, amount, crit, power?, blocked?, by }`.

## Decisions
- Combo latency allowance 0.08 s (a step may come 0.08 s before the previous step's windup + contact + recover ends); combo window = comboReset + comboGrace from the previous swing's start; after the finisher it restarts at 1. Too-early taps are dropped (no queue).
- No attacks while the character attribute `Dodging` is set, while HP is 0, or while flagged.
- Targets: Monsters.hittableBy within range + body radius ((size.X + size.Z) / 4 of the Root) and the arc widened by the body's angular size; finishers also hit everything within `radius` all around; vertical reach = range + half height + 6 studs; nearest first, at most `maxHitsPerSwing` monsters (Twin Blades finisher = 2 strikes per monster, Void double = one extra strike).
- Auto-face uses the nearest hittable monster within `autoFaceRange` (body radius counted); the server never rotates the character (the client does).
- Crit: 10% x2, rolled per strike; heavy flag sent to Monsters for heavy steps and crits. Double-power extra hit copies the strike's damage, crit false.
- Powers: burn and slow land on every hit (burn dps = power.dps x hit damage, credit to the player), stagger rolls its chance; stagger immunity `Config.Combat.staggerImmune` s after a stagger ends (Combat keeps it per monster); bosses stagger for half the time.
- Dodge: invulnerable for duration + 0.1 s; status effects are blocked too; burn ticks keep going during a roll.
- Map fall default: `Plots.sendHome` + `PlayerData.fullHeal` + 2 s invulnerability.
- Anti-teleport: 4 Hz root samples, > 160 studs/s flags 3 s; skipped 0.6 s after respawn, after Combat's own sendHome, after `noteTeleport`, and when the jump lands on the player's own plot (6 studs margin) or within 16 studs of the SpawnLocation.
- Regen: `regenPerSecond` x dt at 4 Hz after `regenDelay` s without damage; skipped with `InOpening` / `InRift`.
- Slow on players: WalkSpeed = speed at slow start x Status.speedMult, restored at the end (written only when it changes).
- FxU MonsterHit radius 90 studs. Heavy hit on a player -> Fx Shake amount 0.45.

## Studio checks
- Each weapon: hold ATTACK -> full 3-step combos, no dropped taps at a normal tapping rhythm on phone and PC (ping 100-200 ms); finisher hits monsters behind.
- Auto-face: hits land on the nearest monster even while facing away (client must turn too).
- Void Knight: front hits show blocked (0), side/back hits land.
- Burn/slow numbers coloured, slow visibly slows monsters; stagger stops them; bosses only half.
- Dodge through a Stone Brute slam: Dodged Fx, no damage; Frost Troll stomp slows the player and WalkSpeed returns after.
- Map fall: back at the plot with full HP, no 3 s attack lock afterwards; teleporting via DebugTools `home` does not lock attacks.
- Regen starts 4 s after the last hit outside openings, not inside an opening.

## Assets/anim/sound hooks
- Character attributes for client swings: `Swing` (counter), `SwingStep` (1-3), `SwingType` (Sword/Axe/TwinBlades), `Dodging`. Player attribute `Burn` (server-time expiry), `Slow` (from Status).
- Weapon swing animation ids: `Config.Anims.weapons[type][step]`; the server's contact time is the end of `windup` for each step, so a real animation's `Hit` marker should sit at `windup` seconds.
- No sounds in these files (client plays `GearTypes[type].swing/hit/finisher`).
