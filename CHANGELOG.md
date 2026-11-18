# Changelog

## Unreleased

- Own X / Y / B / A on the top bar: the top bar's face buttons and the LB / RB targeting bars take actions of your own. Four cells per face button: normal, living enemy targeted, LB held, RB held; empty cells and LT / RT + a face button stay the game's (`/grip face`, `/grip face edit`).
- Debug log: Lua errors, blocked actions and Gripbar messages kept in SavedVariables (`/grip debug`).
- Game actions: the top bar's Interact, Inspect, Back and Jump as macros to put on any slot, with the game's live icon (`/grip actions`).
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
