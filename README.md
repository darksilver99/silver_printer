# Silver Printer

A comprehensive Flutter plugin for connecting to thermal/POS printers via Bluetooth. This plugin supports both Classic Bluetooth and Bluetooth Low Energy (BLE) across Android and iOS platforms.

## Features

- **Universal Bluetooth Support**: Connects to any Bluetooth device (Classic + BLE)
- **Cross-Platform**: Works on both Android and iOS
- **Optimized Performance**: Special optimizations for iOS image printing
- **ESC/POS Commands**: Built-in support for standard thermal printer commands
- **Real-time Streams**: Connection state, device discovery, and printer status streams
- **Image Printing**: Convert Flutter widgets to images and print them
- **Text Printing**: Print formatted text with various settings

## Platform Support

| Platform | Classic Bluetooth | Bluetooth LE | Performance |
|----------|-------------------|--------------|-------------|
| Android  | ✅ Full Support   | ✅ Full Support | 🟢 Fast (1-2 seconds) |
| iOS      | ❌ Not Supported  | ✅ Limited Support | 🟡 Slow (10-15 seconds) |

## Printer Compatibility

### 🟢 Android - Full Support
- **KPrinter_77a7 (JK-5802H)**: USB+BT → ✅ Fast printing
- **PT-280**: USB+Bluetooth → ✅ Fast printing  
- **All thermal printers**: Both Bluetooth Classic and BLE

### 🟡 iOS - Limited Support
- **KPrinter_77a7 (JK-5802H)**: USB+BT → ❌ Not supported (Bluetooth Classic)
- **PT-280**: USB+Bluetooth → ⚠️ Slow printing (BLE limitations)
- **BLE printers only**: Must use "Bluetooth" not "BT" interface

### How to Identify Compatible Printers
Look at the printer's interface specification:
- **"USB+BT"** = Bluetooth Classic → Android only
- **"USB+Bluetooth"** = BLE → Both platforms (iOS slower)

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  silver_printer: ^0.0.1
```

## Permissions

### Android

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Bluetooth Classic permissions -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />

<!-- Bluetooth permissions for Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Location permission for Bluetooth scanning -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Bluetooth features -->
<uses-feature android:name="android.hardware.bluetooth" android:required="false" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
```

### iOS

Add the following to your `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect and print to thermal printers</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to connect and print to thermal printers</string>
```

## Usage

### Basic Setup

```dart
import 'package:silver_printer/silver_printer.dart';

final printer = SilverPrinter.instance;
```

### Check Bluetooth Availability

```dart
bool isAvailable = await printer.isBluetoothAvailable();
if (!isAvailable) {
  await printer.requestBluetoothPermissions();
}
```

### Scan for Devices

```dart
// Start scanning
await printer.startScan();

// Listen to discovered devices
printer.deviceDiscoveryStream.listen((device) {
  print('Found device: ${device.name} (${device.type})');
});

// Get all discovered devices
List<BluetoothDevice> devices = await printer.getDiscoveredDevices();

// Stop scanning
await printer.stopScan();
```

### Connect to a Printer

```dart
// Connect to a device
bool connected = await printer.connect(device.id);

// Listen to connection state changes
printer.connectionStateStream.listen((state) {
  print('Connection state: $state');
});

// Check if connected
bool isConnected = await printer.isConnected();
```

### Print Text

```dart
await printer.printText('Hello, World!');

// With custom settings
await printer.printText(
  'Formatted Text',
  settings: {
    'fontSize': 'large',
    'alignment': 'center',
    'bold': true,
  },
);
```

### Print Images

```dart
// From widget using RepaintBoundary
final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
final image = await boundary.toImage(pixelRatio: 2.0);
final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
final imageBytes = byteData!.buffer.asUint8List();

await printer.printImage(
  imageBytes,
  width: 384,
  height: 200,
);
```

### Print Combined Content

```dart
final job = PrintJob(
  text: 'Receipt Header\n',
  imageData: imageBytes,
  imageWidth: 384,
  imageHeight: 200,
  settings: {
    'cutPaper': true,
    'feedLines': 3,
  },
);

await printer.printJob(job);
```

### Utility Functions

```dart
// Feed paper
await printer.feedPaper(3);

// Cut paper (if supported)
await printer.cutPaper();

// Send raw ESC/POS commands
await printer.sendRawData(escPosCommands);

// Disconnect
await printer.disconnect();
```

## Example App

The plugin comes with a comprehensive example app that demonstrates:

1. **Main Screen**: Shows Bluetooth and connection status
2. **Device List**: Scans and displays all available Bluetooth devices
3. **Print Preview**: Shows a receipt preview with print functionality

To run the example:

```bash
cd example
flutter run
```

## Supported Printer Commands

The plugin supports standard ESC/POS commands:

- Text printing with formatting
- Image printing (optimized for thermal printers)
- Paper feeding
- Paper cutting
- Raw command sending

## Performance Optimizations

### iOS Image Printing

The plugin includes special optimizations for iOS:
- **Chunked Data Transfer**: Sends data in small chunks to prevent BLE overflow
- **Automatic Delays**: Adds appropriate delays between chunks
- **Image Resizing**: Automatically resizes images to printer-friendly dimensions
- **Memory Management**: Efficient memory usage for large images

### Android Support

- **Dual Protocol**: Automatically tries Classic Bluetooth first, falls back to BLE
- **Fast Discovery**: Efficient device discovery for both protocols
- **Large Data Transfer**: Optimized for faster printing on Classic Bluetooth

## Troubleshooting

### Common Issues

1. **iOS prints slowly**: This is a platform limitation. iOS BLE throughput is restricted compared to Android.
2. **iOS can't find printer**: Check if printer uses Bluetooth Classic (BT) - not supported on iOS.
3. **Android can't find device**: Ensure location permissions are granted for Bluetooth scanning.
4. **Connection fails**: Try pairing the device in system settings first (Android only).
5. **Print quality issues**: Ensure printer has adequate battery and paper is loaded correctly.

### Debug Tips

```dart
// Monitor connection state
printer.connectionStateStream.listen((state) {
  print('Connection: $state');
});

// Monitor printer status
printer.printerStatusStream.listen((status) {
  print('Printer: $status');
});
```

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to the main branch.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
