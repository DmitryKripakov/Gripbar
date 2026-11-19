# Gripbar knowledge base

Pitfalls of WoW: Forever's gamepad UI and of addon code around it, learned while building Gripbar. Each entry: what happens, why, what to do. Read before touching the crossbar, bindings or secure code.

## Sources and tools

- **Blizzard UI source for Forever:** [Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever) (branch `forever`). Forever's game type is `camelot`: files under `Camelot/` and `[Game]` paths win; `Mainline` is the "family" fallback. Sparse checkout is enough:
  `git clone --depth 1 --filter=blob:none --sparse <repo>` then `git sparse-checkout set Interface/AddOns/Blizzard_GamepadActionBars ...`
- Key folders: `Blizzard_GamepadActionBars` (crossbar, styles, targeting bars), `Blizzard_GamepadSharedUtility/InputBindingStack` (how the game binds pad keys), `Blizzard_GamepadTargeting` (bumper tap-to-target), `Blizzard_RestrictedAddOnEnvironment` (what secure snippets may call), `Blizzard_FrameXML/Bindings_Camelot.xml` (what each key binding really calls).
- **Debug log** (`Debug.lua`, `/grip debug`): Lua errors of every addon, `ADDON_ACTION_BLOCKED` / `FORBIDDEN`, Gripbar messages and a `/grip diag` snapshot 5 s after login, in `WTF/Account/<account>/SavedVariables/Gripbar.lua` (`GripbarDebugLog`). Written only on `/reload` or logout; a client crash loses the session. When the game offers to disable an addon, press Ignore, then `/reload`.
- Lua syntax check outside the game: `luaparser` (`from luaparser import ast; ast.parse(text)`).
- A new file in the addon needs a full client restart; changed files need `/reload`. Check that a test session ran the code you think it did (the log's login time against the commit time).

## Taint (the big one)

- **Never create frames from the game's crossbar templates** (`GamepadActionBarButtonTemplate`, `ActionBarButtonTemplate`...). Their OnLoad registers the button in Blizzard's shared lists (`ActionBarButtonEventsFrame.frames`, `ActionBarActionEventsFrame.frames`, range / usable watchers). The game walks those lists in one loop; after our entry the rest of the loop is tainted, and in combat it is blocked from laying out its own bars (`ADDON_ACTION_BLOCKED` on `SetSize` / `SetPoint` / `SetShown` of `RightBar` buttons, targeting bars...). Draw our own art instead (`BuildSlotVisual` in `Buttons.lua`).
- **Do not write fields on Blizzard tables or frames** from addon code (taint spreads when secure code reads them). Keep per-frame data in our own weak tables (see `savedAlpha` in `TopFace.lua`).
- `hooksecurefunc` (post-hooks) and plain textures' `SetAlpha` / `SetAtlas` on Blizzard buttons are safe. Moving, sizing, showing or hiding a protected frame from addon code in combat is not.
- **`/run` in a macro is tainted on purpose** (`*** ForceTaint_Strong ***`). A window opened with `/run ToggleSpellBook()`... is tainted, and the game blocks closing it (and then `SetPreferredGamepadInteractTarget`). Open windows by clicking the game's own buttons: `/click SpellbookMicroButton`, `CharacterMicroButton`, `QuestLogMicroButton`, `MainMenuBarBackpackButton`.
- `ToggleSpellBook` does not exist in Forever; the binding calls `PlayerSpellsUtil.ToggleSpellBookFrame()`. Check `Bindings_Camelot.xml` before calling a UI function.

## Secure (restricted) code

- Snippets (`WrapScript`, state drivers, `SecureHandlerExecute`) **cannot create tables**: no `{ ... }`, no `ipairs({ ... })` ("Direct table creation is not permitted"). Unroll lists by hand.
- Available there: `GetGamePadState()` (insecure code does not have it: use `IsKeyDown` / `C_GamePad.GetDeviceMappedState`), `HasAction`, `GetActionInfo`, `IsControlKeyDown` & co, frame handles (`SetPoint`, `SetAlpha`, `GetFrameRef`, `CallMethod`, `IsVisible`). `control` is the header in a wrapped script.
- Insecure work from a snippet: `self:CallMethod("Name", ...)` runs a method of our frame insecurely (art updates in combat).
- Pass data into snippets as attributes; decide out of combat what can only be decided there.

## Bindings

- The game binds pad keys itself: `SetOverrideBindingClick(UIParent, true, "PAD3", "InputFunctionBindingButton_PAD3")` from its binding stack (`GamepadSharedUtility.InputBindingManager`). Menus push binding sets on top; `IsOnlyCoreBindingSetActive()` says when only the HUD set is active. Our priority overrides go on while only the core set is active and come off for menus (hooks on `AddBindingSet` / `RemoveSet`...).
- `/click InputFunctionBindingButton_PADn` does **not** run the game's press; `/click <the game's button>` does (top bar `...TopBarActionButton5..8`, targeting bars' `faceLeftButton`..., trigger bars' face buttons). Send both edges: `LeftButton true` on press, `LeftButton` on release (jump keeps rising while held).
- Emulated modifiers differ per setup: here LT = Shift, LB = Ctrl, RT and RB none (`GamePadEmulateShift/Ctrl/Alt`). A modifier-emulating input may not show in the mapped pad state; check its modifier too. Inputs that are not modifiers arrive as the plain key: detect them in the snippet (RT + Y would otherwise fire our Y).
- Face key + trigger modifier: bind back to the game's `CLICK InputFunctionBindingButton_PADn:LeftButton`; with only bumper modifiers: ours.
- Holding both bumpers shows the shortcuts bar, and the game keeps it until **both** are released. Decide the layer from the bar the game shows (`bar:IsVisible()`), not from the buttons held.
- Releasing a bumper without using it targets the next enemy / friend (`GamepadTargetLogic`) unless something consumed it (a target change does).

## Action slots

- Gamepad action storage: `C_GamepadUI` slots (here 181-360). Pages 1-3 come from `GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID`; the top face buttons are reserved (action 0) and take no actions.
- **At `ADDON_LOADED` every slot looks empty**: the game has not loaded their contents yet. Choose free slots at `PLAYER_ENTERING_WORLD` or later, or you pick slots holding the player's old actions.
- Never clear a slot you did not create: it may hold the player's things. Drop it from our list instead.
- `C_ActionBar.EnableActionRangeCheck` on a storage slot no game button owns crashes the client: poll `IsActionInRange`.
- Dropping onto a frame: handle both `OnReceiveDrag` and a click with an action on the cursor (`PreClick`), and debounce: a release can fire both, and a second `PutActionInSlot` swaps the action back.

## Drawing like the game

- Read how the game draws a thing in its source and mirror it; read live values from the game's button rather than hard-coding them (picture, crop, offset, mask presence).
- The crossbar's button shape and size come from the bar's style, not the template: `buttonIndexOnActionBar` 1-4 squares, 5-8 circles; `SetShapeToCircle` after `UpdateButtonArt`; sizes 30 / 38 (circle), 32 / 40 (square); pushed = 4 smaller, 2 lower.
- The face glyph beside a button (`ButtonIcon`) belongs to the bar template, not the button.
- **Atlases can be sprite sheets:** the inspect crosshair needs `SetSpriteSheetCell(1, 1, 1)` after `SetAtlas`. Never `SetTexCoord(0, 1, 0, 1)` after an atlas.
- Textures keep the game's crop (`GetTexCoord`): raid markers are cells of one sheet.
- Game pictures change with state: with a bumper held the inspect button shows a raid marker, offset 6 inside. Show the state the action will actually use.
- **Masks:** an atlas mask repeats its edge pixels outward; a circle touches its square at four points, so a picture larger than the mask shows four strips past the ring. Use `TempPortraitAlphaMask` with `CLAMPTOBLACKADDITIVE`.
- The game's buttons hold pictures its bars put there (targeting overlay with ticks, portraits, markers). To cover a game button, hide **all** its textures (`GetRegions`) except the shadows, and give each back its own saved alpha (some are transparent on purpose).
- Our frames live in the crossbar's strata (`HIGH` draws over the map), at a higher level.
- A frame anchored to a game button follows its size, collapse / expand and pressed motion for free; ours moving alone must move its companions (the mini cell) the same way.

## Releases

- `.pkgmeta` leaves `docs`, `tools` and dotfiles out of the zip. A `v*` tag builds the GitHub release (BigWigs packager); CurseForge uploads are manual until the webhook or `CF_API_KEY` route is set up (one of them, not both).
- Back up before big changes (Desktop `Gripbar_<date>_<name>` + zip).
