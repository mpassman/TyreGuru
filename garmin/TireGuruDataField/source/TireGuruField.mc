import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Shows tire status from the TyreGuru app on a ride screen.
// Every 3 seconds it switches between: front air, rear air, front sealant, rear sealant.
// Each reads like "Low - 24.0" or "OVERFILLED - 51.0" (air, PSI) or "OK - 55%" (sealant left).
// The numbers are the app's estimates, typed in by the rider. The field measures nothing.
class TireGuruField extends WatchUi.SimpleDataField {

    const STALE_DAYS = 3;
    const SEAL_LOW = 40.0;   // below this percent of the dose: Low (same as the app's refill trigger)
    const SEAL_OK = 70.0;    // below this: OK, above: Good

    function initialize() {
        SimpleDataField.initialize();
        label = "TYREGURU";
    }

    function compute(info) {
        var fAir = readFloat("frontPsi");
        var rAir = readFloat("rearPsi");
        var fTgt = readFloat("frontTgt");
        var rTgt = readFloat("rearTgt");
        var fSeal = readFloat("frontSeal");
        var rSeal = readFloat("rearSeal");

        if (fAir <= 0.0 && rAir <= 0.0 && fSeal <= 0.0 && rSeal <= 0.0) {
            label = "TYREGURU";
            return "set up";
        }

        // A trailing "!" means the numbers are old: check the app and update them.
        var mark = "";
        var age = ageDays(readFloat("updated").toNumber());
        if (age < 0 || age > STALE_DAYS) {
            mark = " !";
        }

        var mode = (Time.now().value() / 3) % 4;
        if (mode == 0) {
            label = "FRONT AIR";
            return airText(fAir, fTgt, readFloat("maxPsi")) + mark;
        } else if (mode == 1) {
            label = "REAR AIR";
            return airText(rAir, rTgt, readFloat("maxPsi")) + mark;
        } else if (mode == 2) {
            label = "FRONT SEALANT";
            return sealText(fSeal) + mark;
        }
        label = "REAR SEALANT";
        return sealText(rSeal) + mark;
    }

    // Same zones as the app. tol is 5% of target (at least 3 PSI).
    // Low: below target - tol.  OK: up to target - tol/2.  Good: up to target + tol.
    // High: above that.  Over: above the tire maximum (or target + 4 x tol when no maximum is set).
    function airText(est, tgt, maxPsi) {
        if (est <= 0.0) {
            return "--";
        }
        var word = "Good";
        if (tgt > 0.0) {
            var tol = 0.05 * tgt;
            if (tol < 3.0) {
                tol = 3.0;
            }
            var over = tgt + 4.0 * tol;
            if (maxPsi > 0.0) {
                over = maxPsi;
            }
            if (over < tgt + 1.5 * tol) {
                over = tgt + 1.5 * tol;
            }
            if (est > over) {
                word = "OVERFILLED";
            } else if (est > tgt + tol) {
                word = "High";
            } else if (est < tgt - tol) {
                word = "Low";
            } else if (est < tgt - 0.5 * tol) {
                word = "OK";
            }
        }
        return word + " - " + est.format("%.1f");
    }

    function sealText(pct) {
        if (pct <= 0.0) {
            return "--";
        }
        var word = "Good";
        if (pct < SEAL_LOW) {
            word = "Low";
        } else if (pct < SEAL_OK) {
            word = "OK";
        }
        return word + " - " + pct.format("%.0f") + "%";
    }

    function readFloat(id) {
        var v = null;
        try {
            v = Application.Properties.getValue(id);
        } catch (e) {
            v = null;
        }
        if (v == null) {
            return 0.0;
        }
        return v.toFloat();
    }

    // Days since the date typed as YYYYMMDD. Returns -1 when no date is set.
    function ageDays(ymd) {
        if (ymd <= 0) {
            return -1;
        }
        var then = Gregorian.moment({
            :year => ymd / 10000,
            :month => (ymd / 100) % 100,
            :day => ymd % 100,
            :hour => 12
        });
        return Time.now().subtract(then).value() / 86400;
    }
}
