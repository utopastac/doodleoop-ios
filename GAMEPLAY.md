# Doodleoop gameplay

## Pitch

A pictorial Chinese whispers / Telestrations-style party game. One shared category starts every pad. Players draw, pass left, guess, pass left, draw again — until every person has contributed to every pad. Then reveal the mangled chains.

## Setup

1. Create or join a local lobby (Multipeer)
2. Optional: **Add seat** on any phone for pass-and-play
3. Host can open **Game settings** to set drawing / guessing timers (defaults **60s** / **30s**)
4. Host enters a **category** and starts when there are at least 2 players

## Round

| Turn parity | Action | Timer |
|-------------|--------|-------|
| Even (`0, 2, …`) | Draw from the prompt in front of you (category or last guess) | Draw limit (default 60s) |
| Odd (`1, 3, …`) | Guess what the drawing in front of you depicts | Guess limit (default 30s) |

After everyone submits — or the turn timer expires — each pad moves one seat to the left.

The round ends when `turnIndex == playerCount` (each pad has one contribution from each seat). Host advances through pad reveals, then returns to lobby for another category.

## Win condition

None — the point is the reveal.
