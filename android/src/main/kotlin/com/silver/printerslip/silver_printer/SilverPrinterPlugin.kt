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
  private var currentMtu = 23 // Default BLE MTU
  private var pendingWriteResult: Result? = null
  private var writeData: ByteArray? = null
  private var writeOffset = 0
  private var writeChunkSize = 20
  private var writeCharacteristic: BluetoothGattCharacteristic? = null

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
        getPrinterStatus(result)
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
      "printHybrid" -> {
        val items = call.argument<List<Map<String, Any>>>("items")
        val settings = call.argument<Map<String, Any>>("settings")
        if (items != null) {
          printHybrid(items, settings, result)
        } else {
          result.error("INVALID_ARGUMENT", "Items are required", null)
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
          
          // Get device name from scan record if not available from device object
          val deviceName = device.name ?: scanResult.scanRecord?.deviceName ?: "Unknown Device"
          
          val deviceInfo = mapOf<String, Any>(
            "id" to device.address,
            "name" to deviceName,
            "address" to device.address,
            "type" to "ble",
            "rssi" to scanResult.rssi,
            "isPaired" to false
          )
          
          Log.d(TAG, "Found BLE device: $deviceName (${device.address}) RSSI: ${scanResult.rssi}")
          
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
    
    // Reset MTU to default when starting new connection
    currentMtu = 23

    try {
      val device = bluetoothAdapter!!.getRemoteDevice(deviceId)
      
      // Try BLE first (no pairing required)
      connectBLE(device, result)
      
    } catch (e: Exception) {
      Log.e(TAG, "Connection failed", e)
      updateConnectionState("disconnected")
      result.success(false)
    }
  }

  @SuppressLint("MissingPermission")
  private fun connectBLE(device: BluetoothDevice, result: Result) {
    var callbackHandled = false
    
    // Set connection timeout
    val connectionTimeout = Runnable {
      if (!callbackHandled) {
        callbackHandled = true
        Log.d(TAG, "BLE connection timeout for device: ${device.address}")
        bluetoothGatt?.close()
        bluetoothGatt = null
        tryClassicBluetooth(device, result)
      }
    }
    mainHandler.postDelayed(connectionTimeout, 8000) // 8 second timeout
    
    val gattCallback = object : BluetoothGattCallback() {
      override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
        if (callbackHandled) return
        
        when (newState) {
          BluetoothProfile.STATE_CONNECTED -> {
            if (!callbackHandled) {
              callbackHandled = true
              mainHandler.removeCallbacks(connectionTimeout)
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
          }
          BluetoothProfile.STATE_DISCONNECTED -> {
            if (!callbackHandled) {
              callbackHandled = true
              mainHandler.removeCallbacks(connectionTimeout)
              bluetoothGatt?.close()
              bluetoothGatt = null
              // If BLE fails, try Classic Bluetooth as fallback
              tryClassicBluetooth(device, result)
            }
          }
        }
      }
      
      override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
        if (status == BluetoothGatt.GATT_SUCCESS) {
          Log.d(TAG, "Services discovered for device: ${device.address}")
          // Look for printer services
          gatt?.services?.forEach { service ->
            Log.d(TAG, "Service found: ${service.uuid}")
            service.characteristics?.forEach { characteristic ->
              Log.d(TAG, "Characteristic found: ${characteristic.uuid}")
            }
          }
          
          // Request larger MTU for faster data transfer
          gatt?.requestMtu(512)
        }
      }
      
      override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
        if (status == BluetoothGatt.GATT_SUCCESS) {
          currentMtu = mtu
          Log.d(TAG, "MTU changed to: $mtu for device: ${device.address}")
        } else {
          Log.d(TAG, "MTU change failed with status: $status")
        }
      }
      
    }

    // Use auto-connect false for faster connection
    device.connectGatt(context, false, gattCallback)
  }

  @SuppressLint("MissingPermission")
  private fun tryClassicBluetooth(device: BluetoothDevice, result: Result) {
    try {
      // Only try Classic if device is already paired (to avoid pairing dialog)
      if (device.bondState == BluetoothDevice.BOND_BONDED) {
        // Set connection timeout for Classic Bluetooth too
        val classicTimeout = Runnable {
          Log.d(TAG, "Classic Bluetooth connection timeout for device: ${device.address}")
          try {
            bluetoothSocket?.close()
            bluetoothSocket = null
          } catch (e: Exception) {
            Log.e(TAG, "Error closing socket on timeout", e)
          }
          updateConnectionState("disconnected")
          updatePrinterStatus("offline")
          result.success(false)
        }
        mainHandler.postDelayed(classicTimeout, 10000) // 10 second timeout
        
        bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        bluetoothSocket?.connect()
        
        // Cancel timeout if successful
        mainHandler.removeCallbacks(classicTimeout)
        
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
          return
        }
      }
    } catch (e: Exception) {
      Log.e(TAG, "Classic Bluetooth connection failed", e)
    }
    
    // Both BLE and Classic failed
    updateConnectionState("disconnected")
    updatePrinterStatus("offline")
    result.success(false)
  }

  private fun getPrinterStatus(result: Result) {
    // Check actual connection status
    val isActuallyConnected = when {
      bluetoothSocket?.isConnected == true -> true
      bluetoothGatt?.let { gatt ->
        // For BLE, we need to check if it's still connected
        try {
          // Try to read services to test connection
          val services = gatt.services
          services != null && services.isNotEmpty()
        } catch (e: Exception) {
          false
        }
      } == true -> true
      else -> false
    }
    
    if (!isActuallyConnected && connectionState == "connected") {
      // Connection was lost, update state
      updateConnectionState("disconnected")
      updatePrinterStatus("offline")
      connectedDevice = null
      
      // Clean up connections
      try {
        bluetoothSocket?.close()
        bluetoothGatt?.close()
      } catch (e: Exception) {
        Log.e(TAG, "Error closing connections", e)
      }
      bluetoothSocket = null
      bluetoothGatt = null
    }
    
    result.success(printerStatus)
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
      
      val escPosCommands = mutableListOf<Byte>()
      
      // Initialize printer
      escPosCommands.addAll(listOf(0x1B.toByte(), 0x40.toByte())) // ESC @
      
      // Process settings
      settings?.let { s ->
        // Font size and bold
        val fontSize = s["fontSize"] as? String ?: "normal"
        val bold = s["bold"] as? Boolean ?: false
        
        var fontCommand = 0x00
        when (fontSize) {
          "large" -> fontCommand = fontCommand or 0x20 // Double height
          "extraLarge" -> fontCommand = fontCommand or 0x30 // Double width + height
        }
        if (bold) {
          fontCommand = fontCommand or 0x08 // Bold
        }
        
        if (fontCommand != 0x00) {
          escPosCommands.addAll(listOf(0x1B.toByte(), 0x21.toByte(), fontCommand.toByte())) // ESC !
        }
        
        // Alignment
        val alignment = s["alignment"] as? String ?: "left"
        when (alignment) {
          "center" -> escPosCommands.addAll(listOf(0x1B.toByte(), 0x61.toByte(), 0x01.toByte())) // ESC a 1
          "right" -> escPosCommands.addAll(listOf(0x1B.toByte(), 0x61.toByte(), 0x02.toByte())) // ESC a 2
          else -> escPosCommands.addAll(listOf(0x1B.toByte(), 0x61.toByte(), 0x00.toByte())) // ESC a 0 (left)
        }
      }
      
      // Add text with proper encoding for Thai text
      val encodedText = try {
        // Try TIS-620 encoding first (Thai standard)
        text.toByteArray(Charsets.UTF_8)
      } catch (e: Exception) {
        // Fallback to UTF-8 if TIS-620 fails
        text.toByteArray(Charsets.UTF_8)
      }
      
      // Add ESC/POS command to set code page for Thai characters
      escPosCommands.addAll(listOf(0x1B.toByte(), 0x74.toByte(), 0x11.toByte())) // ESC t 17 (CP874/TIS-620)
      
      escPosCommands.addAll(encodedText.toList())
      
      // Reset alignment and font after text (optional)
      escPosCommands.addAll(listOf(0x1B.toByte(), 0x21.toByte(), 0x00.toByte())) // Reset font
      escPosCommands.addAll(listOf(0x1B.toByte(), 0x61.toByte(), 0x00.toByte())) // Reset alignment to left
      
      sendDataToPrinter(escPosCommands.toByteArray(), result)
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
      
      // Add feed lines if specified
      val feedLines = settings?.get("feedLines") as? Int ?: 0
      val finalData = if (feedLines > 0) {
        escPosData + generateFeedLines(feedLines)
      } else {
        escPosData
      }
      
      sendDataToPrinter(finalData, result)
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

  private fun printHybrid(items: List<Map<String, Any>>, settings: Map<String, Any>?, result: Result) {
    if (connectionState != "connected") {
      result.error("NOT_CONNECTED", "No device connected", null)
      return
    }

    try {
      updatePrinterStatus("busy")
      
      val escPosData = ArrayList<Byte>()
      escPosData.addAll(listOf(0x1B, 0x40).map { it.toByte() }) // Initialize printer
      
      for (item in items) {
        val type = item["type"] as? String ?: continue
        
        when (type) {
          "text" -> {
            val content = item["content"] as? String ?: ""
            val alignment = item["alignment"] as? String ?: "left"
            val size = item["size"] as? String ?: "normal"
            val bold = item["bold"] as? Boolean ?: false
            val underline = item["underline"] as? Boolean ?: false
            
            // Add text formatting commands
            when (alignment) {
              "center" -> escPosData.addAll(listOf(0x1B, 0x61, 0x01).map { it.toByte() })
              "right" -> escPosData.addAll(listOf(0x1B, 0x61, 0x02).map { it.toByte() })
              else -> escPosData.addAll(listOf(0x1B, 0x61, 0x00).map { it.toByte() }) // left
            }
            
            // Text size
            when (size) {
              "small" -> escPosData.addAll(listOf(0x1D, 0x21, 0x00).map { it.toByte() })
              "large" -> escPosData.addAll(listOf(0x1D, 0x21, 0x11).map { it.toByte() })
              "extraLarge" -> escPosData.addAll(listOf(0x1D, 0x21, 0x22).map { it.toByte() })
              else -> escPosData.addAll(listOf(0x1D, 0x21, 0x00).map { it.toByte() }) // normal
            }
            
            // Bold
            if (bold) {
              escPosData.addAll(listOf(0x1B, 0x45, 0x01).map { it.toByte() })
            }
            
            // Underline
            if (underline) {
              escPosData.addAll(listOf(0x1B, 0x2D, 0x01).map { it.toByte() })
            }
            
            // Add text content with proper encoding for Thai text
            val encodedContent = try {
              content.toByteArray(Charsets.UTF_8)
            } catch (e: Exception) {
              content.toByteArray(Charsets.UTF_8)
            }
            
            // Add ESC/POS command to set code page for Thai characters before text
            escPosData.addAll(listOf(0x1B, 0x74, 0x11).map { it.toByte() }) // ESC t 17 (CP874/TIS-620)
            
            escPosData.addAll(encodedContent.toList())
            escPosData.add(0x0A.toByte()) // Line feed
            
            // Reset formatting
            escPosData.addAll(listOf(0x1B, 0x45, 0x00).map { it.toByte() }) // Bold off
            escPosData.addAll(listOf(0x1B, 0x2D, 0x00).map { it.toByte() }) // Underline off
            escPosData.addAll(listOf(0x1D, 0x21, 0x00).map { it.toByte() }) // Normal size
            escPosData.addAll(listOf(0x1B, 0x61, 0x00).map { it.toByte() }) // Left align
          }
          
          "image" -> {
            val imageData = item["imageData"] as? ByteArray
            if (imageData != null) {
              val width = item["width"] as? Int
              val height = item["height"] as? Int
              val alignment = item["alignment"] as? String ?: "center"
              
              val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
              val imageEscPos = convertBitmapToEscPos(bitmap, width, height)
              escPosData.addAll(imageEscPos.toList())
            }
          }
          
          "lineFeed" -> {
            val lines = item["lines"] as? Int ?: 1
            repeat(lines) {
              escPosData.add(0x0A.toByte())
            }
          }
          
          "divider" -> {
            val character = item["character"] as? String ?: "-"
            val width = item["width"] as? Int ?: 32
            val dividerText = character.repeat(width)
            escPosData.addAll(listOf(0x1B, 0x61, 0x01).map { it.toByte() }) // Center
            escPosData.addAll(dividerText.toByteArray().toList())
            escPosData.add(0x0A.toByte()) // Line feed
            escPosData.addAll(listOf(0x1B, 0x61, 0x00).map { it.toByte() }) // Left align
          }
        }
      }
      
      // Add final feed lines from settings if specified
      val feedLines = settings?.get("feedLines") as? Int ?: 0
      if (feedLines > 0) {
        escPosData.addAll(generateFeedLines(feedLines).toList())
      }
      
      sendDataToPrinter(escPosData.toByteArray(), result)
    } catch (e: Exception) {
      Log.e(TAG, "Print hybrid failed", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }

  private fun sendDataToPrinter(data: ByteArray, result: Result) {
    try {
      // Try BLE first if connected via BLE
      if (bluetoothGatt != null) {
        sendDataViaBLE(data, result)
      } else if (bluetoothSocket != null) {
        // Classic Bluetooth
        bluetoothSocket?.outputStream?.write(data)
        bluetoothSocket?.outputStream?.flush()
        
        mainHandler.postDelayed({
          updatePrinterStatus("ready")
          result.success(true)
        }, 100)
      } else {
        Log.e(TAG, "No active connection to send data")
        result.success(false)
      }
    } catch (e: IOException) {
      Log.e(TAG, "Failed to send data to printer", e)
      updatePrinterStatus("error")
      result.success(false)
    }
  }
  
  @SuppressLint("MissingPermission")
  private fun sendDataViaBLE(data: ByteArray, result: Result) {
    bluetoothGatt?.let { gatt ->
      // Find printer service - try common printer service UUIDs
      val printerServiceUuids = listOf(
        UUID.fromString("00001101-0000-1000-8000-00805f9b34fb"), // SPP
        UUID.fromString("0000180A-0000-1000-8000-00805f9b34fb"), // Device Information
        UUID.fromString("49535343-fe7d-4ae5-8fa9-9fafd205e455"), // Common printer service
        UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")  // Nordic UART service
      )
      
      var foundCharacteristic: BluetoothGattCharacteristic? = null
      
      // Look for writable characteristic - prioritize specific printer services
      for (service in gatt.services) {
        Log.d(TAG, "Checking service: ${service.uuid}")
        for (characteristic in service.characteristics) {
          val props = characteristic.properties
          Log.d(TAG, "Characteristic ${characteristic.uuid} has properties: $props")
          
          if (props and BluetoothGattCharacteristic.PROPERTY_WRITE != 0 ||
              props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
            foundCharacteristic = characteristic
            Log.d(TAG, "Selected characteristic: ${characteristic.uuid} with properties: $props")
            break
          }
        }
        if (foundCharacteristic != null) break
      }
      
      if (foundCharacteristic != null) {
        // Use adaptive chunk size based on characteristic properties
        val chunkSize: Int
        val useWithoutResponse: Boolean
        val delay: Int
        
        if (foundCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
          chunkSize = 500
          useWithoutResponse = true
          delay = 20
          Log.d(TAG, "Using writeWithoutResponse with chunk size: $chunkSize")
        } else {
          chunkSize = 220
          useWithoutResponse = false
          delay = 25
          Log.d(TAG, "Using write with response with chunk size: $chunkSize")
        }
        
        Log.d(TAG, "Starting BLE print with MTU: $currentMtu, chunk size: $chunkSize")
        Log.d(TAG, "Characteristic properties - Write: ${foundCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0}, WriteWithoutResponse: ${foundCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0}")
        
        // Send data in chunks with adaptive approach
        sendDataInChunks(foundCharacteristic, data, chunkSize, useWithoutResponse, delay, result)
      } else {
        Log.e(TAG, "No writable characteristic found")
        result.success(false)
      }
    } ?: run {
      Log.e(TAG, "No GATT connection available")
      result.success(false)
    }
  }
  
  @SuppressLint("MissingPermission")
  private fun sendDataInChunks(
    characteristic: BluetoothGattCharacteristic, 
    data: ByteArray, 
    chunkSize: Int, 
    useWithoutResponse: Boolean, 
    delay: Int, 
    result: Result
  ) {
    Thread {
      try {
        val totalChunks = (data.size.toFloat() / chunkSize).let { kotlin.math.ceil(it).toInt() }
        val progressStep = maxOf(1, totalChunks / 10) // แสดง progress ทุก 10%
        
        Log.d(TAG, "Total chunks to send: $totalChunks")
        
        for (i in data.indices step chunkSize) {
          val end = minOf(i + chunkSize, data.size)
          val chunk = data.sliceArray(i until end)
          val currentChunk = (i / chunkSize) + 1
          
          // แสดง progress เฉพาะบางช่วง เพื่อลด logging overhead
          if (currentChunk == 1 || currentChunk % progressStep == 0 || currentChunk == totalChunks) {
            Log.d(TAG, "Progress: $currentChunk/$totalChunks (${((currentChunk.toFloat() / totalChunks) * 100).toInt()}%)")
          }
          
          try {
            // Set write type based on characteristic capability
            characteristic.writeType = if (useWithoutResponse) {
              BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
              BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            
            characteristic.value = chunk
            val success = bluetoothGatt?.writeCharacteristic(characteristic) ?: false
            
            if (!success) {
              Log.e(TAG, "Failed to write chunk $currentChunk")
              throw Exception("Write failed for chunk $currentChunk")
            }
            
            // ลดเวลาหน่วงลงมาก และใช้ adaptive delay
            if (currentChunk % 5 == 0) {
              // หน่วงเฉพาะทุก 5 chunks เพื่อให้เครื่องปริ้นได้พัก
              Thread.sleep((delay * 2).toLong())
            } else {
              Thread.sleep(delay.toLong())
            }
            
          } catch (e: Exception) {
            Log.e(TAG, "Error sending chunk $currentChunk: $e")
            // ถ้า error ให้ลองส่งใหม่ 1 ครั้ง
            try {
              Thread.sleep((delay * 3).toLong())
              characteristic.value = chunk
              val retrySuccess = bluetoothGatt?.writeCharacteristic(characteristic) ?: false
              if (retrySuccess) {
                Log.d(TAG, "Retry successful for chunk $currentChunk")
              } else {
                throw Exception("Retry failed for chunk $currentChunk")
              }
            } catch (retryError: Exception) {
              Log.e(TAG, "Retry failed for chunk $currentChunk: $retryError")
              mainHandler.post {
                updatePrinterStatus("error")
                result.success(false)
              }
              return@Thread
            }
          }
        }
        
        Log.d(TAG, "All chunks sent successfully!")
        mainHandler.post {
          updatePrinterStatus("ready")
          result.success(true)
        }
        
      } catch (e: Exception) {
        Log.e(TAG, "BLE print failed: $e")
        mainHandler.post {
          updatePrinterStatus("error")
          result.success(false)
        }
      }
    }.start()
  }
  
  private fun resetWriteState() {
    writeData = null
    writeOffset = 0
    writeChunkSize = 20
    writeCharacteristic = null
    pendingWriteResult = null
  }

  private fun convertBitmapToEscPos(bitmap: Bitmap, targetWidth: Int?, targetHeight: Int?): ByteArray {
    // Calculate optimal size to prevent OOM with special handling for tall images
    val originalWidth = bitmap.width
    val originalHeight = bitmap.height
    val aspectRatio = originalHeight.toFloat() / originalWidth.toFloat()
    
    // Use smaller max dimension for very tall images (aspect ratio > 2)
    val maxDimension = if (aspectRatio > 2.0f) {
      400 // Smaller for tall images like receipts
    } else {
      600 // Standard size for normal images
    }
    
    // Calculate scaling factor to fit within memory constraints
    val scaleFactor = minOf(
      maxDimension.toFloat() / originalWidth,
      maxDimension.toFloat() / originalHeight,
      1.0f
    )
    
    val finalWidth = if (targetWidth != null) {
      // Ensure width is divisible by 8 for ESC/POS compatibility
      (targetWidth / 8) * 8
    } else {
      // Default thermal printer width (58mm = 384px, 80mm = 576px)
      384 // Default to 58mm paper
    }
    
    val finalHeight = if (targetHeight != null) {
      minOf(targetHeight, (originalHeight * scaleFactor).toInt())
    } else {
      // Calculate height proportionally to maintain aspect ratio with final width
      val aspectRatio = originalHeight.toFloat() / originalWidth.toFloat()
      (finalWidth * aspectRatio).toInt()
    }
    
    // Create scaled bitmap with memory optimization and better quality
    val resizedBitmap = if (finalWidth != originalWidth || finalHeight != originalHeight) {
      Bitmap.createScaledBitmap(bitmap, finalWidth, finalHeight, true)
    } else {
      bitmap
    }
    
    // Ensure bitmap is in ARGB_8888 format for better color processing
    val processedBitmap = if (resizedBitmap.config != Bitmap.Config.ARGB_8888) {
      resizedBitmap.copy(Bitmap.Config.ARGB_8888, false)
    } else {
      resizedBitmap
    }

    val width = processedBitmap.width
    val height = processedBitmap.height
    
    // Process image in chunks to avoid OOM
    val chunkHeight = minOf(100, height) // Process 100 rows at a time
    val escPosData = ArrayList<Byte>()
    
    // Add center alignment command
    escPosData.addAll(listOf(0x1B, 0x61, 0x01).map { it.toByte() }) // ESC a 1 (center)
    
    // ESC/POS image header
    escPosData.addAll(listOf(0x1D, 0x76, 0x30, 0x00).map { it.toByte() })
    escPosData.addAll(listOf((width / 8).toByte(), 0x00.toByte()))
    escPosData.addAll(listOf(height.toByte(), (height shr 8).toByte()))
    
    // Process bitmap in chunks
    for (startY in 0 until height step chunkHeight) {
      val endY = minOf(startY + chunkHeight, height)
      val chunkPixels = IntArray(width * (endY - startY))
      processedBitmap.getPixels(chunkPixels, 0, width, 0, startY, width, endY - startY)
      
      // Convert chunk to bitmap data
      for (y in 0 until (endY - startY)) {
        for (x in 0 until width step 8) {
          var byte = 0
          for (bit in 0 until 8) {
            if (x + bit < width) {
              val pixel = chunkPixels[y * width + x + bit]
              val red = (pixel shr 16) and 0xFF
              val green = (pixel shr 8) and 0xFF
              val blue = pixel and 0xFF
              val gray = (0.299 * red + 0.587 * green + 0.114 * blue).toInt()
              
              // Improve threshold for better contrast
              if (gray < 180) { // Increase threshold from 128 to 180
                byte = byte or (1 shl (7 - bit))
              }
            }
          }
          escPosData.add(byte.toByte())
        }
      }
    }
    
    // Reset alignment to left
    escPosData.addAll(listOf(0x1B, 0x61, 0x00).map { it.toByte() }) // ESC a 0 (left)
    
    // Clean up
    if (processedBitmap != resizedBitmap) {
      processedBitmap.recycle()
    }
    if (resizedBitmap != bitmap) {
      resizedBitmap.recycle()
    }
    
    return escPosData.toByteArray()
  }

  private fun generateFeedLines(lines: Int): ByteArray {
    val feedData = ArrayList<Byte>()
    // ESC/POS line feed command (0x0A = LF)
    repeat(lines) {
      feedData.add(0x0A.toByte())
    }
    return feedData.toByteArray()
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
