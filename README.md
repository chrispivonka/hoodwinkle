# Hoodwinkle

A daily bluffing trivia game. Every day you get three strange-but-true facts with one word blanked out.

1. **Write a lie.** Fill the blank with something false but believable.
2. **Find the truth.** Pick the real answer from a lineup of lies written by other players.
3. **Fool people.** Every player who falls for your lie earns you points, all day long.

Finding the truth is worth 100 points. Each player your lie fools is worth 10. Writing the real answer by accident gets a bonus, and that answer is kept out of the lie pool.

## Status

Prototype. `index.html` is the whole game: plain HTML, CSS and JavaScript with no build step.

- **Shared lie pool:** on the public site the game talks to a small API backed by Postgres on Neon. When the page runs as a claude.ai artifact it uses the artifact's shared database instead. If neither is reachable, the game falls back to single-player mode with pre-written decoy lies.
- **Question bank:** 15 facts, enough for 5 days, then it repeats.

## Backend

```
browser ──HTTPS──▶ api/ (Neon Function) ──SQL over HTTPS──▶ Postgres (Neon)
```

- **`db/migrations/`** creates two tables (`hw_players`, `hw_plays`) and four database functions. Row-level security is on with no policies, and the tables are revoked from everyone, so the only way in is through the functions.
- **`hw_api` role:** the API connects as a role that can execute `hw_day`, `hw_submit_lie` and `hw_submit_pick` and nothing else. It can't read or write a table directly.
- **Players are anonymous.** The browser makes a random token and keeps it in `localStorage`. The database stores only its SHA-256 hash and hands back a public id.
- **Writes are validated in the database:** the day must be today (UTC, ±1 day), lies are 2–40 characters and pass a word filter, a lie can't be changed once written, and you can't pick your own lie.
- **`api/index.mjs`** has no dependencies. It allows only the origins listed in `ALLOWED_ORIGINS`, caps request bodies at 4 KB and limits each IP to 60 calls a minute.

The API reads two environment variables, set on the function and never committed:

| Variable | Value |
| --- | --- |
| `HW_DB_URL` | connection string for the `hw_api` role |
| `ALLOWED_ORIGINS` | comma-separated origins, e.g. `https://chrispivonka.github.io` |

To deploy, zip `api/index.mjs` and deploy it as a Neon Function on the project's branch, then put its URL in `API_URL` near the top of the script in `index.html`.

## How lies are picked

Each player's lie goes into the pool for that question. When you reach the "find the truth" step you see the real answer plus four lies:

- up to two player lies that have fooled the most people relative to how often they've been shown,
- one new or rarely shown player lie, so fresh lies get a fair test,
- pre-written decoys to fill any empty slots (this covers day one, before there are players).

Your own lie appears in the list but can't be picked.

## Roadmap

- [x] Move the shared pool to a real backend so the public site has multiplayer
- [ ] Server-side moderation: word filter plus an AI moderation check, and a report button
- [ ] Grow the question bank to at least a year of facts, each checked against a source
- [ ] "Your lie fooled N people" summary when you come back the next day
- [ ] Optional 30-second timer so players can't look answers up

## Content

Facts are written in our own words and link to a source (usually Wikipedia) so players can check them. Every new fact needs a source link before it goes in the bank.

Hoodwinkle is an original game. It isn't affiliated with or endorsed by the makers of Balderdash, Fibbage or any other bluffing game.

## License

Code is released under the [MIT License](LICENSE).
