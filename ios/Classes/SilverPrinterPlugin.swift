import Flutter
import UIKit
import CoreBluetooth
import ExternalAccessory

public class SilverPrinterPlugin: NSObject, FlutterPlugin {
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    // For optimized chunked writing
    private var pendingWriteData: Data?
    private var writeOffset = 0
    private var writeChunkSize = 20
    private var pendingWriteResult: FlutterResult?
    
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
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART service
        CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB"), // SPP service
        CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB"), // Device Information service
        CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB"), // Battery service
        CBUUID(string: "00001800-0000-1000-8000-00805F9B34FB"), // Generic Access service
        CBUUID(string: "00001801-0000-1000-8000-00805F9B34FB")  // Generic Attribute service
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
                // Give some time for CBCentralManager to initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    result(self.centralManager?.state == .poweredOn)
                }
            } else {
                result(centralManager?.state == .poweredOn)
            }
            
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
            
        case "printHybrid":
            guard let args = call.arguments as? [String: Any],
                  let items = args["items"] as? [[String: Any]] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Items are required", details: nil))
                return
            }
            let settings = args["settings"] as? [String: Any]
            printHybrid(items: items, settings: settings, result: result)
            
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
        
        // Scan for all peripherals with options to find more devices
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,  // Don't allow duplicates initially
            CBCentralManagerScanOptionSolicitedServiceUUIDsKey: []
        ]
        
        print("iOS: Starting BLE scan...")
        centralManager?.scanForPeripherals(withServices: nil, options: options)
        
        // Also try scanning for specific printer services after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("iOS: Starting targeted printer service scan...")
            self.centralManager?.scanForPeripherals(withServices: self.printerServiceUUIDs, options: options)
        }
        
        // Try scanning with minimal filtering after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("iOS: Starting minimal filter scan...")
            let minimalOptions: [String: Any] = [:]
            self.centralManager?.scanForPeripherals(withServices: nil, options: minimalOptions)
        }
        
        // Try a more aggressive scan with duplicates after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("iOS: Starting aggressive scan with duplicates...")
            let aggressiveOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            self.centralManager?.scanForPeripherals(withServices: nil, options: aggressiveOptions)
        }
        
        // Try to retrieve previously connected peripherals after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            print("iOS: Trying to retrieve previously connected peripherals...")
            let connectedPeripherals = self.centralManager?.retrieveConnectedPeripherals(withServices: self.printerServiceUUIDs) ?? []
            print("iOS: Found \(connectedPeripherals.count) connected peripherals")
            
            for peripheral in connectedPeripherals {
                print("iOS: Connected peripheral: \(peripheral.name ?? "Unknown") (\(peripheral.identifier.uuidString))")
                self.addPeripheralToDiscoveredList(peripheral: peripheral, rssi: -50) // Default RSSI
            }
            
            // Try to find devices that might be previously discovered but not connected
            // This is a more aggressive approach for stubborn devices
            print("iOS: Trying alternative discovery methods...")
            
            // Log current iOS Bluetooth state
            print("iOS: Current Bluetooth state: \(self.centralManager?.state.rawValue ?? -1)")
            
            // Try scanning with no filters and extended options
            let extendedOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: self.printerServiceUUIDs
            ]
            self.centralManager?.scanForPeripherals(withServices: nil, options: extendedOptions)
            
            // Try to find MFi accessories
            print("iOS: Checking for MFi accessories...")
            let accessories = EAAccessoryManager.shared().connectedAccessories
            print("iOS: Found \(accessories.count) MFi accessories")
            
            for accessory in accessories {
                print("iOS: MFi accessory: \(accessory.name) - \(accessory.manufacturer)")
                if accessory.name.contains("KPrinter") || accessory.name.contains("77a7") {
                    print("iOS: Found KPrinter via MFi!")
                    // Create a fake peripheral entry for MFi device
                    let deviceInfo: [String: Any] = [
                        "id": "mfi_\(accessory.connectionID)",
                        "name": accessory.name,
                        "address": "MFi:\(accessory.connectionID)",
                        "type": "mfi",
                        "rssi": -50,
                        "isPaired": true
                    ]
                    
                    self.discoveredDevices["mfi_\(accessory.connectionID)"] = deviceInfo
                    
                    DispatchQueue.main.async {
                        self.deviceDiscoverySink?(deviceInfo)
                    }
                }
            }
        }
        
        // Final attempt with long duration scan after 6 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            print("iOS: Final attempt - Long duration scan...")
            let finalOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            self.centralManager?.scanForPeripherals(withServices: nil, options: finalOptions)
            
            // Stop this final scan after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                print("iOS: Stopping final scan")
                self.centralManager?.stopScan()
            }
        }
        
        // Try to manually add KPrinter if we know it exists but can't discover it
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            print("iOS: Adding manual KPrinter entry for stubborn device...")
            
            // Create a manual entry that user can try to connect to
            let manualDeviceInfo: [String: Any] = [
                "id": "manual_kprinter_77a7",
                "name": "KPrinter_77a7 (Manual)",
                "address": "XX:XX:XX:XX:77:A7",
                "type": "ble_manual",
                "rssi": -60,
                "isPaired": false
            ]
            
            self.discoveredDevices["manual_kprinter_77a7"] = manualDeviceInfo
            
            DispatchQueue.main.async {
                self.deviceDiscoverySink?(manualDeviceInfo)
            }
        }
        
        result(nil)
    }
    
    private func addPeripheralToDiscoveredList(peripheral: CBPeripheral, rssi: Int) {
        // Get device name from peripheral
        let deviceName = peripheral.name ?? "Unknown Device"
        
        // Convert iOS UUID to more readable format (last 12 characters)
        let uuidString = peripheral.identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let shortAddress = String(uuidString.suffix(12)).uppercased()
        let formattedAddress = stride(from: 0, to: shortAddress.count, by: 2).map {
            let start = shortAddress.index(shortAddress.startIndex, offsetBy: $0)
            let end = shortAddress.index(start, offsetBy: 2)
            return String(shortAddress[start..<end])
        }.joined(separator: ":")
        
        let deviceInfo: [String: Any] = [
            "id": peripheral.identifier.uuidString,
            "name": deviceName,
            "address": formattedAddress,
            "type": "ble",
            "rssi": rssi,
            "isPaired": false
        ]
        
        // Only add if not already in list
        if discoveredDevices[peripheral.identifier.uuidString] == nil {
            discoveredDevices[peripheral.identifier.uuidString] = deviceInfo
            
            DispatchQueue.main.async {
                self.deviceDiscoverySink?(deviceInfo)
            }
        }
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
        
        // Handle manual KPrinter connection attempt
        if deviceId == "manual_kprinter_77a7" {
            print("iOS: Attempting manual KPrinter connection...")
            
            // Try to find any peripheral with KPrinter in the name
            // First stop current scanning
            centralManager.stopScan()
            
            // Start a targeted scan for KPrinter
            let targetedOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            
            centralManager.scanForPeripherals(withServices: nil, options: targetedOptions)
            
            // Give it 5 seconds to find and connect
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                print("iOS: Manual connection timeout")
                self.updateConnectionState("disconnected")
                result(false)
            }
            
            return
        }
        
        // Normal connection flow
        guard let uuid = UUID(uuidString: deviceId) else {
            updateConnectionState("disconnected")
            result(false)
            return
        }
        
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
        escPos.append(Data([0x1B, 0x40])) // Initialize printer
        escPos.append(Data([0x1B, 0x21, 0x00])) // Reset font to normal
        escPos.append(Data([0x1B, 0x61, 0x00])) // Left alignment
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
        
        let escPosData = convertImageToEscPos(image: image, targetWidth: width, targetHeight: height, settings: settings)
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
            let imageEscPos = convertImageToEscPos(image: image, targetWidth: width, targetHeight: height, settings: settings)
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
    
    private func printHybrid(items: [[String: Any]], settings: [String: Any]?, result: @escaping FlutterResult) {
        guard connectionState == "connected" else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        
        updatePrinterStatus("busy")
        
        var escPosData = Data()
        escPosData.append(Data([0x1B, 0x40])) // Initialize printer
        escPosData.append(Data([0x1B, 0x21, 0x00])) // Reset font to normal
        
        for item in items {
            guard let type = item["type"] as? String else { continue }
            
            switch type {
            case "text":
                let content = item["content"] as? String ?? ""
                let alignment = item["alignment"] as? String ?? "left"
                let size = item["size"] as? String ?? "normal"
                let bold = item["bold"] as? Bool ?? false
                let underline = item["underline"] as? Bool ?? false
                
                // Add text formatting commands
                switch alignment {
                case "center":
                    escPosData.append(Data([0x1B, 0x61, 0x01]))
                case "right":
                    escPosData.append(Data([0x1B, 0x61, 0x02]))
                default: // left
                    escPosData.append(Data([0x1B, 0x61, 0x00]))
                }
                
                // Text size
                switch size {
                case "small":
                    escPosData.append(Data([0x1D, 0x21, 0x00]))
                case "large":
                    escPosData.append(Data([0x1D, 0x21, 0x11]))
                case "extraLarge":
                    escPosData.append(Data([0x1D, 0x21, 0x22]))
                default: // normal
                    escPosData.append(Data([0x1D, 0x21, 0x00]))
                }
                
                // Bold
                if bold {
                    escPosData.append(Data([0x1B, 0x45, 0x01]))
                }
                
                // Underline
                if underline {
                    escPosData.append(Data([0x1B, 0x2D, 0x01]))
                }
                
                // Add text content
                if let textData = content.data(using: .utf8) {
                    escPosData.append(textData)
                }
                escPosData.append(Data([0x0A])) // Line feed
                
                // Reset formatting
                escPosData.append(Data([0x1B, 0x45, 0x00])) // Bold off
                escPosData.append(Data([0x1B, 0x2D, 0x00])) // Underline off
                escPosData.append(Data([0x1D, 0x21, 0x00])) // Normal size
                escPosData.append(Data([0x1B, 0x61, 0x00])) // Left align
                
            case "image":
                if let imageData = item["imageData"] as? FlutterStandardTypedData {
                    let width = item["width"] as? Int
                    let height = item["height"] as? Int
                    let alignment = item["alignment"] as? String ?? "center"
                    
                    if let image = UIImage(data: imageData.data) {
                        let imageEscPos = convertImageToEscPos(image: image, targetWidth: width, targetHeight: height, settings: nil)
                        escPosData.append(imageEscPos)
                    }
                }
                
            case "lineFeed":
                let lines = item["lines"] as? Int ?? 1
                for _ in 0..<lines {
                    escPosData.append(Data([0x0A]))
                }
                
            case "divider":
                let character = item["character"] as? String ?? "-"
                let width = item["width"] as? Int ?? 32
                let dividerText = String(repeating: character, count: width)
                escPosData.append(Data([0x1B, 0x61, 0x01])) // Center
                if let dividerData = dividerText.data(using: .utf8) {
                    escPosData.append(dividerData)
                }
                escPosData.append(Data([0x0A])) // Line feed
                escPosData.append(Data([0x1B, 0x61, 0x00])) // Left align
                
            default:
                break
            }
        }
        
        // Add final feed lines from settings if specified
        if let settings = settings, let feedLines = settings["feedLines"] as? Int, feedLines > 0 {
            for _ in 0..<feedLines {
                escPosData.append(Data([0x0A])) // Line feed
            }
        }
        
        sendDataToPrinter(data: escPosData, result: result)
    }
    
    private func sendDataToPrinter(data: Data, result: @escaping FlutterResult) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            updatePrinterStatus("error")
            result(false)
            return
        }
        
        // Use callback-based approach like Android for maximum speed
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeChunkSize = 500  // Large chunks for no-response
            print("iOS: Using writeWithoutResponse with \(writeChunkSize) byte chunks")
        } else {
            writeChunkSize = 200  // Medium chunks for response-based
            print("iOS: Using writeWithResponse with \(writeChunkSize) byte chunks")
        }
        
        pendingWriteData = data
        writeOffset = 0
        pendingWriteResult = result
        
        print("iOS: Starting callback-based BLE print with \(data.count) bytes")
        
        // Start writing immediately
        writeNextChunk()
    }
    
    private func writeNextChunk() {
        guard let data = pendingWriteData,
              let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            print("iOS: Missing data or connection for chunk write")
            return
        }
        
        if writeOffset >= data.count {
            // All data sent
            print("iOS: BLE printing completed. Total bytes: \(data.count)")
            pendingWriteData = nil
            writeOffset = 0
            
            DispatchQueue.main.async {
                self.updatePrinterStatus("ready")
                self.pendingWriteResult?(true)
                self.pendingWriteResult = nil
            }
            return
        }
        
        let endIndex = min(writeOffset + writeChunkSize, data.count)
        let chunk = data.subdata(in: writeOffset..<endIndex)
        
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        
        peripheral.writeValue(chunk, for: characteristic, type: writeType)
        writeOffset = endIndex
        
        // For writeWithoutResponse, continue immediately
        // For writeWithResponse, wait for callback
        if writeType == .withoutResponse {
            // Send next chunk immediately for maximum speed
            writeNextChunk()
        }
        // If writeWithResponse, the didWriteValueFor callback will trigger next chunk
    }
    
    private func convertImageToEscPos(image: UIImage, targetWidth: Int?, targetHeight: Int?, settings: [String: Any]? = nil) -> Data {
        // Ensure width is divisible by 8 for ESC/POS compatibility
        let finalWidth: Int
        if let targetWidth = targetWidth {
            finalWidth = (targetWidth / 8) * 8
        } else {
            finalWidth = 384 // Default to 58mm paper
        }
        
        // Calculate height maintaining aspect ratio
        let aspectRatio = image.size.height / image.size.width
        let finalHeight = Int(Double(finalWidth) * Double(aspectRatio))
        
        // Resize image
        let resizedImage = resizeImage(image: image, targetSize: CGSize(width: finalWidth, height: finalHeight))
        
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
        
        // Add center alignment command
        escPosData.append(Data([0x1B, 0x61, 0x01])) // ESC a 1 (center)
        
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
        
        // Add feed lines if specified
        if let settings = settings, let feedLines = settings["feedLines"] as? Int, feedLines > 0 {
            for _ in 0..<feedLines {
                escPosData.append(Data([0x0A])) // Line feed
            }
        }
        
        // Reset alignment to left
        escPosData.append(Data([0x1B, 0x61, 0x00])) // ESC a 0 (left)
        
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
        print("iOS: CBCentralManager state changed to: \(central.state.rawValue)")
        // Handle state changes if needed
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Get device name from advertisement data if not available from peripheral
        let deviceName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown Device"
        
        // Debug: Log ALL discovered devices
        print("iOS: Discovered device: \(deviceName) (\(peripheral.identifier.uuidString)) RSSI: \(RSSI.intValue)")
        print("iOS: Advertisement data: \(advertisementData)")
        
        // More lenient filtering - only skip if completely anonymous and very weak
        if RSSI.intValue < -95 && deviceName == "Unknown Device" && (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.isEmpty != false {
            print("iOS: Skipping very weak anonymous device")
            return
        }
        
        // Convert iOS UUID to more readable format (last 12 characters)
        let uuidString = peripheral.identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let shortAddress = String(uuidString.suffix(12)).uppercased()
        let formattedAddress = stride(from: 0, to: shortAddress.count, by: 2).map {
            let start = shortAddress.index(shortAddress.startIndex, offsetBy: $0)
            let end = shortAddress.index(start, offsetBy: 2)
            return String(shortAddress[start..<end])
        }.joined(separator: ":")
        
        let deviceInfo: [String: Any] = [
            "id": peripheral.identifier.uuidString,
            "name": deviceName,
            "address": formattedAddress,
            "type": "ble",
            "rssi": RSSI.intValue,
            "isPaired": false
        ]
        
        // Check if this might be the KPrinter we're looking for during manual connection
        if deviceName.contains("KPrinter") || deviceName.contains("77a7") {
            print("iOS: Found potential KPrinter during scan: \(deviceName)")
            
            // If we're in manual connection mode, try to connect immediately
            if pendingResult != nil {
                print("iOS: Attempting immediate connection to found KPrinter")
                connectedPeripheral = peripheral
                peripheral.delegate = self
                centralManager?.connect(peripheral, options: nil)
                return
            }
        }
        
        // Only update and send if this is a new device or RSSI changed significantly
        if let existingDevice = discoveredDevices[peripheral.identifier.uuidString] {
            let existingRSSI = existingDevice["rssi"] as? Int ?? -100
            if abs(RSSI.intValue - existingRSSI) < 5 { // RSSI hasn't changed much
                return
            }
        }
        
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
        
        print("iOS: Discovered service: \(service.uuid)")
        
        for characteristic in characteristics {
            print("iOS: Found characteristic: \(characteristic.uuid), properties: \(characteristic.properties.rawValue)")
            
            // Priority: writeWithoutResponse > write
            if characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("iOS: Selected writeWithoutResponse characteristic: \(characteristic.uuid)")
                break
            } else if characteristic.properties.contains(.write) && writeCharacteristic == nil {
                writeCharacteristic = characteristic
                print("iOS: Selected write characteristic: \(characteristic.uuid)")
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("iOS: Write error: \(error)")
            pendingWriteData = nil
            writeOffset = 0
            DispatchQueue.main.async {
                self.updatePrinterStatus("error")
                self.pendingWriteResult?(false)
                self.pendingWriteResult = nil
            }
            return
        }
        
        // Continue with next chunk for writeWithResponse
        if characteristic.properties.contains(.write) && !characteristic.properties.contains(.writeWithoutResponse) {
            writeNextChunk()
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
