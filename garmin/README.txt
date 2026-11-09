TyreGuru ride screen for Garmin Edge 1050 (Connect IQ data field)

WHAT IT SHOWS
Pump-style dials for front and rear tire, air and sealant, with the same zones and colors as the phone app
(red low, yellow OK, green good, purple high, red overfilled with "Release air").
  - One-field full screen (or tall field): 2 x 2 dials, front on top, rear below.
  - Wide, short field: 4 dials in a row.
  - Very small field: one line of text.
A "!" notice appears when the numbers are more than 3 days old.

ALERTS ON THE EDGE (new)
  - Danger alarm: one alarm tone and a long double buzz when a dial turns red (air more than 20% below target
    or over the tire maximum, or sealant under 40% of a full dose). It sounds ONCE and does not repeat. If a
    different problem appears later, that one sounds once as well.
  - Optimal chirp: one short high tone when both tires turn green (air in the green zone, sealant at 90% or more).
  - Settings: sound and vibration, vibration only, or silent; danger alarm on/off; chirp on/off.
  - Set "Where alerts sound" in the TyreGuru phone app to "Bike computer" so the phone stays quiet and the two
    do not sound at the same time.
  - A data field has no button, so it cannot be acknowledged; that is why it sounds once.
  - Not yet compiled or tried on an Edge. The tones depend on the Edge's sound settings.

HOW TO ENTER THE NUMBERS
In Garmin Connect (phone app): Connect IQ > My Data Fields > TyreGuru > Settings.
Type the front and rear air (PSI, one decimal), target, tire maximum, sealant left (%), the date (YYYYMMDD),
and optionally turn on color-blind colors. The TyreGuru app's Garmin card shows the exact numbers to type.
NOTE: settings only appear in Garmin Connect for fields installed through the Connect IQ store
(a private or beta listing works). A field copied to the Edge by cable has no settings screen on the phone.

BUILD
VS Code with the Monkey C extension: Monkey C: Build for Device > edge1050, then copy bin/TireGuruDataField.prg
to the Edge's GARMIN/APPS folder.
