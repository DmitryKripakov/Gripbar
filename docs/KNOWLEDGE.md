# Gripbar knowledge base

Pitfalls of WoW: Forever's gamepad UI and of addon code around it, learned while building Gripbar. Each entry: what happens, why, what to do. Read before touching the crossbar, bindings or secure code.

## Sources and tools

- **Blizzard UI source for Forever:** [Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever) (branch `forever`). Forever's game type is `camelot`: files under `Camelot/` and `[Game]` paths win; `Mainline` is the "family" fallback. Sparse checkout is enough:
  `git clone --depth 1 --filter=blob:none --sparse <repo>` then `git sparse-checkout set Interface/AddOns/Blizzard_GamepadActionBars ...`
- Key folders: `Blizzard_GamepadActionBars` (crossbar, styles, targeting bars), `Blizzard_GamepadSharedUtility/InputBindingStack` (how the game binds pad keys), `Blizzard_GamepadTargeting` (bumper tap-to-target), `Blizzard_RestrictedAddOnEnvironment` (what secure snippets may call), `Blizzard_FrameXML/Bindings_Camelot.xml` (what each key binding really calls).
- **Debug log** (`Debug.lua`, `/grip debug`, `/grip debug status`): in `WTF/Account/<account>/SavedVariables/Gripbar.lua` (`GripbarDebugLog`): `problems` (Lua errors of every addon, `ADDON_ACTION_BLOCKED` / `FORBIDDEN`, warnings; one record per distinct problem with count, first / last time, sessions, stack; never pushed out by chatter), `lines` (a timeline, 800 lines, repeats collapsed into "(xN)") and `sessions` (the last 20 logins). Read it with `python tools/readlog.py`. Written only on `/reload` or logout; a client crash loses the session. When the game offers to disable an addon, press Ignore, then `/reload`.
- Never log from code that runs on every redraw or event: the log keeps 800 lines and per-redraw lines push the real errors out within seconds. Log changes and failures only.
- Lua syntax check outside the game: `luaparser` (`from luaparser import ast; ast.parse(text)`).
- A new file in the addon needs a full client restart; changed files need `/reload`. Check that a test session ran the code you think it did (the log's login time against the commit time).

## Taint (the big one)

- **Never create frames from the game's crossbar templates** (`GamepadActionBarButtonTemplate`, `ActionBarButtonTemplate`...). Their OnLoad registers the button in Blizzard's shared lists (`ActionBarButtonEventsFrame.frames`, `ActionBarActionEventsFrame.frames`, range / usable watchers). The game walks those lists in one loop; after our entry the rest of the loop is tainted, and in combat it is blocked from laying out its own bars (`ADDON_ACTION_BLOCKED` on `SetSize` / `SetPoint` / `SetShown` of `RightBar` buttons, targeting bars...). Draw our own art instead (`BuildSlotVisual` in `Buttons.lua`).
- **Do not write fields on Blizzard tables or frames** from addon code (taint spreads when secure code reads them). Keep per-frame data in our own weak tables (see `savedAlpha` in `TopFace.lua`).
- `hooksecurefunc` (post-hooks) and plain textures' `SetAlpha` / `SetAtlas` on Blizzard buttons are safe. Moving, sizing, showing or hiding a protected frame from addon code in combat is not.
- **`/run` in a macro is tainted on purpose** (`*** ForceTaint_Strong ***`). A window opened with `/run ToggleSpellBook()`... is tainted, and the game blocks closing it (and then `SetPreferredGamepadInteractTarget`). Open windows by clicking the game's own buttons: `/click SpellbookMicroButton`, `CharacterMicroButton`, `QuestLogMicroButton`, `MainMenuBarBackpackButton`.
- `ToggleSpellBook` does not exist in Forever; the binding calls `PlayerSpellsUtil.ToggleSpellBookFrame()`. Check `Bindings_Camelot.xml` before calling a UI function.

## Secret values

- The client hands addon code **secret values** in some places: `UnitName("target")` read in a `PLAYER_TARGET_CHANGED` handler that the game fires from inside its own targeting (`TargetNearestEnemy` on a bumper release). Comparing one (`==`), testing it, or using it as a table key errors ("attempt to compare ... a secret string value"); concatenating one makes the whole string secret. Check with `issecretvalue(v)` first; the debug log turns secrets into "(secret value)" (`ns.Plain`).

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
- The game's own windows push binding sets that take the face keys (`LootFrameFooter`, `GroupLootFrameFooter` for need / greed rolls, `ContainerFrameCombinedBagsFooter` for bags, with `SmartNavigation*` / `FrameControlsManager*`), also in combat; when they close the game binds its core face keys again and they win over ours. Release a key only while a set on the stack binds it (`set:GetBinding(key)`), and win it back from secure code: pad presses reach the crossbar through `PressActionButton` -> `actionButton:Click()`, so a `WrapScript` on the game's face buttons' OnClick sees every press that went the game's way and can `control:SetBindingClick` ours back (and drop that press).
- Holding both bumpers shows the shortcuts bar, and the game keeps it until **both** are released. Decide the layer from the bar the game shows (`bar:IsVisible()`), not from the buttons held.
- Releasing a bumper without using it targets the next enemy / friend (`GamepadTargetLogic`) unless something consumed it (a target change does).
- The game's bumper-bar buttons consume it in their OnClick (`GamepadTargetLogic:ConsumeModifier()`); our cells cannot (addon code writing `wasModifierUsed` would taint `GamepadTargetLogic`, whose `EndTargeting` / `BeginTargeting` run the game's targeting). While a bumper is held the game's own targeting is on (`C_GamepadTargeting.Enable()`; `Disable()` on release reports whether it picked a target). Watch a bumper cell that does not change the target, and Back on a bumper cell (open: the target comes back).
- Other game windows that take face keys (from the source): spell flyouts (`SpellFlyoutFrameFooter`: A cast, X bind), party / raid targeting (`SmartNavigation`), raid marker D-pad, ready check, role poll, stack split, equipment flyout, static popups.

## Safety net (TopFace.lua)

- The reclaim wrap tells the game's binding from a macro's `/click` on the same button by the pad state: the binding fires while the face key is down (`GetGamePadState().buttons[index]`, index written out of combat as `pad-<face>`); with the key up it is a macro on a paddle or a crossbar slot and is left alone (no drop, **no rebind**: a game window may hold the key). Logged as "click on the game's X with the key up". If a real stolen press ever logs that, the pad state lags the binding: rethink.
- `WrapScript` replaces the button's OnClick; the game's `SetScript("OnClick", ...)` takes the wrap off again. The targeting bars do that in `SetUpActionButtons` (at load, and whenever their "swap D-pad and face buttons" CVar changes). Keep the wrapped handler (`GetScript` after wrapping), compare, wrap again out of combat.
- With that swap on, the bars' `faceLeftButton`... fields point at the **D-pad side's** buttons (they follow the action); a press of X still reaches `bar.Right.ActionButton1`. Address the game's buttons by position, never by those fields.
- Not hooked: `InputUtil.RegisterGamepadInit` -> `coreSet:BindAll()` (keyboard and mouse back to gamepad) binds the game's core keys with no stack change. A 1 s out-of-combat watchdog (`GetBindingAction(key, true)` against our `CLICK GripbarFaceX:LeftButton`, the wraps, a left-over `gb-busy`) puts things right; it backs off for a minute after 3 failed tries.
- `PLAYER_REGEN_DISABLED` fires before the lockdown: check `GetBindingAction(key, true)` is our `CLICK GripbarFaceX:LeftButton` and bind again right there; tell the player only if that fails.
- The reclaim wrap reports each win back through `control:CallMethod("GBReclaimed", ...)` on our own header (an insecure method called from secure code is fine; it only logs). Clicks made from inside a press of ours are not the game's: our relays to its buttons, and **game-action macros in our cells** (`/click` on the top bar's Back / Interact / Inspect / Jump). PRECLICK sets `gb-busy` and returns `nil, message`, so the wrap's post body runs after the press and clears it. Without this the wrap dropped Back on a bumper cell whenever B's current top cell held an action.
- Cell contents are watched by kind + **name** (a macro's index shifts when macros are added; a spell's ID changes with a new rank). A change within 2 s of a mouse drop / pickup / `/grip face clear`, or with something on the cursor, is the player's; any other is logged and told in chat (a newly learned spell placed by the game, a talent reset, another addon).
- 5 s after the first `PLAYER_ENTERING_WORLD`: a self-test of the game parts we lean on (`InputBindingManager` and its stack, `PressActionButton`, the face buttons of every layer); a patch that renames them shows in chat instead of failing silently.

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
- Textures keep the game's crop: `GetTexCoord()` returns **eight** numbers (four corners), pass them all back with `SetTexCoord(unpack(c))`; taking four as left / right / top / bottom gives a zero-width picture. Raid markers are cells of one sheet. The game gives some pictures by file ID (a number): never turn it into a string path.
- Game pictures change with state: with a bumper held the inspect button shows a raid marker, offset 6 inside. Show the state the action will actually use.
- **Masks:** an atlas mask repeats its edge pixels outward; a circle touches its square at four points, so a picture larger than the mask shows four strips past the ring. Use `TempPortraitAlphaMask` with `CLAMPTOBLACKADDITIVE`.
- The game's buttons hold pictures its bars put there (targeting overlay with ticks, portraits, markers). To cover a game button, hide **all** its textures (`GetRegions`) except the shadows, and give each back its own saved alpha (some are transparent on purpose).
- Our frames live in the crossbar's strata (`HIGH` draws over the map), at a higher level.
- A frame anchored to a game button follows its size, collapse / expand and pressed motion for free; ours moving alone must move its companions (the mini cell) the same way.

## Releases

- `.pkgmeta` leaves `docs`, `tools` and dotfiles out of the zip. A `v*` tag builds the GitHub release (BigWigs packager); CurseForge uploads are manual until the webhook or `CF_API_KEY` route is set up (one of them, not both).
- Back up before big changes (Desktop `Gripbar_<date>_<name>` + zip).
