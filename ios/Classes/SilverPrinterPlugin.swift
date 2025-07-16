import Flutter
import UIKit
import CoreBluetooth

public class SilverPrinterPlugin: NSObject, FlutterPlugin {
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    private var deviceDiscoveryChannel: FlutterEventChannel?
    private var connectionStateChannel: FlutterEventChannel?
    private var printerStatusChannel: FlutterEventChannel?
    
    private var deviceDiscoverySink: FlutterEventSink?
    private var connectionStateSink: FlutterEventSink?
    private var printerStatusSink: FlutterEventSink?
    
    private var discoveredDevices: [String: [String: Any]] = [:]
    private var isScanning = false
    private var connectionState = "disconnected"
    private var printerStatus = "offline"
    
    private var pendingResult: FlutterResult?
    
    // Common service UUIDs for thermal printers
    private let printerServiceUUIDs = [
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"), // Common thermal printer service
        CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455"), // Another common service
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")  // Nordic UART service
    ]
    
    private let writeCharacteristicUUIDs = [
        CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3"),
        CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "silver_printer", binaryMessenger: registrar.messenger())
        let instance = SilverPrinterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Setup event channels
        instance.setupEventChannels(registrar: registrar)
    }
    
    private func setupEventChannels(registrar: FlutterPluginRegistrar) {
        deviceDiscoveryChannel = FlutterEventChannel(name: "silver_printer/device_discovery", binaryMessenger: registrar.messenger())
        deviceDiscoveryChannel?.setStreamHandler(DeviceDiscoveryStreamHandler { [weak self] sink in
            self?.deviceDiscoverySink = sink
        })
        
        connectionStateChannel = FlutterEventChannel(name: "silver_printer/connection_state", binaryMessenger: registrar.messenger())
        connectionStateChannel?.setStreamHandler(ConnectionStateStreamHandler { [weak self] sink in
            self?.connectionStateSink = sink
        })
        
        printerStatusChannel = FlutterEventChannel(name: "silver_printer/printer_status", binaryMessenger: registrar.messenger())
        printerStatusChannel?.setStreamHandler(PrinterStatusStreamHandler { [weak self] sink in
            self?.printerStatusSink = sink
        })
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "isBluetoothAvailable":
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: nil)
            }
            result(centralManager?.state == .poweredOn)
            
        case "requestBluetoothPermissions":
            // iOS automatically handles Bluetooth permissions
            result(true)
            
        case "startScan":
            startScan(result: result)
            
        case "stopScan":
            stopScan(result: result)
            
        case "getDiscoveredDevices":
            result(Array(discoveredDevices.values))
            
        case "getPairedDevices":
            // iOS doesn't have a concept of "paired" devices for BLE
            result([])
            
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Device ID is required", details: nil))
                return
            }
            connectToDevice(deviceId: deviceId, result: result)
            
        case "disconnect":
            disconnect(result: result)
            
        case "getConnectionState":
            result(connectionState)
            
        case "getConnectedDevice":
            if let peripheral = connectedPeripheral {
                let deviceInfo: [String: Any] = [
                    "id": peripheral.identifier.uuidString,
                    "name": peripheral.name ?? "Unknown Device",
                    "address": peripheral.identifier.uuidString,
                    "type": "ble",
                    "rssi": NSNull(),
                    "isPaired": false
                ]
                result(deviceInfo)
            } else {
                result(nil)
            }
            
        case "isConnected":
            result(connectionState == "connected")
            
        case "getPrinterStatus":
            result(printerStatus)
            
        case "printText":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Text is required", details: nil))
                return
            }
            let settings = args["settings"] as? [String: Any]
            printText(text: text, settings: settings, result: result)
            
        case "printImage":
            guard let args = call.arguments as? [String: Any],
                  let imageData = args["imageData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Image data is required", details: nil))
                return
            }
            let width = args["width"] as? Int
            let height = args["height"] as? Int
            let settings = args["settings"] as? [String: Any]
            printImage(imageData: imageData.data, width: width, height: height, settings: settings, result: result)
            
        case "printJob":
            let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
            let imageData = (call.arguments as? [String: Any])?["imageData"] as? FlutterStandardTypedData
            let width = (call.arguments as? [String: Any])?["imageWidth"] as? Int
            let height = (call.arguments as? [String: Any])?["imageHeight"] as? Int
            let settings = (call.arguments as? [String: Any])?["settings"] as? [String: Any]
            printJob(text: text, imageData: imageData?.data, width: width, height: height, settings: settings, result: result)
            
        case "feedPaper":
            let lines = (call.arguments as? [String: Any])?["lines"] as? Int ?? 1
            feedPaper(lines: lines, result: result)
            
        case "cutPaper":
            cutPaper(result: result)
            
        case "sendRawData":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Data is required", details: nil))
                return
            }
            sendRawData(data: data.data, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startScan(result: @escaping FlutterResult) {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        
        guard centralManager?.state == .poweredOn else {
            result(FlutterError(code: "BLUETOOTH_UNAVAILABLE", message: "Bluetooth is not available or enabled", details: nil))
            return
        }
        
        if isScanning {
            result(nil)
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        
        // Scan for all peripherals, not just printer services
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        result(nil)
    }
    
    private func stopScan(result: @escaping FlutterResult) {
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
        }
        result(nil)
    }
    
    private func connectToDevice(deviceId: String, result: @escaping FlutterResult) {
        guard let centralManager = centralManager else {
            result(FlutterError(code: "BLUETOOTH_UNAVAILABLE", message: "Bluetooth manager not available", details: nil))
            return
        }
        
        updateConnectionState("connecting")
        pendingResult = result
        
        let uuid = UUID(uuidString: deviceId)!
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        
        if let peripheral = peripherals.first {
            connectedPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        } else {
            updateConnectionState("disconnected")
            result(false)
        }
    }
    
    private func disconnect(result: @escaping FlutterResult) {
        updateConnectionState("disconnecting")
        
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        connectedPeripheral = nil
        writeCharacteristic = nil
        updateConnectionState("disconnected")
        updatePrinterStatus("offline")
        
        result(true)
    }
    
    private func printText(text: String, settings: [String: Any]?, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        updatePrinterStatus("busy")
        
        var escPos = Data()
        escPos.append(Data([0x1B, 0x40])) // Initialize
        escPos.append(text.data(using: .utf8) ?? Data())
        escPos.append(Data([0x0A, 0x0A, 0x0A])) // Line feeds
        
        sendDataToPrinter(data: escPos, result: result)
    }
    
    private func printImage(imageData: Data, width: Int?, height: Int?, settings: [String: Any]?, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        updatePrinterStatus("busy")
        
        guard let image = UIImage(data: imageData) else {
            updatePrinterStatus("error")
            result(false)
            return
        }
        
        let escPosData = convertImageToEscPos(image: image, targetWidth: width, targetHeight: height)
        sendDataToPrinter(data: escPosData, result: result)
    }
    
    private func printJob(text: String, imageData: Data?, width: Int?, height: Int?, settings: [String: Any]?, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        updatePrinterStatus("busy")
        
        var escPos = Data()
        escPos.append(Data([0x1B, 0x40])) // Initialize
        
        if !text.isEmpty {
            escPos.append(text.data(using: .utf8) ?? Data())
            escPos.append(Data([0x0A])) // Line feed
        }
        
        if let imageData = imageData, let image = UIImage(data: imageData) {
            let imageEscPos = convertImageToEscPos(image: image, targetWidth: width, targetHeight: height)
            escPos.append(imageEscPos)
        }
        
        sendDataToPrinter(data: escPos, result: result)
    }
    
    private func feedPaper(lines: Int, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        let feedData = Data(repeating: 0x0A, count: lines)
        sendDataToPrinter(data: feedData, result: result)
    }
    
    private func cutPaper(result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        let cutData = Data([0x1D, 0x56, 0x00]) // ESC/POS cut command
        sendDataToPrinter(data: cutData, result: result)
    }
    
    private func sendRawData(data: Data, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        sendDataToPrinter(data: data, result: result)
    }
    
    private func sendDataToPrinter(data: Data, result: @escaping FlutterResult) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            updatePrinterStatus("error")
            result(false)
            return
        }
        
        // Send data in chunks to avoid overwhelming the printer (iOS BLE optimization)
        let chunkSize = 20  // Small chunks for better reliability
        var offset = 0
        
        func sendNextChunk() {
            if offset < data.count {
                let endIndex = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<endIndex)
                
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                offset = endIndex
                
                // Small delay between chunks for iOS optimization
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    sendNextChunk()
                }
            } else {
                // All chunks sent
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updatePrinterStatus("ready")
                    result(true)
                }
            }
        }
        
        sendNextChunk()
    }
    
    private func convertImageToEscPos(image: UIImage, targetWidth: Int?, targetHeight: Int?) -> Data {
        // Resize image if needed for better performance
        let resizedImage: UIImage
        if let targetWidth = targetWidth, let targetHeight = targetHeight {
            resizedImage = resizeImage(image: image, targetSize: CGSize(width: targetWidth, height: targetHeight))
        } else {
            // Default to printer-friendly size
            resizedImage = resizeImage(image: image, targetSize: CGSize(width: 384, height: 384))
        }
        
        guard let cgImage = resizedImage.cgImage else { return Data() }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width
        let totalBytes = height * bytesPerRow
        
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var escPosData = Data()
        
        // ESC/POS image header
        escPosData.append(Data([0x1D, 0x76, 0x30, 0x00]))
        escPosData.append(Data([UInt8(width / 8), 0x00]))
        escPosData.append(Data([UInt8(height & 0xFF), UInt8(height >> 8)]))
        
        // Convert pixels to bitmap data
        for y in 0..<height {
            for x in stride(from: 0, to: width, by: 8) {
                var byte: UInt8 = 0
                for bit in 0..<8 {
                    if x + bit < width {
                        let pixel = pixels[y * width + x + bit]
                        if pixel < 128 {
                            byte |= (0x80 >> bit)
                        }
                    }
                }
                escPosData.append(byte)
            }
        }
        
        return escPosData
    }
    
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    private func updateConnectionState(_ state: String) {
        connectionState = state
        DispatchQueue.main.async {
            self.connectionStateSink?(state)
        }
    }
    
    private func updatePrinterStatus(_ status: String) {
        printerStatus = status
        DispatchQueue.main.async {
            self.printerStatusSink?(status)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension SilverPrinterPlugin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Handle state changes if needed
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceInfo: [String: Any] = [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? "Unknown Device",
            "address": peripheral.identifier.uuidString,
            "type": "ble",
            "rssi": RSSI.intValue,
            "isPaired": false
        ]
        
        discoveredDevices[peripheral.identifier.uuidString] = deviceInfo
        
        DispatchQueue.main.async {
            self.deviceDiscoverySink?(deviceInfo)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateConnectionState("connected")
        updatePrinterStatus("ready")
        peripheral.discoverServices(nil)
        pendingResult?(true)
        pendingResult = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        updateConnectionState("disconnected")
        updatePrinterStatus("offline")
        pendingResult?(false)
        pendingResult = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateConnectionState("disconnected")
        updatePrinterStatus("offline")
        connectedPeripheral = nil
        writeCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate
extension SilverPrinterPlugin: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                break
            } else if characteristic.properties.contains(.write) {
                writeCharacteristic = characteristic
            }
        }
    }
}

// MARK: - Stream Handlers
class DeviceDiscoveryStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenCallback: (FlutterEventSink?) -> Void
    
    init(onListen: @escaping (FlutterEventSink?) -> Void) {
        self.onListenCallback = onListen
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListenCallback(nil)
        return nil
    }
}

class ConnectionStateStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenCallback: (FlutterEventSink?) -> Void
    
    init(onListen: @escaping (FlutterEventSink?) -> Void) {
        self.onListenCallback = onListen
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListenCallback(nil)
        return nil
    }
}

class PrinterStatusStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenCallback: (FlutterEventSink?) -> Void
    
    init(onListen: @escaping (FlutterEventSink?) -> Void) {
        self.onListenCallback = onListen
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListenCallback(nil)
        return nil
    }
}
