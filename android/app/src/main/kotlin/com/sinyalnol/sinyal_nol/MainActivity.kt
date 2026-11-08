package com.sinyalnol.sinyal_nol

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.NetworkInterface
import java.util.Collections
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private val SERVICE_CHANNEL = "com.sinyalnol/mesh_service"
    private val COMPASS_CHANNEL = "com.sinyalnol/compass"
    private val SYSTEM_SETTINGS_CHANNEL = "com.sinyalnol/system_settings"
    private val BLUETOOTH_CHANNEL = "com.sinyalnol/bluetooth"
    private val BLUETOOTH_EVENTS_CHANNEL = "com.sinyalnol/bluetooth_events"
    private val USB_LORA_CHANNEL = "com.sinyalnol/usb_lora"

    // Standard Bluetooth Serial Port Profile (SPP) UUID
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var sensorManager: SensorManager? = null
    private var rotationVectorSensor: Sensor? = null
    private var compassListener: SensorEventListener? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var btServerSocket: BluetoothServerSocket? = null
    private var isBtServerRunning = false
    private var bluetoothEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. MethodChannel untuk Foreground Service & Wakelock Management
        MethodChannel(messenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val title = call.argument<String>("title") ?: "SinyalNol Mesh Radio Siaga"
                    val text = call.argument<String>("text") ?: "Radio P2P & Dead Man's Switch aktif"
                    TacticalMeshService.start(context, title, text)
                    result.success(true)
                }
                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: "SinyalNol Mesh Radio Siaga"
                    val text = call.argument<String>("text") ?: "Radio P2P & Dead Man's Switch aktif"
                    TacticalMeshService.update(context, title, text)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    TacticalMeshService.stop(context)
                    result.success(true)
                }
                "setTorchMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    try {
                        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as? android.hardware.camera2.CameraManager
                        val cameraId = cameraManager?.cameraIdList?.firstOrNull()
                        if (cameraId != null) {
                            cameraManager.setTorchMode(cameraId, enabled)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. EventChannel untuk Kompas Sensor Magnetik & Azimuth Fisik
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationVectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

        EventChannel(messenger, COMPASS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (rotationVectorSensor == null || events == null) {
                        events?.error("SENSOR_UNAVAILABLE", "Sensor Rotation Vector / Kompas tidak ditemukan", null)
                        return
                    }

                    val rotationMatrix = FloatArray(9)
                    val orientationValues = FloatArray(3)

                    compassListener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event?.sensor?.type == Sensor.TYPE_ROTATION_VECTOR) {
                                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                                SensorManager.getOrientation(rotationMatrix, orientationValues)

                                var azimuthDegrees = Math.toDegrees(orientationValues[0].toDouble())
                                if (azimuthDegrees < 0) {
                                    azimuthDegrees += 360.0
                                }
                                events.success(azimuthDegrees)
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }

                    sensorManager?.registerListener(
                        compassListener,
                        rotationVectorSensor,
                        SensorManager.SENSOR_DELAY_UI
                    )
                }

                override fun onCancel(arguments: Any?) {
                    compassListener?.let {
                        sensorManager?.unregisterListener(it)
                    }
                    compassListener = null
                }
            }
        )

        // 3. System Settings & Local Network Info Channel
        MethodChannel(messenger, SYSTEM_SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openTetheringSettings" -> {
                    try {
                        val intent = Intent("android.settings.TETHER_SETTINGS").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(fallback)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.message, null)
                    }
                }
                "getLocalIpAddress" -> {
                    result.success(resolveLocalIpAddress())
                }
                else -> result.notImplemented()
            }
        }

        // 4. Native Bluetooth RFCOMM Channel (SPP Profile)
        MethodChannel(messenger, BLUETOOTH_CHANNEL).setMethodCallHandler { call, result ->
            val adapter = BluetoothAdapter.getDefaultAdapter()
            when (call.method) {
                "isBluetoothSupported" -> {
                    result.success(adapter != null)
                }
                "isBluetoothEnabled" -> {
                    result.success(adapter?.isEnabled == true)
                }
                "getBondedDevices" -> {
                    if (adapter == null) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    try {
                        @Suppress("MissingPermission")
                        val bonded = adapter.bondedDevices?.map { dev ->
                            mapOf(
                                "name" to (dev.name ?: "Unknown Device"),
                                "address" to dev.address
                            )
                        } ?: emptyList()
                        result.success(bonded)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "startRfcommServer" -> {
                    if (adapter == null || !adapter.isEnabled) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    startRfcommListener(adapter)
                    result.success(true)
                }
                "stopRfcommServer" -> {
                    stopRfcommListener()
                    result.success(true)
                }
                "sendRfcommMessage" -> {
                    val address = call.argument<String>("address")
                    val message = call.argument<String>("message")
                    if (adapter == null || address.isNullOrEmpty() || message == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    thread {
                        val success = sendRfcommPayload(adapter, address, message)
                        mainHandler.post {
                            result.success(success)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel untuk Pesan Bluetooth RFCOMM Masuk
        EventChannel(messenger, BLUETOOTH_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bluetoothEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    bluetoothEventSink = null
                }
            }
        )

        // 5. USB OTG LoRa Bridge Channel
        MethodChannel(messenger, USB_LORA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAttachedUsbDevices" -> {
                    val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager
                    if (usbManager == null) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    val list = mutableListOf<Map<String, Any>>()
                    for ((_, device) in usbManager.deviceList) {
                        val vid = device.vendorId
                        val pid = device.productId
                        val isLoRaSerial = vid == 0x1A86 || // CH340 (Heltec / ESP32)
                                          vid == 0x10C4 || // CP2102 (LilyGO T-Beam)
                                          vid == 0x0403 || // FTDI
                                          vid == 0x303A || // Espressif ESP32-S3 CDC
                                          vid == 0x2E8A    // Raspberry Pi Pico RP2040
                        list.add(
                            mapOf(
                                "name" to (device.productName ?: "USB Serial Bridge"),
                                "vendorId" to vid,
                                "productId" to pid,
                                "deviceName" to device.deviceName,
                                "isLoRaCompatible" to isLoRaSerial
                            )
                        )
                    }
                    result.success(list)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveLocalIpAddress(): String {
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                val addrs = Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress) {
                        val sAddr = addr.hostAddress
                        val isIPv4 = sAddr?.indexOf(':') ?: -1 < 0
                        if (isIPv4 && sAddr != null) {
                            return sAddr
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return "127.0.0.1"
    }

    @Suppress("MissingPermission")
    private fun startRfcommListener(adapter: BluetoothAdapter) {
        if (isBtServerRunning) return
        isBtServerRunning = true

        thread {
            try {
                btServerSocket = adapter.listenUsingRfcommWithServiceRecord("SinyalNolSPP", SPP_UUID)
                while (isBtServerRunning) {
                    try {
                        val clientSocket = btServerSocket?.accept() ?: break
                        val reader = BufferedReader(InputStreamReader(clientSocket.inputStream, "UTF-8"))
                        val line = reader.readLine()
                        if (!line.isNullOrBlank()) {
                            val remoteMac = clientSocket.remoteDevice?.address ?: "BT_PEER"
                            val remoteName = clientSocket.remoteDevice?.name ?: "Bluetooth Node"

                            mainHandler.post {
                                bluetoothEventSink?.success(
                                    mapOf(
                                        "data" to line,
                                        "address" to remoteMac,
                                        "name" to remoteName
                                    )
                                )
                            }
                        }
                        try { clientSocket.close() } catch (_: Exception) {}
                    } catch (_: Exception) {
                        if (!isBtServerRunning) break
                    }
                }
            } catch (_: Exception) {
            } finally {
                isBtServerRunning = false
            }
        }
    }

    private fun stopRfcommListener() {
        isBtServerRunning = false
        try {
            btServerSocket?.close()
        } catch (_: Exception) {}
        btServerSocket = null
    }

    @Suppress("MissingPermission")
    private fun sendRfcommPayload(adapter: BluetoothAdapter, macAddress: String, payload: String): Boolean {
        var socket: BluetoothSocket? = null
        return try {
            val device = adapter.getRemoteDevice(macAddress)
            adapter.cancelDiscovery()
            socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            socket.connect()
            val writer = BufferedWriter(OutputStreamWriter(socket.outputStream, "UTF-8"))
            writer.write(payload)
            writer.write("\n")
            writer.flush()
            socket.close()
            true
        } catch (e: Exception) {
            try { socket?.close() } catch (_: Exception) {}
            false
        }
    }

    override fun onDestroy() {
        compassListener?.let {
            sensorManager?.unregisterListener(it)
        }
        compassListener = null
        stopRfcommListener()
        super.onDestroy()
    }
}
