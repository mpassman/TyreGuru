# TyreGuru AI review service

A small Cloudflare Worker that lets the app's "Ask the AI to review" button work outside Claude.
The app sends the review text; the Worker adds your Anthropic key (stored only in Cloudflare) and returns the answer.

**Until you add a key it does nothing.** The app shows "The AI review service is not switched on yet" and the red and green advice keeps working.

## Turn it on later (about 10 minutes)

1. Make a free Cloudflare account and an Anthropic API key at console.anthropic.com.
2. In Anthropic's console set a monthly spending limit (for example $5). This is your hard stop.
3. In this folder run:
   - `npx wrangler deploy`
   - `npx wrangler secret put ANTHROPIC_API_KEY` and paste the key
   - optional: `npx wrangler secret put APP_CODE` and choose an access code
4. Wrangler prints an address like `https://tyreguru-ai.YOURNAME.workers.dev`.
5. In the app: Data, "AI review service", paste that address (and the access code if you set one). Tap Test.

Or skip the command line: in the Cloudflare dashboard create a Worker, paste `worker.js`, add the secrets under Settings, Variables.

## Safeguards built in
- Key lives only in Cloudflare secrets, never in the app or this repo.
- Only TyreGuru review prompts are accepted (checked signature, 12,000 character cap, 500 token answer cap).
- Per-address and total daily limits (`PER_IP_DAILY`, `DAILY_LIMIT`); bind a KV namespace for limits that survive restarts.
- Optional access code (`APP_CODE`). It is a gate against strangers, not strong security, because it is stored in the app.
- The app never sends Strava or other connected-service data to the review.

## Check it
`GET /health` returns `{"ok":true,"configured":false}` until the key is set.
