TyreGuru data field for the Garmin Edge 1050  (WRITTEN HERE, NOT COMPILED OR RUN)

What it does
- Adds a data field you can place on any Edge data screen.
- Every 3 seconds it switches between: FRONT AIR, REAR AIR, FRONT SEALANT, REAR SEALANT. Each shows a status and number, e.g. "Low - 24.0" (PSI) or "OK - 55%" (sealant left).
- Status rules match the TyreGuru app. Air: Low below target minus tolerance, OK just under target, Good up to target plus tolerance, High above that, OVERFILLED above the tire maximum. Tolerance is 5% of target, at least 3 PSI. Sealant: Low below 40%, OK below 70%, Good above that.
- A trailing "!" means the numbers are more than 3 days old, so check the TyreGuru app.
- The numbers are ESTIMATES that you copy from the TyreGuru app (Settings, Data, "Garmin Edge data field" card). The field does not measure anything and does not connect to the app by itself.

What you need
- A free Garmin developer account and the Connect IQ SDK (SDK Manager from developer.garmin.com/connect-iq).
- Visual Studio Code with the "Monkey C" extension (easiest), or the command line tools.
- Java (the SDK needs it).

Build and try it
1. In Visual Studio Code open this folder. Run "Monkey C: Generate a Developer Key" once if asked.
2. Run "Monkey C: Build for Device", choose edge1050. Or run in the simulator first ("Run without debugging"). If edge1050 is not in the list, update the SDK and device files in SDK Manager.
3. Command line alternative:
   monkeyc -d edge1050 -f monkey.jungle -o TireGuru.prg -y developer_key.der
4. Put it on your Edge: connect the Edge by USB, copy TireGuru.prg into the GARMIN/APPS folder, eject, and restart the Edge.
5. On the Edge add it to a data screen: Menu, Activity Profiles, your profile, Data Screens, choose a screen, add a data field, Connect IQ, TyreGuru.

Entering the numbers
- Settings for a sideloaded app may NOT show up in the Garmin Connect phone app. If they do not, use the project file instead: in the estimator open the Data tab, open "properties.xml block", copy it over resources/properties/properties.xml here, rebuild, and copy the new .prg to the Edge.
- If you upload the field to the Connect IQ developer dashboard as a beta, Garmin Connect can show the settings (TyreGuru, Settings) and you can type the numbers there. Beta apps are reported to be visible only to the developer account. This is from forum posts and may have changed.

Known unknowns
- Not compiled or tested on any device or the simulator.
- minApiLevel is set low (3.2.0) to be safe. If the compiler complains, set it to the level shown for edge1050 in the SDK.
- The launcher icon size may produce a warning. That is harmless.
- Changing the label while riding is allowed in the field code but untested. If the label does not update, tell me and I will use one fixed label.
- Some Edge screen slots are small. Long values may be cut off.
- Sideloading has been reported to fail on some Edge models and software versions.
