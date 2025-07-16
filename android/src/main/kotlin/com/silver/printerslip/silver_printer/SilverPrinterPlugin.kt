package com.silver.printerslip.silver_printer

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.ArrayList

/** SilverPrinterPlugin */
class SilverPrinterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  
  companion object {
    private const val TAG = "SilverPrinterPlugin"
    private const val PERMISSION_REQUEST_CODE = 12345
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
  }
  
  private lateinit var context: Context
  private lateinit var channel: MethodChannel
  private lateinit var deviceDiscoveryChannel: EventChannel
  private lateinit var connectionStateChannel: EventChannel
  private lateinit var printerStatusChannel: EventChannel
  
  private var deviceDiscoverySink: EventChannel.EventSink? = null
  private var connectionStateSink: EventChannel.EventSink? = null
  private var printerStatusSink: EventChannel.EventSink? = null
  
  private var bluetoothAdapter: BluetoothAdapter? = null
  private var bluetoothLeScanner: BluetoothLeScanner? = null
  private var bluetoothSocket: BluetoothSocket? = null
  private var bluetoothGatt: BluetoothGatt? = null
  
  private val discoveredDevices = ConcurrentHashMap<String, Map<String, Any>>()
  private var isScanning = false
  private var connectionState = "disconnected"
  private var connectedDevice: Map<String, Any?>? = null
  private var printerStatus = "offline"
  
  private val mainHandler = Handler(Looper.getMainLooper())
  private var pendingResult: Result? = null
  private var activityBinding: ActivityPluginBinding? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "silver_printer")
    channel.setMethodCallHandler(this)
    
    deviceDiscoveryChannel = EventChannel(flutterPluginBinding.binaryMessenger, "silver_printer/device_discovery")
    deviceDiscoveryChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        deviceDiscoverySink = events
      }
      override fun onCancel(arguments: Any?) {
        deviceDiscoverySink = null
      }
    })
    
    connectionStateChannel = EventChannel(flutterPluginBinding.binaryMessenger, "silver_printer/connection_state")
    connectionStateChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        connectionStateSink = events
      }
      override fun onCancel(arguments: Any?) {
        connectionStateSink = null
      }
    })
    
    printerStatusChannel = EventChannel(flutterPluginBinding.binaryMessenger, "silver_printer/printer_status")
    printerStatusChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        printerStatusSink = events
      }
      override fun onCancel(arguments: Any?) {
        printerStatusSink = null
      }
    })
    
    initializeBluetooth()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    activityBinding = null
  }

  private fun initializeBluetooth() {
    val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    bluetoothAdapter = bluetoothManager.adapter
    bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
  }

  @SuppressLint("MissingPermission")
  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "isBluetoothAvailable" -> {
        result.success(bluetoothAdapter != null && bluetoothAdapter!!.isEnabled)
      }
      "requestBluetoothPermissions" -> {
        requestBluetoothPermissions(result)
      }
      "startScan" -> {
        startScan(result)
      }
      "stopScan" -> {
        stopScan(result)
      }
      "getDiscoveredDevices" -> {
        result.success(discoveredDevices.values.toList())
      }
      "getPairedDevices" -> {
        getPairedDevices(result)
      }
      "connect" -> {
        val deviceId = call.argument<String>("deviceId")
        if (deviceId != null) {
          connectToDevice(deviceId, result)
        } else {
          result.error("INVALID_ARGUMENT", "Device ID is required", null)
        }
      }
      "disconnect" -> {
        disconnect(result)
      }
      "getConnectionState" -> {
        result.success(connectionState)
      }
      "getConnectedDevice" -> {
        result.success(connectedDevice)
      }
      "isConnected" -> {
        result.success(connectionState == "connected")
      }
      "getPrinterStatus" -> {
        result.success(printerStatus)
      }
      "printText" -> {
        val text = call.argument<String>("text")
        val settings = call.argument<Map<String, Any>>("settings")
        if (text != null) {
          printText(text, settings, result)
        } else {
          result.error("INVALID_ARGUMENT", "Text is required", null)
        }
      }
      "printImage" -> {
        val imageData = call.argument<ByteArray>("imageData")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val settings = call.argument<Map<String, Any>>("settings")
        if (imageData != null) {
          printImage(imageData, width, height, settings, result)
        } else {
          result.error("INVALID_ARGUMENT", "Image data is required", null)
        }
      }
      "printJob" -> {
        val text = call.argument<String>("text") ?: ""
        val imageData = call.argument<ByteArray>("imageData")
        val width = call.argument<Int>("imageWidth")
        val height = call.argument<Int>("imageHeight")
        val settings = call.argument<Map<String, Any>>("settings")
        printJob(text, imageData, width, height, settings, result)
      }
      "feedPaper" -> {
        val lines = call.argument<Int>("lines") ?: 1
        feedPaper(lines, result)
      }
      "cutPaper" -> {
        cutPaper(result)
      }
      "sendRawData" -> {
        val data = call.argument<ByteArray>("data")
        if (data != null) {
          sendRawData(data, result)
        } else {
          result.error("INVALID_ARGUMENT", "Data is required", null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun requestBluetoothPermissions(result: Result) {
    val activity = activityBinding?.activity
    if (activity == null) {
      result.error("NO_ACTIVITY", "Activity not available", null)
      return
    }

    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.ACCESS_FINE_LOCATION
      )
    } else {
      arrayOf(
        Manifest.permission.BLUETOOTH,
        Manifest.permission.BLUETOOTH_ADMIN,
        Manifest.permission.ACCESS_FINE_LOCATION
      )
    }

    pendingResult = result
    ActivityCompat.requestPermissions(activity, permissions, PERMISSION_REQUEST_CODE)
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
    if (requestCode == PERMISSION_REQUEST_CODE) {
      val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
      pendingResult?.success(allGranted)
      pendingResult = null
      return true
    }
    return false
  }

  @SuppressLint("MissingPermission")
  private fun startScan(result: Result) {
    if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
      result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth is not available or enabled", null)
      return
    }

    if (isScanning) {
      result.success(null)
      return
    }

    discoveredDevices.clear()
    isScanning = true

    // Scan for Classic Bluetooth devices
    bluetoothAdapter?.startDiscovery()

    // Scan for BLE devices
    if (bluetoothLeScanner != null) {
      val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
          val device = scanResult.device
          val deviceInfo = mapOf<String, Any>(
            "id" to device.address,
            "name" to (device.name ?: "Unknown Device"),
            "address" to device.address,
            "type" to "ble",
            "rssi" to scanResult.rssi,
            "isPaired" to false
          )
          
          discoveredDevices[device.address] = deviceInfo
          deviceDiscoverySink?.success(deviceInfo)
        }

        override fun onScanFailed(errorCode: Int) {
          Log.e(TAG, "BLE scan failed with error: $errorCode")
        }
      }

      bluetoothLeScanner?.startScan(scanCallback)
    }

    result.success(null)
  }

  @SuppressLint("MissingPermission")
  private fun stopScan(result: Result) {
    if (isScanning) {
      bluetoothAdapter?.cancelDiscovery()
      bluetoothLeScanner?.stopScan(object : ScanCallback() {})
      isScanning = false
    }
    result.success(null)
  }

  @SuppressLint("MissingPermission")
  private fun getPairedDevices(result: Result) {
    if (bluetoothAdapter == null) {
      result.success(emptyList<Map<String, Any>>())
      return
    }

    val pairedDevices = bluetoothAdapter!!.bondedDevices.map { device ->
      mapOf<String, Any?>(
        "id" to device.address,
        "name" to (device.name ?: "Unknown Device"),
        "address" to device.address,
        "type" to "classic",
        "rssi" to null,
        "isPaired" to true
      )
    }

    result.success(pairedDevices)
  }

  @SuppressLint("MissingPermission")
  private fun connectToDevice(deviceId: String, result: Result) {
    if (bluetoothAdapter == null) {
      result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth adapter not available", null)
      return
    }

    updateConnectionState("connecting")

    try {
      val device = bluetoothAdapter!!.getRemoteDevice(deviceId)
      
      // Try Classic Bluetooth first
      bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
      bluetoothSocket?.connect()
      
      if (bluetoothSocket?.isConnected == true) {
        connectedDevice = mapOf<String, Any?>(
          "id" to device.address,
          "name" to (device.name ?: "Unknown Device"),
          "address" to device.address,
          "type" to "classic",
          "rssi" to null,
          "isPaired" to true
        )
        updateConnectionState("connected")
        updatePrinterStatus("ready")
        result.success(true)
      } else {
        // If Classic fails, try BLE
        connectBLE(device, result)
      }
    } catch (e: Exception) {
      Log.e(TAG, "Connection failed", e)
      updateConnectionState("disconnected")
      result.success(false)
    }
  }

  @SuppressLint("MissingPermission")
  private fun connectBLE(device: BluetoothDevice, result: Result) {
    val gattCallback = object : BluetoothGattCallback() {
      override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
        when (newState) {
          BluetoothProfile.STATE_CONNECTED -> {
            bluetoothGatt = gatt
            connectedDevice = mapOf<String, Any?>(
              "id" to device.address,
              "name" to (device.name ?: "Unknown Device"),
              "address" to device.address,
              "type" to "ble",
              "rssi" to null,
              "isPaired" to false
            )
            updateConnectionState("connected")
            updatePrinterStatus("ready")
            gatt?.discoverServices()
            result.success(true)
          }
          BluetoothProfile.STATE_DISCONNECTED -> {
            bluetoothGatt?.close()
            bluetoothGatt = null
            updateConnectionState("disconnected")
            updatePrinterStatus("offline")
            result.success(false)
          }
        }
      }
    }

    device.connectGatt(context, false, gattCallback)
  }

  @SuppressLint("MissingPermission")
  private fun disconnect(result: Result) {
    updateConnectionState("disconnecting")
    
    try {
      bluetoothSocket?.close()
      bluetoothSocket = null
      
      bluetoothGatt?.disconnect()
      bluetoothGatt?.close()
      bluetoothGatt = null
      
      connectedDevice = null
      updateConnectionState("disconnected")
      updatePrinterStatus("offline")
      result.success(true)
    } catch (e: Exception) {
      Log.e(TAG, "Disconnect failed", e)
      result.success(false)
    }
  }

  private fun printText(text: String, settings: Map<String, Any>?, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      updatePrinterStatus("busy")
      
      val escPos = StringBuilder()
      escPos.append("\u001B@") // Initialize
      escPos.append(text)
      escPos.append("\n\n\n")
      
      sendDataToPrinter(escPos.toString().toByteArray(), result)
    } catch (e: Exception) {
      Log.e(TAG, "Print text failed", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }

  private fun printImage(imageData: ByteArray, width: Int?, height: Int?, settings: Map<String, Any>?, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      updatePrinterStatus("busy")
      
      val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
      val escPosData = convertBitmapToEscPos(bitmap, width, height)
      
      sendDataToPrinter(escPosData, result)
    } catch (e: Exception) {
      Log.e(TAG, "Print image failed", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }

  private fun printJob(text: String, imageData: ByteArray?, width: Int?, height: Int?, settings: Map<String, Any>?, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      updatePrinterStatus("busy")
      
      val escPos = StringBuilder()
      escPos.append("\u001B@") // Initialize
      
      if (text.isNotEmpty()) {
        escPos.append(text)
        escPos.append("\n")
      }
      
      val finalData = if (imageData != null) {
        val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
        val imageEscPos = convertBitmapToEscPos(bitmap, width, height)
        escPos.toString().toByteArray() + imageEscPos
      } else {
        escPos.toString().toByteArray()
      }
      
      sendDataToPrinter(finalData, result)
    } catch (e: Exception) {
      Log.e(TAG, "Print job failed", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }

  private fun feedPaper(lines: Int, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      val feedData = "\n".repeat(lines).toByteArray()
      sendDataToPrinter(feedData, result)
    } catch (e: Exception) {
      Log.e(TAG, "Feed paper failed", e)
      result.success(false)
    }
  }

  private fun cutPaper(result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      val cutData = byteArrayOf(0x1D, 0x56, 0x00) // ESC/POS cut command
      sendDataToPrinter(cutData, result)
    } catch (e: Exception) {
      Log.e(TAG, "Cut paper failed", e)
      result.success(false)
    }
  }

  private fun sendRawData(data: ByteArray, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    sendDataToPrinter(data, result)
  }

  private fun sendDataToPrinter(data: ByteArray, result: Result) {
    try {
      bluetoothSocket?.outputStream?.write(data)
      bluetoothSocket?.outputStream?.flush()
      
      mainHandler.postDelayed({
        updatePrinterStatus("ready")
        result.success(true)
      }, 100)
    } catch (e: IOException) {
      Log.e(TAG, "Failed to send data to printer", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }

  private fun convertBitmapToEscPos(bitmap: Bitmap, targetWidth: Int?, targetHeight: Int?): ByteArray {
    // Resize bitmap if needed
    val resizedBitmap = if (targetWidth != null && targetHeight != null) {
      Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    } else {
      bitmap
    }

    val width = resizedBitmap.width
    val height = resizedBitmap.height
    val pixels = IntArray(width * height)
    resizedBitmap.getPixels(pixels, 0, width, 0, 0, width, height)

    // Convert to ESC/POS format
    val escPosData = ArrayList<Byte>()
    
    // ESC/POS image header
    escPosData.addAll(listOf(0x1D, 0x76, 0x30, 0x00).map { it.toByte() })
    escPosData.addAll(listOf((width / 8).toByte(), 0x00.toByte()))
    escPosData.addAll(listOf(height.toByte(), (height shr 8).toByte()))

    // Convert pixels to bitmap data
    for (y in 0 until height) {
      for (x in 0 until width step 8) {
        var byte = 0
        for (bit in 0 until 8) {
          if (x + bit < width) {
            val pixel = pixels[y * width + x + bit]
            val gray = (0.299 * ((pixel shr 16) and 0xFF) + 
                       0.587 * ((pixel shr 8) and 0xFF) + 
                       0.114 * (pixel and 0xFF)).toInt()
            if (gray < 128) {
              byte = byte or (0x80 shr bit)
            }
          }
        }
        escPosData.add(byte.toByte())
      }
    }

    return escPosData.toByteArray()
  }

  private fun updateConnectionState(state: String) {
    connectionState = state
    mainHandler.post {
      connectionStateSink?.success(state)
    }
  }

  private fun updatePrinterStatus(status: String) {
    printerStatus = status
    mainHandler.post {
      printerStatusSink?.success(status)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    deviceDiscoveryChannel.setStreamHandler(null)
    connectionStateChannel.setStreamHandler(null)
    printerStatusChannel.setStreamHandler(null)
    
    try {
      bluetoothSocket?.close()
      bluetoothGatt?.close()
    } catch (e: Exception) {
      Log.e(TAG, "Error closing connections", e)
    }
  }
}
