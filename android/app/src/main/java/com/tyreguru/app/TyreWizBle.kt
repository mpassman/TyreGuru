package com.tyreguru.app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * TyreWiz discovery over Bluetooth LE, matching TyreWizBridge on iPhone.
 * Page to phone: {"cmd":"watch","paired":[ids]}, {"cmd":"pair","id":"..."}, {"cmd":"forget","id":"..."}, {"cmd":"rescan"}.
 * An id here is the sensor's Bluetooth address. SRAM does not publish the TyreWiz format, so after pairing this
 * subscribes to everything the sensor offers and passes each raw message to the page, which logs it.
 * Paired sensors are reached with a pending connection (autoConnect), kept alive by TyreWizService.
 * Readings that arrive while the page is not on screen are kept and handed over, with their real times, when the app opens.
 * NOT compiled or run by the author.
 */
@SuppressLint("MissingPermission")
object TyreWizBle {
    var sink: ((String, String) -> Unit)? = null
    var visible: () -> Boolean = { false }
    private lateinit var ctx: Context
    private var ready = false
    private val main = Handler(Looper.getMainLooper())
    private val paired = HashSet<String>()
    private val gatts = HashMap<String, BluetoothGatt>()
    private val lastSent = HashMap<String, Long>()
    private var scanning = false
    private var continuousUntil = 0L
    private val prefs get() = ctx.getSharedPreferences("tg", Context.MODE_PRIVATE)

    fun attach(c: Context) {
        if (ready) return
        ctx = c; ready = true
        paired.addAll(prefs.getStringSet("tw.paired", emptySet()) ?: emptySet())
        if (paired.isNotEmpty() && hasBt()) startService()
    }

    private val adapter: BluetoothAdapter? get() = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private fun hasBt() = if (Build.VERSION.SDK_INT >= 31)
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    else ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun savePaired() = prefs.edit().putStringSet("tw.paired", HashSet(paired)).apply()
    private fun startService() { try { ContextCompat.startForegroundService(ctx, Intent(ctx, TyreWizService::class.java)) } catch (e: Exception) {} }
    private fun status(t: String) { val s = JSONObject.quote(t.replace("\\", "")); main.post { sink?.invoke("__tyrewizStatus", s) } }
    private fun send(fn: String, o: JSONObject) { main.post { sink?.invoke(fn, o.toString()) } }

    private var pendingCmd: JSONObject? = null
    fun onPermissions(r: Map<String, Boolean>) { val c = pendingCmd; pendingCmd = null; if (c != null && hasBt()) command(c) else if (c != null) status("Bluetooth is off for TyreGuru. Allow it in Android Settings.") }

    fun command(o: JSONObject) {
        if (!hasBt()) {
            pendingCmd = o
            val list = if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            main.post { (ctx as? Context)?.let { MainHolder.act?.ask(list) } }
            return
        }
        when (o.optString("cmd")) {
            "watch" -> { paired.clear(); val a = o.optJSONArray("paired") ?: JSONArray(); for (i in 0 until a.length()) paired.add(a.getString(i)); savePaired()
                         if (paired.isNotEmpty()) startService(); connectPaired(); startBursts() }
            "rescan" -> { lastSent.clear(); continuousUntil = System.currentTimeMillis() + 90000; startBursts() }
            "pair" -> { val id = o.optString("id"); paired.add(id); savePaired(); status("Connecting to the sensor..."); startService(); connect(id) }
            "forget" -> { val id = o.optString("id"); paired.remove(id); savePaired(); gatts.remove(id)?.close() }
        }
    }

    fun connectPaired() { if (ready && hasBt()) paired.forEach { connect(it) } }

    private fun connect(id: String) {
        val ad = adapter ?: return
        if (gatts.containsKey(id)) return
        try { gatts[id] = ad.getRemoteDevice(id).connectGatt(ctx, true, cb, BluetoothDevice.TRANSPORT_LE) } catch (e: Exception) { status("Could not connect: ${e.message}") }
    }

    // ---- scanning: foreground bursts (10 s every 60 s), or constant while the pairing screen is open
    private val tick = object : Runnable { override fun run() {
        if (!visible()) { stopScan(); return }
        val now = System.currentTimeMillis()
        if (now < continuousUntil) { if (!scanning) beginScan(); main.postDelayed(this, 1000); return }
        if (!scanning) { beginScan(); main.postDelayed({ stopScan() }, 10000) }
        main.postDelayed(this, 60000) } }

    fun startBursts() { stopScan(); main.removeCallbacks(tick); main.post(tick) }
    private fun beginScan() { adapter?.bluetoothLeScanner?.let { try { it.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanCb); scanning = true } catch (e: Exception) {} } }
    private fun stopScan() { if (scanning) { try { adapter?.bluetoothLeScanner?.stopScan(scanCb) } catch (e: Exception) {}; scanning = false } }

    private fun looksLikeTyreWiz(n: String) = n.lowercase().let { it.contains("tyrewiz") || it.contains("tirewiz") || it.contains("quarq") }

    private val scanCb = object : ScanCallback() {
        override fun onScanResult(type: Int, r: ScanResult) {
            val name = r.scanRecord?.deviceName ?: r.device.name ?: ""
            if (!looksLikeTyreWiz(name)) return
            val id = r.device.address
            if (paired.contains(id)) { connect(id); return }
            val now = System.currentTimeMillis()
            if (now - (lastSent[id] ?: 0) >= 2000) { lastSent[id] = now; send("__tyrewizSeen", JSONObject().put("id", id).put("name", name).put("rssi", r.rssi)) }
        }
    }

    private val cb = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, st: Int, ns: Int) {
            val id = g.device.address
            if (ns == BluetoothProfile.STATE_CONNECTED) { status("Connected to ${g.device.name ?: "the sensor"}. Reading what it sends..."); g.discoverServices() }
            else if (ns == BluetoothProfile.STATE_DISCONNECTED) { status("Sensor disconnected. It will reconnect when it is in range.")
                if (!paired.contains(id)) { g.close(); gatts.remove(id) } }   // autoConnect keeps paired ones pending
        }
        override fun onServicesDiscovered(g: BluetoothGatt, st: Int) {
            val queue = ArrayDeque<BluetoothGattCharacteristic>()
            for (s in g.services) for (c in s.characteristics) {
                send("__tyrewizData", JSONObject().put("id", g.device.address).put("name", g.device.name ?: "").put("svc", s.uuid.toString().uppercase())
                    .put("chr", c.uuid.toString().uppercase()).put("props", c.properties).put("hex", "").put("kind", "found"))
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 || c.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) {
                    g.setCharacteristicNotification(c, true)
                    c.getDescriptor(java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))?.let { d ->
                        d.value = if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                        pendingWrites.add(d) } }
                if (c.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) queue.add(c)
            }
            // Android allows one GATT operation at a time, so descriptors and reads go in a queue.
            pendingReads.addAll(queue); gatt = g; next()
        }
        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, st: Int) { busy = false; next() }
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, st: Int) { value(g, c, c.value); busy = false; next() }
        @Deprecated("") override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) { value(g, c, c.value) }
    }
    private val pendingWrites = ArrayDeque<BluetoothGattDescriptor>()
    private val pendingReads = ArrayDeque<BluetoothGattCharacteristic>()
    private var busy = false
    private var gatt: BluetoothGatt? = null
    private fun next() {
        if (busy) return
        val g = gatt ?: return
        val w = pendingWrites.removeFirstOrNull()
        if (w != null) { busy = true; g.writeDescriptor(w); return }
        val r = pendingReads.removeFirstOrNull()
        if (r != null) { busy = true; g.readCharacteristic(r) }
    }

    private fun value(g: BluetoothGatt, c: BluetoothGattCharacteristic, v: ByteArray?) {
        if (v == null) return
        val o = JSONObject().put("id", g.device.address).put("name", g.device.name ?: "").put("svc", c.service.uuid.toString().uppercase())
            .put("chr", c.uuid.toString().uppercase()).put("props", c.properties).put("hex", v.joinToString("") { "%02x".format(it) })
            .put("kind", "value").put("ts", System.currentTimeMillis())
        if (visible() && sink != null) send("__tyrewizData", o)
        else { val buf = JSONArray(prefs.getString("tw.buffer", "[]")); buf.put(o)
               val keep = JSONArray(); for (i in maxOf(0, buf.length() - 400) until buf.length()) keep.put(buf.get(i))
               prefs.edit().putString("tw.buffer", keep.toString()).apply() }
    }

    fun flush() {
        if (!ready) return
        val buf = JSONArray(prefs.getString("tw.buffer", "[]")); if (buf.length() == 0) return
        prefs.edit().remove("tw.buffer").apply()
        for (i in 0 until buf.length()) main.postDelayed({ send("__tyrewizData", buf.getJSONObject(i)) }, 600L + i * 20L)
        startBursts()
    }
}

/** Lets non-activity code ask the visible activity for permissions. */
object MainHolder { var act: MainActivity? = null }
