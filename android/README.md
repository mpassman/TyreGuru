# TyreGuru for Android

A WebView app that loads the same `index.html` as the iPhone app (copy in `app/src/main/assets/`; refresh it from `../app/index.html` after any change).
`Bridge.kt` answers the page's native requests the way `WebContainer.swift` does on iPhone:

| Page message | Android |
|---|---|
| store | saves the app data to a file |
| geo | one approximate location fix |
| http | web requests to Strava, Intervals.icu, Withings, WHOOP |
| alerts | alarm sounds, vibration, sealant-check reminders |
| tyrewiz | Bluetooth LE discovery and pairing (`TyreWizBle.kt`), kept alive by a foreground service |
| garmin, health | not built yet: the page is told so |

**Not compiled or run by the author.** Nobody has an Android phone to test on. Open the `android` folder in Android Studio, let it sync, and fix whatever it flags before trusting any of it.
Known gaps: no Garmin Connect IQ sending, no Health Connect, TyreWiz pressure decoding is the same unfinished step as on iPhone, and the app has no icon yet.
