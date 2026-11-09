import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// TyreGuru ride screen: pump-style dials for front and rear tire, air and sealant.
// Same zones and colors as the phone app. The numbers are typed in (Garmin Connect settings)
// from the TyreGuru app. The field measures nothing.
//   Full-screen or tall field: 2 x 2 dials (front row on top, rear row below).
//   Wide, short field: 4 dials in a row.
//   Very small field: one line of text.
class TireGuruField extends WatchUi.DataField {

    const STALE_DAYS = 3;
    const SEAL_LOW = 40.0;
    const SEAL_OK = 70.0;
    const SWEEP_START = -135.0;
    const SWEEP = 270.0;

    var fAir = 0.0;
    var rAir = 0.0;
    var fTgt = 0.0;
    var rTgt = 0.0;
    var fSeal = 0.0;
    var rSeal = 0.0;
    var maxPsi = 0.0;
    var stale = false;
    var cb = false;

    function initialize() {
        DataField.initialize();
    }

    function compute(info) {
        return null;
    }

    function readAll() {
        fAir = readFloat("frontPsi");
        rAir = readFloat("rearPsi");
        fTgt = readFloat("frontTgt");
        rTgt = readFloat("rearTgt");
        fSeal = readFloat("frontSeal");
        rSeal = readFloat("rearSeal");
        maxPsi = readFloat("maxPsi");
        cb = readFloat("cbMode") > 0.5;
        var age = ageDays(readFloat("updated").toNumber());
        stale = (age < 0 || age > STALE_DAYS);
    }

    // ---- colors: zone 0 low, 1 OK, 2 good, 3 high, 4 overfilled ----
    function zoneColor(z) {
        if (cb) {
            // color-blind safe palette
            if (z == 0 || z == 4) { return 0xE8742A; }
            if (z == 1) { return 0xF0E442; }
            if (z == 2) { return 0x3D9BE0; }
            return 0xCC79A7;
        }
        if (z == 0 || z == 4) { return 0xE5483B; }
        if (z == 1) { return 0xF2B21A; }
        if (z == 2) { return 0x22B14C; }
        return 0x9B5DE5;
    }

    function zoneWord(z) {
        if (z == 0) { return "Low"; }
        if (z == 1) { return "OK"; }
        if (z == 2) { return "Good"; }
        if (z == 3) { return "High"; }
        return "OVERFILLED";
    }

    // Air thresholds, same as the app. Returns [low, good0, good1, over, dialMax]
    // Good is target -10% to +5%. OK (yellow) is 10% to 20% below. Low is more than 20% below. High is above +5%.
    // Purple (high) is above green but still under the tire maximum. Overfilled is above the maximum (or target + 25% when no maximum is set).
    function airZones(tgt) {
        var g1 = tgt * 1.05;
        var over = tgt * 1.25;
        if (maxPsi > 0.0) {
            over = maxPsi;
            if (g1 > over) { g1 = over; }
        } else if (over < g1 + 2.0) {
            over = g1 + 2.0;
        }
        var dmax = 180.0;
        if (over <= 52.0) {
            dmax = 60.0;
        } else if (over <= 104.0) {
            dmax = 120.0;
        }
        return [tgt * 0.80, tgt * 0.90, g1, over, dmax];
    }

    function airZone(est, tgt) {
        if (tgt <= 0.0) { return 2; }
        var z = airZones(tgt);
        if (est > z[3]) { return 4; }
        if (est > z[2]) { return 3; }
        if (est < z[0]) { return 0; }
        if (est < z[1]) { return 1; }
        return 2;
    }

    function sealZone(pct) {
        if (pct < SEAL_LOW) { return 0; }
        if (pct < SEAL_OK) { return 1; }
        return 2;
    }

    // ---- drawing ----
    function onUpdate(dc) {
        readAll();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (fAir <= 0.0 && rAir <= 0.0 && fSeal <= 0.0 && rSeal <= 0.0) {
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "TYREGURU: set up in Garmin Connect", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        if (w < 150 || h < 90) {
            drawTextOnly(dc, w, h);
            return;
        }

        var cols = 4;
        var rows = 1;
        if (h * 4 >= w * 3) {
            cols = 2;
            rows = 2;
        }
        var cw = w / cols;
        var ch = h / rows;
        for (var i = 0; i < 4; i++) {
            var r = i / cols;
            var c = i % cols;
            var x0 = c * cw;
            var y0 = r * ch;
            var front = (i < 2);
            if (i % 2 == 0) {
                var est = front ? fAir : rAir;
                var tgt = front ? fTgt : rTgt;
                drawAir(dc, x0, y0, cw, ch, est, tgt, front ? "FRONT" : "REAR");
            } else {
                drawSeal(dc, x0, y0, cw, ch, front ? fSeal : rSeal, front ? "FRONT" : "REAR");
            }
        }
        if (stale) {
            dc.setColor(0xF2B21A, Graphics.COLOR_BLACK);
            dc.drawText(w / 2, h - 2, Graphics.FONT_XTINY, "! numbers are old, update in Garmin Connect", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function drawTextOnly(dc, w, h) {
        var zf = airZone(fAir, fTgt);
        dc.setColor(zoneColor(zf), Graphics.COLOR_BLACK);
        var s = "F " + zoneWord(zf) + " " + fAir.format("%.1f");
        if (stale) { s = s + " !"; }
        dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawAir(dc, x0, y0, cw, ch, est, tgt, name) {
        var z = 2;
        var dmax = 60.0;
        var zones = null;
        if (tgt > 0.0) {
            zones = airZones(tgt);
            dmax = zones[4];
            z = airZone(est, tgt);
        }
        var cx = x0 + cw / 2;
        var rad = dialRadius(cw, ch);
        var cy = y0 + 4 + rad;
        if (zones != null) {
            band(dc, cx, cy, rad, 0.0, zones[0], dmax, zoneColor(0));
            band(dc, cx, cy, rad, zones[0], zones[1], dmax, zoneColor(1));
            band(dc, cx, cy, rad, zones[1], zones[2], dmax, zoneColor(2));
            band(dc, cx, cy, rad, zones[2], zones[3], dmax, zoneColor(3));
            band(dc, cx, cy, rad, zones[3], dmax, dmax, zoneColor(4));
            marker(dc, cx, cy, rad, tgt, dmax);
        } else {
            band(dc, cx, cy, rad, 0.0, dmax, dmax, 0x555555);
        }
        ticks(dc, cx, cy, rad);
        needle(dc, cx, cy, rad, est, dmax);
        label(dc, cx, cy, rad, name, "PSI");
        var txt = zoneWord(z) + " " + est.format("%.1f");
        valueText(dc, cx, cy, rad, ch, y0, txt, zoneColor(z));
        if (z == 4) {
            dc.setColor(zoneColor(4), Graphics.COLOR_BLACK);
            dc.drawText(cx, cy + rad + 4 + Graphics.getFontHeight(Graphics.FONT_XTINY) + 2, Graphics.FONT_XTINY, "Release air", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawSeal(dc, x0, y0, cw, ch, pct, name) {
        var z = sealZone(pct);
        var cx = x0 + cw / 2;
        var rad = dialRadius(cw, ch);
        var cy = y0 + 4 + rad;
        band(dc, cx, cy, rad, 0.0, SEAL_LOW, 100.0, zoneColor(0));
        band(dc, cx, cy, rad, SEAL_LOW, SEAL_OK, 100.0, zoneColor(1));
        band(dc, cx, cy, rad, SEAL_OK, 100.0, 100.0, zoneColor(2));
        ticks(dc, cx, cy, rad);
        needle(dc, cx, cy, rad, pct, 100.0);
        label(dc, cx, cy, rad, name, "SEALANT %");
        valueText(dc, cx, cy, rad, ch, y0, zoneWord(z) + " " + pct.format("%.0f") + "%", zoneColor(z));
    }

    function dialRadius(cw, ch) {
        var r = cw / 2 - 3;
        var byH = (ch - 4 - 2 * Graphics.getFontHeight(Graphics.FONT_XTINY) - 8) / 2;
        if (byH < r) { r = byH; }
        if (r < 14) { r = 14; }
        return r;
    }

    function norm(a) {
        var n = a.toNumber() % 360;
        if (n < 0) { n = n + 360; }
        return n;
    }

    // value range v0..v1 of a dial that runs 0..dmax, drawn as a colored arc
    function band(dc, cx, cy, rad, v0, v1, dmax, color) {
        if (v1 <= v0) { return; }
        var d0 = SWEEP_START + SWEEP * clampF(v0 / dmax);
        var d1 = SWEEP_START + SWEEP * clampF(v1 / dmax);
        var pen = rad / 3;
        if (pen < 4) { pen = 4; }
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(pen.toNumber());
        dc.drawArc(cx, cy, (rad - pen / 2).toNumber(), Graphics.ARC_CLOCKWISE, norm(90.0 - d0), norm(90.0 - d1));
        dc.setPenWidth(1);
    }

    function clampF(f) {
        if (f < 0.0) { return 0.0; }
        if (f > 1.0) { return 1.0; }
        return f;
    }

    function polar(cx, cy, r, deg) {
        var a = deg * Math.PI / 180.0;
        return [cx + r * Math.sin(a), cy - r * Math.cos(a)];
    }

    function ticks(dc, cx, cy, rad) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(1);
        for (var k = 0; k <= 12; k++) {
            var d = SWEEP_START + SWEEP * k / 12.0;
            var p0 = polar(cx, cy, rad.toFloat(), d);
            var p1 = polar(cx, cy, rad.toFloat() + 3.0, d);
            dc.drawLine(p0[0].toNumber(), p0[1].toNumber(), p1[0].toNumber(), p1[1].toNumber());
        }
    }

    function marker(dc, cx, cy, rad, tgt, dmax) {
        var d = SWEEP_START + SWEEP * clampF(tgt / dmax);
        var p0 = polar(cx, cy, rad.toFloat() + 5.0, d);
        var p1 = polar(cx, cy, rad.toFloat() - rad / 3.0, d);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        dc.drawLine(p0[0].toNumber(), p0[1].toNumber(), p1[0].toNumber(), p1[1].toNumber());
        dc.setPenWidth(1);
    }

    function needle(dc, cx, cy, rad, v, dmax) {
        var d = SWEEP_START + SWEEP * clampF(v / dmax);
        var tip = polar(cx, cy, rad.toFloat() - 3.0, d);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.setPenWidth(5);
        dc.drawLine(cx, cy, tip[0].toNumber(), tip[1].toNumber());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy, tip[0].toNumber(), tip[1].toNumber());
        dc.setPenWidth(1);
        dc.fillCircle(cx, cy, 4);
    }

    function label(dc, cx, cy, rad, name, unit) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        dc.drawText(cx, cy + (rad * 0.35).toNumber(), Graphics.FONT_XTINY, name, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + (rad * 0.35).toNumber() + fh - 2, Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function valueText(dc, cx, cy, rad, ch, y0, txt, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy + rad + 2, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function readFloat(id) {
        var v = null;
        try {
            v = Application.Properties.getValue(id);
        } catch (e) {
            v = null;
        }
        if (v == null) { return 0.0; }
        if (v instanceof Lang.Boolean) {
            return v ? 1.0 : 0.0;
        }
        return v.toFloat();
    }

    // Days since the date typed as YYYYMMDD. Returns -1 when no date is set.
    function ageDays(ymd) {
        if (ymd <= 0) { return -1; }
        var then = Gregorian.moment({
            :year => ymd / 10000,
            :month => (ymd / 100) % 100,
            :day => ymd % 100,
            :hour => 12
        });
        return Time.now().subtract(then).value() / 86400;
    }
}
