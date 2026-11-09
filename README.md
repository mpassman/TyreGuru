# TyreGuru

Tubeless sealant and tire-pressure estimator.

- `app/index.html` – the web app (wrapped in a WKWebView for iPhone)
- `sealants.json` – sealant list with recommended doses by tire type and width. The app can fetch this file so new sealants arrive without an app update. Each entry records its source; entries marked `secondary` or with no source are unverified.
- `tires.json` – maximum tire pressures by brand, model and width. The app fetches it like `sealants.json`, so new tires arrive without an app update.
- `ai-proxy/` – small Cloudflare Worker: the AI review button and the new-product submissions. Does nothing until keys are added (see its README).
- `scripts/research.mjs` and `.github/workflows/research-products.yml` – the research job (below).
- `garmin/` – Connect IQ data field source for Garmin Edge

Doses are starting points from maker charts. Follow your sealant label.

## How new tires and sealants get added

1. A rider types a tire or sealant that is not listed and taps **Not listed? Add it**. It is added to their own list at once.
2. If they allow it (Data tab) and the service is set up, the app sends only the brand, model and printed width (or the sealant name). The service files a GitHub issue labelled `new-product`.
3. The research job (GitHub Action) reads those issues, asks Claude with web search for the maker's maximum and recommended pressure (tires) or recommended sealant amounts by width (sealants), checks the answer strictly (ranges, https source link), and opens a **pull request** listing each source. Nothing is merged automatically.
4. You check the sources and merge. The app picks up the new lists the next time it opens. Products it could not find reliable figures for get the `research-failed` label and a comment, and are not added.

The job also runs by hand from the Actions tab (Run workflow). It is switched off until you add the repository secret `ANTHROPIC_API_KEY` (Settings, Secrets and variables, Actions) and tick "Allow GitHub Actions to create and approve pull requests" (Settings, Actions, General). Test it offline with `node scripts/research.test.mjs`.
