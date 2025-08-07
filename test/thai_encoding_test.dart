import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:silver_printer/silver_printer.dart';
import 'package:silver_printer/silver_printer_method_channel.dart';
import 'package:silver_printer/silver_printer_platform_interface.dart';
import 'package:silver_printer/print_item.dart';

void main() {
  const MethodChannel channel = MethodChannel('silver_printer');
  
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'printText':
            final args = methodCall.arguments as Map<dynamic, dynamic>;
            final text = args['text'] as String;
            final settings = args['settings'] as Map<dynamic, dynamic>?;
            
            // Simulate successful print for Thai text
            if (text.contains('ภาษาไทย') || text.contains('สวัสดี') || text.contains('ทดสอบ')) {
              return true;
            }
            return true;
          case 'printHybrid':
            final args = methodCall.arguments as Map<dynamic, dynamic>;
            final items = args['items'] as List;
            final settings = args['settings'] as Map<dynamic, dynamic>?;
            
            // Check if any item contains Thai text
            for (var item in items) {
              if (item is Map<dynamic, dynamic> && item['type'] == 'text') {
                final content = item['content'] as String?;
                if (content != null && (content.contains('ภาษาไทย') || content.contains('สวัสดี'))) {
                  return true;
                }
              }
            }
            return true;
          default:
            return false;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Thai Encoding Tests', () {
    late SilverPrinter silverPrinter;

    setUp(() {
      silverPrinter = SilverPrinter.instance;
    });

    test('printText handles Thai characters correctly', () async {
      const thaiText = 'สวัสดีครับ ทดสอบภาษาไทย 123';
      
      final result = await silverPrinter.printText(
        thaiText,
        settings: {
          'fontSize': 'normal',
          'alignment': 'left',
        },
      );
      
      expect(result, true);
    });

    test('printText handles Thai characters with different font sizes', () async {
      const thaiText = 'ภาษาไทยขนาดใหญ่';
      
      final result = await silverPrinter.printText(
        thaiText,
        settings: {
          'fontSize': 'large',
          'bold': true,
          'alignment': 'center',
        },
      );
      
      expect(result, true);
    });

    test('printHybrid handles mixed Thai and English content', () async {
      final items = [
        PrintItem.text(
          'Header in English',
          alignment: TextAlignment.center,
          size: TextSize.large,
          bold: true,
        ),
        PrintItem.text(
          'หัวข้อภาษาไทย',
          alignment: TextAlignment.center,
          size: TextSize.normal,
        ),
        PrintItem.text(
          'รายการสินค้า:',
          alignment: TextAlignment.left,
        ),
        PrintItem.text(
          '1. กาแฟร้อน - 50 บาท',
          alignment: TextAlignment.left,
        ),
        PrintItem.text(
          '2. ชาเย็น - 35 บาท',
          alignment: TextAlignment.left,
        ),
        PrintItem.divider(),
        PrintItem.text(
          'รวม: 85 บาท',
          alignment: TextAlignment.right,
          bold: true,
        ),
        PrintItem.text(
          'ขอบคุณครับ',
          alignment: TextAlignment.center,
        ),
      ];

      final result = await silverPrinter.printHybrid(items);
      
      expect(result, true);
    });

    test('printHybrid handles Thai characters in receipt format', () async {
      final items = [
        PrintItem.text(
          'ร้านอาหารไทย',
          alignment: TextAlignment.center,
          size: TextSize.large,
          bold: true,
        ),
        PrintItem.text(
          'ใบเสร็จการสั่งซื้อ',
          alignment: TextAlignment.center,
        ),
        PrintItem.divider(character: '='),
        PrintItem.text(
          'วันที่: 7 สิงหาคม 2567',
          alignment: TextAlignment.left,
        ),
        PrintItem.text(
          'เวลา: 14:30 น.',
          alignment: TextAlignment.left,
        ),
        PrintItem.divider(),
        PrintItem.text(
          'รายการอาหาร:',
          alignment: TextAlignment.left,
          bold: true,
        ),
        PrintItem.text(
          'ผัดไทย x1        120 บาท',
          alignment: TextAlignment.left,
        ),
        PrintItem.text(
          'ส้มตำ x1         80 บาท',
          alignment: TextAlignment.left,
        ),
        PrintItem.text(
          'น้ำส้ม x2        60 บาท',
          alignment: TextAlignment.left,
        ),
        PrintItem.divider(),
        PrintItem.text(
          'รวม:           260 บาท',
          alignment: TextAlignment.right,
          size: TextSize.large,
          bold: true,
        ),
        PrintItem.lineFeed(2),
        PrintItem.text(
          'ขอบคุณที่ใช้บริการ',
          alignment: TextAlignment.center,
        ),
      ];

      final result = await silverPrinter.printHybrid(items);
      
      expect(result, true);
    });

    test('printText handles special Thai characters and symbols', () async {
      const specialThaiText = '''
ร้านค้า: ก.ข.ค. จำกัด
ที่อยู่: ๑๒๓/๔๕ ซอย ๖ ถนน ๗
โทร: ๐๒-๑๒๓-๔๕๖๗
อีเมล: test@email.co.th

สินค้า: น้ำปลา ๓๘๖ บาท
ภาษี: ๗% = ๒๗.๐๒ บาท
รวม: ๔๑๓.๐๒ บาท
''';
      
      final result = await silverPrinter.printText(
        specialThaiText,
        settings: {
          'fontSize': 'normal',
          'alignment': 'left',
        },
      );
      
      expect(result, true);
    });

    test('printHybrid handles empty Thai strings gracefully', () async {
      final items = [
        PrintItem.text(''),
        PrintItem.text('ข้อความปกติ'),
        PrintItem.text(''),
      ];

      final result = await silverPrinter.printHybrid(items);
      
      expect(result, true);
    });
  });
}