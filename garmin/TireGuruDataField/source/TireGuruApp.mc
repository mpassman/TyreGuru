import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TireGuruApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new TireGuruField() ];
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}
