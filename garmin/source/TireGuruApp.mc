import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

class TireGuruApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // numbers sent by the TyreGuru phone app (auto sync); the typed settings still work without it
        try {
            Communications.registerForPhoneAppMessages(method(:onPhone));
        } catch (ex) {
            // phone messaging not available on this device or software: ignore
        }
    }

    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        var d = msg.data;
        if (d instanceof Lang.Dictionary) {
            var keys = d.keys();
            for (var i = 0; i < keys.size(); i++) {
                Application.Storage.setValue(keys[i], d[keys[i]]);
            }
            WatchUi.requestUpdate();
        }
    }

    function getInitialView() {
        return [ new TireGuruField() ];
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}
