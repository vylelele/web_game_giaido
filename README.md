# VỌNG ÂM — Chapter 01: Tháp Đồng Hồ (V4.1 hotfix)

A browser-based cooperative mystery / escape-room game for **exactly two players**. This release focuses on a playable first chapter and includes a frontend/backend version check so older Supabase functions cannot silently produce a blank answer area: an illustrated room with interactive objects, eight sequential logic mechanisms, private clues for both roles, a shared inventory and journal, and a server-validated final lock.

## What is in this release

- `public/index.html` — game UI, scene, object inspection, distinct puzzle interactions, clue panels and progress display.
- `supabase/supabase.sql` — room schema and server-side RPCs. This file is outside the deployed `public/` directory so answer checks are not published as a static download.
- `public/config.js` — optional public Supabase config. Blank by default.
- `vercel.json` — static hosting settings; no build step is required.
- `validate.mjs` — static validation for JavaScript syntax, puzzle/RPC coverage and important security boundaries.

## Chapter flow

The chapter has eight sequential mechanisms and one combined lock: (1) order five relics, (2) extrapolate a number sequence, (3) solve a second odd-difference sequence, (4) navigate a coordinate grid, (5) use truth-counting to identify a locked box, (6) decode a Caesar cipher, (7) calculate a three-gear transmission, (8) translate four book-index numbers into letters, and (9) combine collected results in a four-wheel lock.

Players alternate the active role. The inactive player receives a complementary observation intended to be discussed out loud. The browser polls the room state so that room progress, inventory and journal updates appear on both devices.

## Run locally

For the UI shell only, serve the `public/` folder through a local static server rather than `file://`, because the Supabase SDK and `config.js` are loaded as browser scripts. For example:

```bash
python -m http.server 8080 --directory public
```

Then open `http://localhost:8080`. A real online room will not work until Supabase is configured.

## Configure Supabase for online play

1. Create a Supabase project.
2. Open **SQL Editor** and run the complete `supabase/supabase.sql` file.
3. In `public/config.js`, enter the project's URL and its public **publishable/anon** key, or use the in-game configuration form on each browser.
4. Never put a `service_role` key or any other privileged secret in browser code.
5. Deploy this folder as a static Vercel project; `vercel.json` publishes only `public/` and keeps server SQL outside the web output. Framework preset: **Other**; build command: none; output directory: `public` (matching `vercel.json`). Do not override the output directory to `.`; that could publish backend SQL files.
6. Open the deployed site on device one, create a room, then open the same URL on device two and join using the six-character code.

If a puzzle displays its title/clue but no answer controls and the status says **CẦN CẬP NHẬT BACKEND**, the frontend and Supabase RPC are from different versions. Run the complete current `supabase/supabase.sql` again in SQL Editor, refresh the site, leave the old room, and create a new room. Do not reuse an old room after changing the SQL.

If using an existing V3 database, make a backup first and do not expect old active rooms to continue in the V4 campaign. A fresh test Supabase project is the cleanest first deployment.

## Validation and test status

Run:

```bash
node validate.mjs
```

The validation checks the inline JavaScript syntax, presence of all eight sequential server answer checks, final-lock RPC wiring, room-table access restrictions, unique solution of the relic-order constraints, and that known answer keys are not embedded in the production HTML.

The offline preview package was also exercised in a local headless browser through the eight interactive puzzle mechanisms and the final lock. **A live Supabase two-device integration test has not been run**, because it requires a real project URL/key and running the SQL in that project. The project has not been deployed to Vercel from this environment.

## Important production notes

This is a functional first chapter, not a security-audited commercial release. Before a public launch, add request rate limiting, cleanup/retention for expired room rows, monitoring, an SQL integration test against a real Supabase project, accessibility review, and additional narrative chapters. Room sessions expire after 24 hours. Direct browser access to `public.game_rooms` is revoked; the client uses the RPC functions granted at the end of `supabase.sql`.
