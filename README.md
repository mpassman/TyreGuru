# TyreGuru

Tubeless sealant and tire-pressure estimator.

- `app/index.html` – the web app (wrapped in a WKWebView for iPhone)
- `sealants.json` – sealant list with recommended doses by tire type and width. The app can fetch this file so new sealants arrive without an app update. Each entry records its source; entries marked `secondary` or with no source are unverified.
- `garmin/` – Connect IQ data field source for Garmin Edge

Doses are starting points from maker charts. Follow your sealant label.
