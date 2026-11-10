import Toybox.Application;
import Toybox.Attention;
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
    const SEAL_OK = 90.0;   // green starts at 90% of the recommended full dose (small buffer for drying)
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
    var known = false;        // numbers have been entered (an update date is set)
    var alarmMode = 0;        // 0 sound and vibration, 1 vibration only, 2 silent
    var dangerOn = true;
    var chirpOn = true;
    var dangerSig = 0;        // bit set of the problems already announced; each sounds once
    var wasOptimal = false;
    var started = false;

    function initialize() {
        DataField.initialize();
    }

    // Called about once a second. Checks for danger and for the optimal state, and sounds the alert on the Edge.
    // The alarm sounds once when a problem appears and never repeats; a different new problem sounds once more.
    function compute(info) {
        readAll();
        checkAlerts();
        return null;
    }

    // Bits: 1 front air, 2 front sealant, 4 rear air, 8 rear sealant. A bit is set when that dial reads red.
    function dangerBits() {
        var b = 0;
        if (fTgt > 0.0) {
            var z = airZone(fAir, fTgt);
            if (z == 0 || z == 4) { b = b | 1; }
        }
        if (fSeal < SEAL_LOW) { b = b | 2; }
        if (rTgt > 0.0) {
            var z2 = airZone(rAir, rTgt);
            if (z2 == 0 || z2 == 4) { b = b | 4; }
        }
        if (rSeal < SEAL_LOW) { b = b | 8; }
        return b;
    }

    // Optimal: both tires have air in the green zone and sealant at or above 90% of a full dose.
    function isOptimal() {
        if (fTgt <= 0.0 || rTgt <= 0.0) { return false; }
        return airZone(fAir, fTgt) == 2 && airZone(rAir, rTgt) == 2 && sealZone(fSeal) == 2 && sealZone(rSeal) == 2;
    }

    function checkAlerts() {
        if (!known || stale) { return; }
        var bits = dangerBits();
        if (dangerOn) {
            var fresh = bits & ~dangerSig;
            if (fresh != 0) { playAlert(1); }
        }
        dangerSig = bits;   // a problem that clears can sound again if it returns
        var opt = isOptimal();
        if (!started) {
            started = true;
            wasOptimal = false;
            var saved = null;
            try { saved = Application.Storage.getValue("wasOpt"); } catch (e) { saved = null; }
            if (saved != null && saved == true) { wasOptimal = true; }
        }
        if (opt && !wasOptimal && chirpOn && bits == 0) { playAlert(0); }
        if (opt != wasOptimal) {
            wasOptimal = opt;
            try { Application.Storage.setValue("wasOpt", opt); } catch (e2) { }
        }
    }

    // kind 1 = danger (alarm tone, long double buzz), 0 = optimal chirp (one high tone, short buzz).
    function playAlert(kind) {
        if (alarmMode >= 2) { return; }
        if (alarmMode == 0 && Attention has :playTone) {
            if (kind == 1) { Attention.playTone(Attention.TONE_ALARM); } else { Attention.playTone(Attention.TONE_ALERT_HI); }
        }
        if (Attention has :vibrate) {
            if (kind == 1) {
                Attention.vibrate([new Attention.VibeProfile(100, 450), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 450)]);
            } else {
                Attention.vibrate([new Attention.VibeProfile(60, 150)]);
            }
        }
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
        alarmMode = readFloat("alarmMode").toNumber();
        dangerOn = readFloat("dangerOn") > 0.5;
        chirpOn = readFloat("chirpOn") > 0.5;
        known = readFloat("updated") > 0.0;
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

        if (h * 4 >= w * 3) {
            // tall or full-screen field: a Front tire box and a Rear tire box, like the Home screen of the phone app
            try {
                drawBoxes(dc, w, h);
            } catch (ex) {
                // show the error on screen so a problem can be reported
                var m = ex.getErrorMessage();
                if (m == null) { m = "ERR"; }
                dc.setColor(0xE5483B, Graphics.COLOR_BLACK);
                dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, m, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                ex.printStackTrace();
            }
            if (stale) {
                dc.setColor(0xF2B21A, Graphics.COLOR_BLACK);
                dc.drawText(w / 2, h - Graphics.getFontHeight(Graphics.FONT_XTINY) / 2 - 1, Graphics.FONT_XTINY, "! numbers are old, update in Garmin Connect", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
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

    // ---- Home-screen style layout: one box per tire (red or green outline, tag, two dials, readouts, fix line) ----
    function drawBoxes(dc, w, h) {
        var gap = 6;
        var foot = 0;
        if (stale) { foot = Graphics.getFontHeight(Graphics.FONT_XTINY) + 2; }
        var bh = (h - foot - gap * 3) / 2;
        drawBox(dc, 4, gap, w - 8, bh, true);
        drawBox(dc, 4, gap * 2 + bh, w - 8, bh, false);
    }

    function drawBox(dc, bx, by, bw, bh, front) {
        var est = front ? fAir : rAir;
        var tgt = front ? fTgt : rTgt;
        var seal = front ? fSeal : rSeal;
        var za = 2;
        if (tgt > 0.0) { za = airZone(est, tgt); }
        var zs = sealZone(seal);
        var red = (tgt > 0.0 && (za == 0 || za == 4)) || zs == 0;
        var edge = red ? zoneColor(0) : zoneColor(2);
        var fm = Graphics.getFontHeight(Graphics.FONT_SMALL);
        var fx = Graphics.getFontHeight(Graphics.FONT_XTINY);

        // outline and header
        dc.setColor(edge, Graphics.COLOR_BLACK);
        dc.setPenWidth(3);
        dc.drawRoundedRectangle(bx, by, bw, bh, 12);
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(bx + 12, by + 5, Graphics.FONT_SMALL, front ? "Front tire" : "Rear tire", Graphics.TEXT_JUSTIFY_LEFT);
        var tag = red ? "RED" : "GREEN";
        var tw = dc.getTextWidthInPixels(tag, Graphics.FONT_XTINY) + 18;
        var th = fx + 2;
        var tx = bx + bw - tw - 10;
        var ty = by + 5 + (fm - th) / 2;
        dc.setColor(edge, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(tx, ty, tw, th, 4);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx + tw / 2, ty + th / 2, Graphics.FONT_XTINY, tag, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // dial size from the space left under the header
        var hh = fm + 12;
        var fixh = fm + 8;
        var readh = fm + fx + 10;
        var cell = (bw - 8) / 2;
        var rad = cell / 2 - 10;
        var byH = (bh - hh - fixh - readh - 8) / 2;
        if (byH < rad) { rad = byH; }
        if (rad < 20) { rad = 20; }
        var cy = by + hh + 4 + rad;
        var cx1 = bx + 4 + cell / 2;
        var cx2 = bx + 4 + cell + cell / 2;

        // air dial (same look as the phone app: chrome bezel, thick band, inner BAR scale)
        var dmax = 60.0;
        var azones = [];
        if (tgt > 0.0) {
            var zz = airZones(tgt);
            dmax = zz[4];
            azones = [[0.0, zz[0], zoneColor(0)], [zz[0], zz[1], zoneColor(1)], [zz[1], zz[2], zoneColor(2)], [zz[2], zz[3], zoneColor(3)], [zz[3], dmax, zoneColor(4)]];
        } else {
            azones = [[0.0, dmax, 0x555555]];
        }
        gauge(dc, cx1, cy, rad, dmax, azones, tgt, est, "PSI", [1.0 / 14.5038, "BAR", [0.5, 1.0, 2.0, 5.0]]);

        // sealant dial (percent of a full dose)
        gauge(dc, cx2, cy, rad, 120.0, [[0.0, SEAL_LOW, zoneColor(0)], [SEAL_LOW, SEAL_OK, zoneColor(1)], [SEAL_OK, 120.0, zoneColor(2)]], -1.0, seal, "SEAL %", null);

        // readouts under each dial
        var ry = cy + rad + 9;
        var aTxt = readWord(za) + " - " + est.format("%.1f") + " PSI";
        var sTxt = readWord(zs) + " - " + seal.format("%.0f") + "%";
        readout(dc, cx1, ry, cell, aTxt, zoneColor(za));
        readout(dc, cx2, ry, cell, sTxt, zoneColor(zs));
        dc.setColor(0xA9A49B, Graphics.COLOR_BLACK);
        var sub = "Target not set";
        if (tgt > 0.0) { sub = "Target " + tgt.format("%.1f") + " PSI"; }
        dc.drawText(cx1, ry + fm, Graphics.FONT_XTINY, sub, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx2, ry + fm, Graphics.FONT_XTINY, "of full dose", Graphics.TEXT_JUSTIFY_CENTER);

        // what to do
        var fix = "";
        if (tgt > 0.0) {
            if (za <= 1) { fix = "Add air to " + tgt.format("%.1f") + " PSI"; }
            else if (za == 3) { fix = "Release a little air"; }
            else if (za == 4) { fix = "Release air to " + tgt.format("%.1f") + " PSI"; }
        }
        if (zs == 0) {
            if (fix.length() > 0) { fix = fix + ", add sealant"; } else { fix = "Add sealant"; }
        }
        if (fix.length() == 0) { fix = "Good"; }
        dc.setColor(red ? zoneColor(0) : Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var fixFont = Graphics.FONT_SMALL;
        if (dc.getTextWidthInPixels(fix, fixFont) > bw - 16) { fixFont = Graphics.FONT_TINY; }
        dc.drawText(bx + bw / 2, by + bh - fixh + 2, fixFont, fix, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function readWord(z) {
        if (z == 4) { return "Over"; }
        return zoneWord(z);
    }

    function readout(dc, cx, y, cell, txt, color) {
        var f = Graphics.FONT_SMALL;
        if (dc.getTextWidthInPixels(txt, f) > cell - 4) { f = Graphics.FONT_TINY; }
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(cx, y, f, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // One dial in the phone app's style. zones = [[from, to, color], ...]; alt = [multiplier, name, steps] for the inner scale, or null.
    function gauge(dc, cx, cy, rad, dmax, zones, tgt, v, unit, alt) {
        var k = rad / 79.0;
        var r1 = 73.5 * k;
        var r0 = 47.0 * k;
        var face = (76.8 * k).toNumber();
        // chrome bezel and black face
        dc.setColor(0xD4D7DA, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, rad);
        dc.setColor(0x000000, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, face);
        dc.setColor(0x8A8D91, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, face);
        dc.setPenWidth(1);
        // colored band
        var mid = (r0 + r1) / 2.0;
        var pen = (r1 - r0).toNumber();
        for (var z = 0; z < zones.size(); z++) {
            var zn = zones[z];
            if (zn[1] > zn[0]) {
                var d0 = SWEEP_START + SWEEP * clampF(zn[0] / dmax);
                var d1 = SWEEP_START + SWEEP * clampF(zn[1] / dmax);
                dc.setColor(zn[2], Graphics.COLOR_BLACK);
                dc.setPenWidth(pen);
                dc.drawArc(cx, cy, mid.toNumber(), Graphics.ARC_CLOCKWISE, norm(90.0 - d0), norm(90.0 - d1));
            }
        }
        dc.setPenWidth(1);
        // black ticks on the band edge
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        for (var i = 0; i <= 12; i++) {
            var big = (i % 2 == 0);
            var d = SWEEP_START + SWEEP * i / 12.0;
            var q0 = polar(cx, cy, r1, d);
            var q1 = polar(cx, cy, r1 - (big ? 9.0 : 5.0) * k, d);
            dc.setPenWidth(big ? 3 : 1);
            dc.drawLine(q0[0].toNumber(), q0[1].toNumber(), q1[0].toNumber(), q1[1].toNumber());
        }
        dc.setPenWidth(1);
        // bold numbers on the band: black with a white outline
        for (var j = 0; j <= 12; j += 2) {
            var val = dmax * j / 12.0;
            var da = SWEEP_START + SWEEP * j / 12.0;
            var pp = polar(cx, cy, r0 + 11.0 * k, da);
            outlined(dc, pp[0].toNumber(), pp[1].toNumber(), numStr(val));
        }
        // inner scale in the other unit (white)
        if (alt != null) {
            var steps = alt[2];
            var im = dmax * alt[0];
            var st = steps[steps.size() - 1];
            for (var s2 = steps.size() - 1; s2 >= 0; s2--) {
                if (im / steps[s2] <= 6.0) { st = steps[s2]; }
            }
            var n = (im / st + 0.000001).toNumber();
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            for (var u = 0; u <= n; u++) {
                var uv = u * st;
                var ua = SWEEP_START + SWEEP * clampF(uv / alt[0] / dmax);
                var t0 = polar(cx, cy, r0 - 3.0 * k, ua);
                var t1 = polar(cx, cy, r0 - 8.0 * k, ua);
                var t2 = polar(cx, cy, r0 - 20.0 * k, ua);
                dc.setPenWidth(2);
                dc.drawLine(t0[0].toNumber(), t0[1].toNumber(), t1[0].toNumber(), t1[1].toNumber());
                dc.setPenWidth(1);
                dc.drawText(t2[0].toNumber(), t2[1].toNumber(), Graphics.FONT_XTINY, numStr(uv), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
        // target marker: white triangle on the outer edge of the band
        if (tgt > 0.0) {
            var ta = SWEEP_START + SWEEP * clampF(tgt / dmax);
            var m0 = polar(cx, cy, r1 - 7.0 * k, ta);
            var m1 = polar(cx, cy, r1 + 2.5 * k, ta - 3.2);
            var m2 = polar(cx, cy, r1 + 2.5 * k, ta + 3.2);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.fillPolygon([[m0[0].toNumber(), m0[1].toNumber()], [m1[0].toNumber(), m1[1].toNumber()], [m2[0].toNumber(), m2[1].toNumber()]]);
        }
        // needle: black outline, white core, short tail
        var na = SWEEP_START + SWEEP * clampF(v / dmax);
        var tip = polar(cx, cy, r1 - 2.0 * k, na);
        var tail = polar(cx, cy, -13.0 * k, na);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.setPenWidth(7);
        dc.drawLine(tail[0].toNumber(), tail[1].toNumber(), tip[0].toNumber(), tip[1].toNumber());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);
        dc.drawLine(tail[0].toNumber(), tail[1].toNumber(), tip[0].toNumber(), tip[1].toNumber());
        dc.setPenWidth(1);
        // chrome hub
        dc.setColor(0xCFD2D6, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, (8.5 * k).toNumber());
        dc.setColor(0x2A2C2F, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, (5.2 * k).toNumber());
        // unit labels
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy + (30.0 * k).toNumber(), Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);
        if (alt != null) {
            dc.setColor(0xA9A49B, Graphics.COLOR_BLACK);
            dc.drawText(cx, cy + (30.0 * k).toNumber() + Graphics.getFontHeight(Graphics.FONT_XTINY) - 4, Graphics.FONT_XTINY, alt[1], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function outlined(dc, x, y, t) {
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y, Graphics.FONT_XTINY, t, j);
        dc.drawText(x + 1, y, Graphics.FONT_XTINY, t, j);
        dc.drawText(x, y - 1, Graphics.FONT_XTINY, t, j);
        dc.drawText(x, y + 1, Graphics.FONT_XTINY, t, j);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, t, j);
    }

    // 60.0 -> "60", 0.5 -> "0.5", 1.25 -> "1.25"
    function numStr(v) {
        var s = v.format("%.2f");
        var n = s.length();
        while (s.substring(n - 1, n).equals("0")) {
            n = n - 1;
            s = s.substring(0, n);
        }
        if (s.substring(n - 1, n).equals(".")) { s = s.substring(0, n - 1); }
        return s;
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
        var cy = y0 + dialTop(ch, rad) + rad;
        bezel(dc, cx, cy, rad);
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
            dc.drawText(cx, cy + rad + 10 + Graphics.getFontHeight(Graphics.FONT_XTINY) + 2, Graphics.FONT_XTINY, "Release air", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawSeal(dc, x0, y0, cw, ch, pct, name) {
        var z = sealZone(pct);
        var cx = x0 + cw / 2;
        var rad = dialRadius(cw, ch);
        var cy = y0 + dialTop(ch, rad) + rad;
        bezel(dc, cx, cy, rad);
        band(dc, cx, cy, rad, 0.0, SEAL_LOW, 120.0, zoneColor(0));
        band(dc, cx, cy, rad, SEAL_LOW, SEAL_OK, 120.0, zoneColor(1));
        band(dc, cx, cy, rad, SEAL_OK, 120.0, 120.0, zoneColor(2));
        ticks(dc, cx, cy, rad);
        needle(dc, cx, cy, rad, pct, 120.0);
        label(dc, cx, cy, rad, name, "SEALANT %");
        valueText(dc, cx, cy, rad, ch, y0, zoneWord(z) + " " + pct.format("%.0f") + "%", zoneColor(z));
    }

    function dialRadius(cw, ch) {
        var r = cw / 2 - 9;
        var byH = (ch - 20 - 2 * Graphics.getFontHeight(Graphics.FONT_XTINY) - 14) / 2;
        if (byH < r) { r = byH; }
        if (r < 14) { r = 14; }
        return r;
    }

    // top padding so the dial and its value line sit centered in the cell (never less than 10, so the ring is not clipped)
    function dialTop(ch, rad) {
        var used = 2 * rad + 10 + Graphics.getFontHeight(Graphics.FONT_XTINY) * 2 + 4;
        var pad = (ch - used) / 2;
        if (pad < 10) { pad = 10; }
        return pad;
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

    // thin light ring around the dial, like the bezel in the phone app
    function bezel(dc, cx, cy, rad) {
        dc.setColor(0xC4C8CC, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, rad + 7);
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
        dc.drawText(cx, cy + rad + 10, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER);
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
