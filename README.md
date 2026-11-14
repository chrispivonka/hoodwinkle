# Hoodwinkle

A daily bluffing trivia game. Every day you get three strange-but-true facts with one word blanked out.

1. **Write a lie.** Fill the blank with something false but believable.
2. **Find the truth.** Pick the real answer from a lineup of lies written by other players.
3. **Fool people.** Every player who falls for your lie earns you points, all day long.

Finding the truth is worth 100 points. Each player your lie fools is worth 10. Writing the real answer by accident gets a bonus, and that answer is kept out of the lie pool.

## Status

Prototype. `index.html` is the whole game: plain HTML, CSS and JavaScript with no build step.

- **Shared lie pool:** works when the page runs as a claude.ai artifact, which provides a shared database. Opened anywhere else (GitHub Pages, a local file), the game falls back to single-player mode with pre-written decoy lies.
- **Question bank:** 15 facts, enough for 5 days, then it repeats.

## How lies are picked

Each player's lie goes into the pool for that question. When you reach the "find the truth" step you see the real answer plus four lies:

- up to two player lies that have fooled the most people relative to how often they've been shown,
- one new or rarely shown player lie, so fresh lies get a fair test,
- pre-written decoys to fill any empty slots (this covers day one, before there are players).

Your own lie appears in the list but can't be picked.

## Roadmap

- [ ] Move the shared pool to a real backend (Supabase or AWS) so the public site has multiplayer
- [ ] Server-side moderation: word filter plus an AI moderation check, and a report button
- [ ] Grow the question bank to at least a year of facts, each checked against a source
- [ ] "Your lie fooled N people" summary when you come back the next day
- [ ] Optional 30-second timer so players can't look answers up

## Content

Facts are written in our own words and link to a source (usually Wikipedia) so players can check them. Every new fact needs a source link before it goes in the bank.

Hoodwinkle is an original game. It isn't affiliated with or endorsed by the makers of Balderdash, Fibbage or any other bluffing game.

## License

Code is released under the [MIT License](LICENSE).
