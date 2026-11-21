# Changelog

## 1.2.3

- An error in Gripbar can no longer leave the game's own gamepad code blocked (targeting, resizing the top bar in combat): every handler the game runs in the middle of its code is guarded, and the error is reported a moment later.
- Game action macros (Back, Interact, Inspect, Jump, the bumper shortcuts) on a paddle or a crossbar slot no longer get swallowed while that face button's own cell holds an action.
- A watchdog (once a second, out of combat) takes the face buttons back when the game binds its own again without a window closing, and puts the safety wrap back on the game's buttons if it was taken off.
- The game's "swap D-pad and face buttons" setting of the targeting bars: own cells stay on the face buttons.
- No false "cell changed by itself" for an item whose name loads late or a renamed macro.
- The mouse area over the bumper cells is put right after a fight that also changed bindings; a rare swallowed button release fixed.
- Debug log: a longer timeline (3000 lines), less noise.
- Debug log: notes when the triggers held, the bar the game focuses and the bars drawn enlarged (the game's and Gripbar's) disagree.
- Own X / Y / B / A is **off by default** for new installs (turn it on in the settings, Combat, or with `/grip face`); a setting already saved stays as it is.
- Fixed a Lua error from the debug log when a bumper release picked a target ("secret string value"): values the game keeps secret are no longer compared.

## 1.2.2

- Game action macros in cells (Back, Interact, Inspect, Jump) no longer get swallowed when the same face button's top cell holds an action (Back on a bumper cell sometimes did nothing).
- Safety net for own X / Y / B / A: at the start of each fight the face buttons are checked and bound again if the game took them; a warning in chat if that fails.
- A cell that changes without you (the game placing a newly learned spell, a talent reset, another addon) is reported in chat.
- A self-test after login reports in chat when a game update changed the crossbar parts Gripbar relies on.
- Debug log: each time a face button is won back from the game, presses on the bumper layers, bumper bars shown / hidden and target changes around them.

## 1.2.1

- Own X / Y / B / A in combat: a loot, group loot (Need / Greed) or bags window opening mid-fight no longer hands the face buttons back to the game for the rest of the fight (X hitting with the weapon instead of the spell). The keys are won back from secure code on the next press.
- A face button goes to a game window only while that window really binds it.

## 1.2.0

- **Russian interface:** settings, chat messages, `/grip` help, the game actions window, the setup guide and tooltips follow the client's language (ruRU translated; English otherwise).
- Own X / Y / B / A is **on by default** (a face button whose cells hold nothing stays the game's).
- An empty cell's tooltip names the game's own function there (Interact, Back, Target self, Bags...).
- Bumper bars: the mouse reaches the bumper cells and lands on the button the game shows (drops, swaps, Shift-drags).
- The mini cell is not drawn when it holds the same action as the button.
- Game action pictures: Interact (it drew black), Back on a taxi, pictures of hidden buttons while a bumper is held.
- `/grip paddle` lists the paddles again.

## 1.1.2

- Debug log: errors and blocked actions kept apart from the timeline, one record per problem with a count, so nothing pushes them out; repeated lines collapsed; the last 20 sessions (`/grip debug status`).
- The icon's round cut sits a little under the ring on every size (5 %): no gap between the ring and the icon.
- Removed the **Cells shown** setting: the enemy cell is set up on its small corner cell, the bumper cells with the bumper held (`/grip face edit` stays as a command; it no longer survives a reload).

## 1.1.1

- The mini cells' round cut, dark disc and cooldown swipe sit inside the ring in proportion to the cell size (no see-through gap between the ring and the icon).

## 1.1.0

- **Own X / Y / B / A on the top bar.** The top bar's face buttons and the bumper bars take actions of your own, drawn like the game's buttons. Five cells per face button: normal; living enemy targeted (shown small in the button's corner and swapped in when an enemy is targeted); LB held; RB held; LB + RB held. Empty cells and LT / RT + a face button stay the game's. Set them up without a target or a bumper with **Cells shown** (`/grip face edit`), empty one with `/grip face clear`.
- **Game actions** (`/grip actions`): the game's Interact, Inspect, Back, Jump and the bumper bars' shortcuts as macros for any slot, drawn with the game's live picture; targeting, combat and pet commands; windows (bags, map, quest log, character, spellbook) opened through the game's own buttons.
- **Debug log** (`/grip debug`): Lua errors, blocked actions and Gripbar messages kept in SavedVariables, for bug reports.
- All round icon cuts clip cleanly (no strips past the ring).
- Removed: swap melee and wand (put Shoot or any spell on X's enemy cell instead).

## 1.0.0

First release of Gripbar, a fork of SNRN Backhand 0.9.1.

- Slots placed around each crossbar bar (two by the d-pad, two by the face buttons) instead of a 2 x 2 grid; separate horizontal / vertical spread for the top and bottom rows.
- The focused bar's slots grow from the bar centre like the native ones; the HUD scale resizes each slot in place; stack and charge numbers scale with the slot.
- Slots fade together with the native bars (for example while a bumper is held).
- Paddle slots follow the native crossbar page: 16 actions per page, switched in combat.
- Controller profiles with engraved glyphs in the native style: Steam Controller / Steam Deck, Xbox Elite / Scuf, DualSense Edge, Razer, Generic.
- Swap melee and wand: X shoots the wand, RB + X swings, on every client language.
- Page binds: keys that fire page 2 / 3 slots without switching pages.
- Offsets for the native LT, RT and LT + RT badges.
- Settings reorganized in two columns; Edit Mode dragging removed (positions come from the spread settings).
