# Silver Printer Plugin - Setup Guide

## การติดตั้งและตั้งค่า

### 1. การเพิ่ม Plugin ใน pubspec.yaml

```yaml
dependencies:
  silver_printer:
    path: ../silver_printer  # หรือ path ที่เก็บ plugin
```

### 2. การตั้งค่า Android

#### Android Manifest (`android/app/src/main/AndroidManifest.xml`)

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Bluetooth permissions -->
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    
    <!-- Android 12+ permissions -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
                     android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- Bluetooth features -->
    <uses-feature android:name="android.hardware.bluetooth" android:required="true" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />

    <application>
        <!-- Your app configuration -->
    </application>
</manifest>
```

#### ProGuard Rules (`android/app/proguard-rules.pro`)

```pro
# Silver Printer Plugin
-keep class com.silver.printerslip.silver_printer.** { *; }
-dontwarn com.silver.printerslip.silver_printer.**

# Bluetooth
-keep class android.bluetooth.** { *; }
-dontwarn android.bluetooth.**
```

### 3. การตั้งค่า iOS

#### Info.plist (`ios/Runner/Info.plist`)

```xml
<dict>
    <!-- Existing keys... -->
    
    <!-- Bluetooth permissions -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>This app uses Bluetooth to connect to thermal printers</string>
    
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>This app uses Bluetooth to connect to thermal printers</string>
    
    <!-- Background modes (optional) -->
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
    </array>
</dict>
```

#### iOS Deployment Target

ตั้งค่าใน `ios/Podfile`:

```ruby
platform :ios, '11.0'  # ต้อง iOS 11.0+ สำหรับ Core Bluetooth
```

### 4. การใช้งานพื้นฐาน

```dart
import 'package:silver_printer/silver_printer.dart';

class PrinterExample extends StatefulWidget {
  @override
  _PrinterExampleState createState() => _PrinterExampleState();
}

class _PrinterExampleState extends State<PrinterExample> {
  final _printer = SilverPrinter.instance;
  
  @override
  void initState() {
    super.initState();
    _initializePrinter();
  }
  
  Future<void> _initializePrinter() async {
    // ตรวจสอบ Bluetooth
    final isAvailable = await _printer.isBluetoothAvailable();
    if (!isAvailable) {
      // ขอ permission
      await _printer.requestBluetoothPermissions();
    }
  }
  
  Future<void> _scanAndConnect() async {
    // เริ่ม scan
    await _printer.startScan();
    
    // Listen for devices
    _printer.deviceDiscoveryStream.listen((device) {
      print('Found: ${device.name}');
    });
    
    // หยุด scan หลัง 10 วินาที
    await Future.delayed(Duration(seconds: 10));
    await _printer.stopScan();
  }
  
  Future<void> _printText(String text) async {
    final success = await _printer.printText(
      text,
      settings: {
        'fontSize': 'normal',
        'alignment': 'left',
      },
    );
    
    if (success) {
      print('Print successful');
    } else {
      print('Print failed');
    }
  }
}
```

## ข้อจำกัดและความเข้ากันได้

### 🟢 Android - รองรับเต็มรูปแบบ

| เครื่องปริ้น | Interface | ความเข้ากันได้ | ความเร็ว |
|-------------|-----------|----------------|----------|
| KPrinter_77a7 (JK-5802H) | USB+BT (Bluetooth Classic) | ✅ เต็มรูปแบบ | 🟢 เร็ว (1-2 วินาที) |
| PT-280 | USB+Bluetooth (BLE) | ✅ เต็มรูปแบบ | 🟢 เร็ว (1-2 วินาที) |

### 🟡 iOS - รองรับบางส่วน

| เครื่องปริ้น | Interface | ความเข้ากันได้ | ความเร็ว |
|-------------|-----------|----------------|----------|
| KPrinter_77a7 (JK-5802H) | USB+BT (Bluetooth Classic) | ❌ ไม่รองรับ | - |
| PT-280 | USB+Bluetooth (BLE) | ✅ รองรับ | 🟡 ช้า (10-15 วินาที) |

### สาเหตุข้อจำกัด iOS:

1. **Bluetooth Classic (BT)**: iOS ไม่อนุญาตให้ third-party apps ใช้ Bluetooth Classic SPP
2. **BLE Performance**: iOS มีข้อจำกัดเรื่อง BLE throughput ที่เข้มงวดกว่า Android
3. **MFi Requirement**: เครื่องปริ้น Bluetooth Classic ต้อง MFi certified เท่านั้น

### วิธีแยกแยะเครื่องปริ้น:

- **"USB+BT"** = Bluetooth Classic → Android เท่านั้น
- **"USB+Bluetooth"** = BLE → iOS และ Android (แต่ iOS ช้า)

## คำแนะนำการใช้งาน

### สำหรับ Android Users:
- ใช้ได้ทุกเครื่องปริ้น
- ประสิทธิภาพดีที่สุด

### สำหรับ iOS Users:
- แนะนำ PT-280 หรือเครื่องปริ้น BLE อื่นๆ
- หลีกเลี่ยงเครื่องปริ้นที่มีป้าย "BT"
- คาดหวังความเร็วช้ากว่า Android

### สำหรับ Cross-Platform Apps:
```dart
// ตรวจสอบ platform และแจ้งเตือน user
if (Platform.isIOS) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('iOS Printing Notice'),
      content: Text(
        'บน iOS การปริ้นจะใช้เวลานานกว่า Android\n'
        'และรองรับเฉพาะเครื่องปริ้น BLE เท่านั้น'
      ),
    ),
  );
}
```

## การ Debug

### Android:
```bash
# ดู logs
flutter logs

# หรือใช้ adb
adb logcat | grep SilverPrinter
```

### iOS:
```bash
# เปิด Xcode console เพื่อดู logs
# หรือใช้ flutter logs
flutter logs
```

## การแก้ปัญหาเบื้องต้น

### 1. ไม่เจอเครื่องปริ้น:
- ตรวจสอบ Bluetooth permissions
- ลองเปิด/ปิด Bluetooth
- ตรวจสอบว่าเครื่องปริ้นอยู่ใน pairing mode

### 2. เชื่อมต่อไม่ได้:
- ตรวจสอบว่าเครื่องปริ้นไม่ได้เชื่อมกับ device อื่น
- ลอง unpair แล้ว pair ใหม่

### 3. ปริ้นไม่ออก:
- ตรวจสอบกระดาษในเครื่องปริ้น
- ลองปริ้น text ธรรมดาก่อน
- ตรวจสอบ battery เครื่องปริ้น

## เวอร์ชันที่รองรับ

- **Flutter**: 3.0+
- **Dart**: 2.17+
- **Android**: API 21+ (Android 5.0+)
- **iOS**: 11.0+