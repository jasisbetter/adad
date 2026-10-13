# Rules for every helper working on Crack a Portal

You are one of several helpers writing the Luau code for Jas's Roblox game **Crack a Portal**, in parallel. Other helpers own other files at the same time.

## Read first (in this order)
1. `/home/user/adad/crack-a-portal/PLAN.md`: the contract (file map, Config schema, Logic API, remotes, payload types, system APIs, Bus events, save schema, attributes). **Code against it exactly.**
2. `/home/user/adad/crack-a-portal/BRIEF.md`: Jas's full design. It is the spec. Read every section your files touch.
3. `/home/user/adad/crack-a-portal/PROMPT.md`: the coding job (rules in section 1, your BUILD ORDER step in section 2, hooks in section 3).
4. `/home/user/adad/crack-a-portal/NOTES.md`: how the grey test was built, decisions, tuning results and **gotchas** (read all gotchas before touching UI or combat).
5. The real files already in `src/` (read anything you call into). The 5 original grey-test files are `Shared/Anim.luau`, `Shared/Sfx.luau`, `Shared/Logic.luau`, `Shared/Net.luau`, `ServerStorage/Build.luau`: keep their APIs.
6. The skill digests your prompt names, in `/tmp/claude-0/-home-user-adad/2cbd4a97-242a-57be-a125-caafa859eb98/scratchpad/digests/` (ui.md, audio.md, anim_models.md, playtest.md, design.md). For more detail, the full skills are in `/root/.claude/skills/synced/34f0ed4c-634d-41ee-be3a-16da0ca2085b_5757718a-ba5e-4f5a-9309-e0938f55edb7/<skill>/SKILL.md` and `/root/.claude/plugins/synced/34f0ed4c-634d-41ee-be3a-16da0ca2085b_5757718a-ba5e-4f5a-9309-e0938f55edb7/0093771a-23a5-4f48-9dda-826f8a0139a9/skills/<skill>/SKILL.md` (roblox-architecture, roblox-datastores, roblox-security, roblox-performance, roblox-testing, luau-strict-typing, roblox-ui, new-system).

## Hard rules
- **Only create or edit the files your prompt assigns to you.** If you need something from a module you don't own, call it exactly as PLAN.md specifies (its owner is writing it now). If PLAN.md doesn't cover what you need, pick the smallest sensible API, use it, and write the exact request in your notes file (below) under "Needs from others".
- Every file: `--!strict` first line (Anim.luau stays `--!nonstrict`), typed, complete. **No TODO, no `...` placeholders, no stub functions, no half-written code.** Every file must compile.
- Modern APIs only: `task.*`, constraint movers (no BodyMovers), `Players:GetPlayers()`, `GetAttribute`, `Animator:LoadAnimation`, `workspace:Raycast` + `RaycastParams`, `GetPartBoundsInRadius` + `OverlapParams`, `...Async` names (`GetProductInfoAsync`, `UserOwnsGamePassAsync`, `GetPolicyInfoForPlayerAsync`), properties set before `Parent`, never `Instance.new(class, parent)`, `Activated` not `MouseButton1Click`, `PreRender`/`Heartbeat` not `RenderStepped`, no `wait()`/`spawn()`/`delay()`.
- **Server decides everything important.** Every remote handler: `RateLimit.allow` with `Net.Limits`, then type/NaN/inf/range/length checks, ownership, distance and state checks. Never trust a number from the client.
- **Everything is data** in `Shared/Config.luau`; pure maths in `Shared/Logic.luau`. No magic numbers in systems when a Config row fits (small cosmetic constants are fine).
- **Everything is made by code.** No hand-made Studio instances are required. Models/animations/sounds made later must slot in by name or id; with nothing there, the grey fallback runs.
- **Performance, phones first:** no per-frame allocations in hot loops (reuse tables, hoist closures), pool effects and damage numbers, clean up every connection on player leave / character respawn / instance destroy, AI at 10 Hz, batch remotes, write a property only when it changes, `pcall` around each per-frame job.
- **Sound:** all effects through `Shared/Sfx.luau` (client only), music through the Music controller. New sounds get rows with `id = 0`. **Never pick or invent a sound or music id.** Keep the Studio mute (`StudioMuteUntil`).
- Never touch any other game or place, never save to Roblox, never publish. Only original names and art.
- The game must be fun for **one player alone on an empty server**.
- Write Luau, not Lua 5.x: `continue`, `+=`, backtick strings, if-expressions. A Luau function holds at most 200 locals: keep modules tidy (put state on tables).
- Comments: short and plain, like the existing files.

## Checks you must run before you finish (from `/home/user/adad/crack-a-portal`)
- `lune run tools/check.luau`: compiles every file with the real Luau compiler. Fix every syntax error in your files.
- `lune run tools/test.luau`: runs the specs (pure modules only). Keep everything passing; add specs for pure logic you write (`src/ServerStorage/Tests/<Name>.spec.luau`, see `Run.luau` for the `t` API).
- `selene <your files>` (config: `selene.toml`, std `roblox_offline`): fix errors and real warnings in your files.
- `stylua <your files>` to format them (config `stylua.toml`).
- Re-read your own files once, adversarially: wrong API names, nil indexing, missing cleanup, unvalidated remote args, types that don't match PLAN.md.

## Your notes file (required)
Write `/home/user/adad/crack-a-portal/notes/<your-helper-name>.md` with these sections (short bullets):
- **Files**: every file you created or changed, one line each with what it does (this becomes CHANGES.md).
- **API**: the public functions/fields your modules export (exact signatures).
- **Deviations from PLAN.md**: anything you did differently and why.
- **Needs from others**: exact calls you make into modules you don't own that PLAN.md doesn't already list.
- **Decisions**: every small pick you made (numbers, names, layouts) for DECISIONS.md.
- **Studio checks**: what must be checked in Studio for your part (for TODO_STUDIO.md).
- **Assets/anim/sound hooks**: model names, attachments, animation ids, Sfx rows your code expects (for ASSETS.md).
