# server-map helper notes

## Files
- `src/ServerStorage/Build.luau` (grey test, extended): builds the whole map from Config: hub ground, stone courtyard with the Rift rune circle, 8 plots (dark stone, Templates/Assets tier-1 portal, torches, cloth banners, name banner, markers, ForceField walls), the Config.Areas rings (inner/outer ground tint per band), Ash ruins/dead trees/rocks, Ember lava arcs/geysers/black rocks, Frost frozen lakes/ice spikes, Void floating islands/star specks/shards, ring walls (rubble/ice/void) with 4 gates each, roads out through the gates, monster spawn points, two world leaderboard boards, world edge, SpawnLocation, hub lighting, StreamingEnabled. Returns a summary string.
- `src/ServerScriptService/Server/Systems/Plots.luau` (new, rebuilt from NOTES.md): plot assignment/release, banner, plot attributes, isInside/clampInside, walls, sendHome, spot, setTier, setPortalState, character spawn home + "Players" collision group.
- `src/ServerScriptService/Server/Systems/Gates.luau` (new): areaAt, canEnter, unlockedArea, 4 Hz `Area` attribute + ring enforcement with toast, GateOpen Fx on portal level-ups.

## API
- `Build.run(): string`, `Build.plotFrame(i): CFrame` (kept), extras `Build.ringRadius(i): number` (wall radius in front of area i), `Build.gateAngle(n, count): number` (radians, same convention as plotFrame: direction = (sin a, 0, cos a)).
- `Plots.init()`, `Plots.start()`, `Plots.assign(player): Model?`, `Plots.plotOf(player): Model?`, `Plots.indexOf(plot): number`, `Plots.ownerOf(plot): Player?`, `Plots.isInside(plot, pos, margin: number?): boolean`, `Plots.clampInside(plot, pos): Vector3`, `Plots.setWall(plot, on: boolean)`, `Plots.sendHome(player)`, `Plots.spot(plot, name): CFrame`, `Plots.setTier(plot, level: number)`, `Plots.setPortalState(plot, state, kind: string?)`.
- `Gates.init()`, `Gates.start()` (loops), `Gates.areaAt(pos): (Area?, "inner"|"outer"?)`, `Gates.canEnter(player, areaId): boolean`, `Gates.unlockedArea(player): Area`.

## Map layout (for Zones, Leaderboards, MapMonsters, Openings, Rift)
- `Workspace.Map`: `Hub` (HubGround, Courtyard, RiftSpot, RuneCircle (Neon parts "Rune"), Torches), `<AreaId>` per area (GroundOuter, GroundInner, `Props`; Ember also `Lava` (parts "Lava", "LavaBank", "LavaPool"); Frost `FrozenLake`; Void `Floating` (Prop_Island models + "Speck" parts, floating on purpose)), `Paths` (Path1..8, Lane1..4, Road1..4), `Boards`, `Gates`, `Walls.<AreaId>`, `MonsterSpawns` (parts "Spawn", attributes Area/Band/Monster), `Edge` (Rim, MapEdge).
- Gates: `Workspace.Map.Gates.Gate_<AreaId>_<n>` (Model, Atomic, pivot = road centre at the wall, -Z outward). Attributes `Area`, `PortalLevel`, `Style` ("rubble"|"ice"|"void"). Children: `PillarL`, `PillarR`, `Lintel`, `Label` (SurfaceGuis "Front" and "Back", each TextLabel "Text" = "Portal level X"), `Barrier` (invisible, CanCollide true, CanQuery false: the only blocker), style props: rubble = 9 parts "Chunk", ice = 3 parts "Pane", void = 1 part "Veil" (ForceField, has a PointLight). All props are anchored, CanCollide/CanQuery/CanTouch false: the client hides/animates them when it opens a gate.
- Boards: `Workspace.Map.Boards.Board_Wave` / `Board_Pot` (Part; SurfaceGui "Rows" on the Front face toward the courtyard centre; TextLabel "Title" + TextLabels "Row1".."Row10", default text `"<n>.  ---"`). Also "Post" and "Cap" parts in the same folder.
- Plots: `Workspace.Plots.PlotN` (Model, Atomic, WorldPivot = plot frame (-Z away from the courtyard)): `Platform`, `Floor`, `Portal` (Model; contains `Surface`, front faces the courtyard/player), markers `PlayerSpawn`, `ChestSpot`, `MonsterSpawn`, `PortalFront` (invisible 1-stud parts), `Banner` (SurfaceGui `Name` > TextLabel `Label`), `BannerPost`, two `Torch` models (Neon "Flame" + PointLight), `ClothPost`/`Cloth`/`ClothTrim`, `Walls` folder (Front/Back/Left/Right ForceField, Transparency 1, CanCollide false by default).
- Ground heights: each ground disc sits 0.05 above the next one out; hub top 0.40, roads/paths top 0.45, courtyard top 0.90 (with 4 areas). Lighting effects named `Atmosphere`, `Bloom`, `ColorCorrection`, `Sky` exist in Lighting after Build.

## Deviations from PLAN.md
- `Plots.isInside` takes an optional third argument `margin` (default 0 = platform edge).
- Plots also runs `ServerStorage.Build.run()` at server start when `Workspace.Plots` is missing (with a warning), so a place where Build was never run still plays.
- Gates enforcement trigger: "past the outer edge of the outermost unlocked area" is measured as past the ring wall in front of the first locked area (wall radius + 3 studs), so players can walk up to a locked gate and read it; they are put back at wall radius - 8, in front of the nearest gate of that ring.
- The gap between two areas counts as the inner area for the `Area` attribute (Logic.areaAt returns nil there).
- Gates fires `Fx GateOpen { area }` (via Notify.fx) when a `PortalLevel` Bus event crosses an area's portalLevel. **Nobody else should send GateOpen** (Economy's PortalUp can still carry `unlocked`).
- Plots listens to `Bus PortalLevel` and `PlayerData.onLoaded` to call `setTier` itself; Economy/DebugTools may also call `Plots.setTier` (no-op when the tier is unchanged).

## Needs from others
- PlayerData: `PlayerData.get(player).profile.portalLevel` and `PlayerData.onLoaded(fn(player))` (both exist).
- Notify: `Notify.toast(player, text, "warn")`, `Notify.fx(player, { k = "GateOpen", area = id })`.
- Economy / DebugTools: fire `Bus.fire("PortalLevel", player, level)` after every portal level change (Plots and Gates react to it).
- Openings: call `Plots.setWall(plot, true)` at crack and `false` at close/fall; re-find the surface with `plot.Portal:FindFirstChild("Surface", true)` (setTier replaces the Portal model); use `Plots.spot(plot, "MonsterSpawn"/"ChestSpot"/"PortalFront")`; Economy must refuse portal upgrades during an opening (setTier swaps the arch).
- Zones (client): gates live in `Workspace.Map.Gates`; for areas where `PortalLevel` attr >= gate's `PortalLevel` attribute, set `Barrier.CanCollide = false` locally and animate Chunk/Pane/Veil away; react to `Fx GateOpen`.
- Leaderboards: fill `Workspace.Map.Boards.Board_<Wave|Pot>.Rows.Row1..Row10` (`.Text`).
- MapMonsters: spawn parts are `Workspace.Map.MonsterSpawns.Spawn` with attributes Area/Band/Monster (unchanged from the grey test); none are inside lava, lakes, roads or gates.
- Monsters/Combat default down handler: `Plots.sendHome(player)`.

## Decisions
- Roads and gates at angles 67.5 deg + 90 deg x k (between plots 2-3, 4-5, 6-7, 8-1), clear of the boards at 22.5/202.5 deg. Road 12 studs wide, narrowing to a 5-stud lane between the plots (r < 150).
- Ring walls at the middle of each gap (340, 510, 680), 16 high, 4 thick, ~48-stud chord segments overlapping 0.3 at each end (same look). Rubble = Slate with uneven heights, ice = Glacier, void = dark purple Glass (0.15 transparent).
- Gate opening 16 wide, 19 high, 4-stud pillars, lintel with a sign sticking out 0.03 on both faces.
- Ground: one disc per band, outer band 12% darker than the inner; discs step 0.05 apart (outermost lowest). Hub = Config.HubLook.ground Slate.
- Rift rune circle: 24 gold Neon runes at Config.Map.riftRadius, 8 more at r = 7 on a dark 10-stud RiftSpot.
- Props per band: Ash 9 dead trees, 5 ruins, 7 rocks; Ember 2 lava arcs (Neon river 6 wide on a 10-wide CrackedLava bank, pools at the ends), 5 geysers, 6 black rocks; Frost one frozen lake (22 inner / 15 outer), 9 ice spikes, 4 ice rocks; Void 7 floating islands (18-52 studs up), 25 star specks, 6 shards. Seeded Random(1234), so every run builds the same map.
- Plot dressing: 2 torches beside the arch at x = +-24 (clear of the tier-5 spires), red cloth banners with a gold Neon trim on the back corners, PortalFront marker 7 studs in front of the arch.
- Portal: the template's front (-Z) is turned to face the courtyard (the player stands between the courtyard and the arch).
- Torches: Neon "Flame" + PointLight (range 16, brightness 1.4, no shadows), no Fire instances (phones). 8 courtyard torches beside the roads.
- Lighting: Technology Future and LightingStyle Realistic (each in pcall), Brightness 2, Bloom size 24 threshold 1.4, Sky with 3000 stars.
- Plots: lowest free plot index first; walls fade in 0.45 s to Transparency 0.3; non-owners inside are moved 6 studs outside the front edge, an owner outside is sent home.
- Gates: 4 Hz, toast at most every 4 s per player, put back 8 studs inside the wall, root 3.5 studs above the gate's ground point.
- Estimated part count about 1,300 (under the 2,500 target).

## Studio checks
- Run `require(game.ServerStorage.Build:Clone()).run()` in Edit mode, read the summary (part count), then `world_scan` on Workspace, `Map.Hub`, `Map.Ash/Ember/Frost/Void`, `Map.Gates`, `Plots`: flicker, hairline gaps, loose, touchesNothing (the `Floating` folders and gate signs are intended).
- Pictures of a plot, the courtyard + boards, each gate from both sides (label readable both ways), each band, lava arcs, lakes, islands.
- Portal growth: DebugTools portal 1/5/10/15/20 on a plot: arch swaps in place, faces the player, clears the torches, chest spot and spawn.
- Walk into a locked gate (blocked by Barrier), then teleport past it (debug): put back in front of the gate with the toast; `Area` attribute changes Hub -> Ash -> ... while walking out.
- Opening walls fade in/out, block a second player, push a second player out.
- First spawn lands on PlayerSpawn facing the portal; reset respawns at home.
- Lighting.LightingStyle exists or is skipped silently; StreamingEnabled is on; plots/gates stream as whole models on a phone.

## Assets/anim/sound hooks
- Props (replace grey parts by name; `ReplicatedStorage.Assets.Props.<Name>` or `ServerStorage.Assets.Props.<Name>`, Model, pivot at the bottom centre on the ground, front -Z; Build anchors and locks every part): `Prop_DeadTree` (~10 studs tall), `Prop_Ruin` (~10x7), `Prop_Rock`, `Prop_Geyser` (keep a part named `Geyser` at the vent for client effects), `Prop_IceSpike` (~12 tall), `Prop_Island` (pivot at the island top centre; it floats), `Prop_Shard`.
- Portal: `ReplicatedStorage.Assets.Portal.Tier1..Tier5` with a part named `Surface`; pivot at the bottom centre, front -Z (Build/Plots turn it to face the courtyard).
- Client effects keyed by name: parts named `Geyser` (Ember), `Lava`/`LavaPool`, `Flame` (torches), gate `Chunk`/`Pane`/`Veil`, `Rune` (courtyard Rift circle).
- No sounds or animations in these files.
