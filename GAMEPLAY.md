# Doodleoop gameplay

## Pitch

A pictorial Chinese whispers / Telestrations-style party game. One shared category starts every pad. Players draw, pass left, guess, pass left, draw again — until the pad has gone once around the table (the person who started it never draws on it twice). Then reveal the mangled chains.

## Setup

1. Create or join a local lobby (Multipeer)
2. Optional: **Add seat** on any phone for pass-and-play
3. Host can open **Game settings** to set drawing / guessing timers (defaults **60s** / **30s**)
4. Host enters a **category** and starts when there are at least 3 players

## Round

| Turn parity | Action | Timer |
|-------------|--------|-------|
| Even (`0, 2, …`) | Draw from the prompt in front of you (category or last guess) | Draw limit (default 60s) |
| Odd (`1, 3, …`) | Guess what the drawing in front of you depicts | Guess limit (default 30s) |

After everyone submits — or the turn timer expires — each pad moves one seat to the left.

Turns alternate draw → guess → draw → … for one lap around the table, so the starter never draws on their own pad again (3 players: draw → guess → draw). The lobby **draw cap** (default 8) only shortens that on large tables.

Reveal walks each pad’s journey one step at a time (drawing → guess → …), synced on every phone; after a pad finishes, the next player’s pad starts. Then return to lobby for another category.

## Win condition

None — the point is the reveal.
