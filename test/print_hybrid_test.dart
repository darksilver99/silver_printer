import 'package:flutter_test/flutter_test.dart';
import 'package:silver_printer/silver_printer.dart';
import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrintHybrid Tests', () {
    test(
      'printHybrid method exists and handles MissingPluginException',
      () async {
        final printer = SilverPrinter.instance;

        // Create sample hybrid print items
        final items = [
          PrintItem.text(
            'Test Header',
            alignment: TextAlignment.center,
            bold: true,
          ),
          PrintItem.divider(),
          PrintItem.text('Regular text line'),
          PrintItem.lineFeed(2),
          PrintItem.text(
            'Receipt Footer',
            alignment: TextAlignment.center,
            size: TextSize.small,
          ),
        ];

        // This should throw an exception when no native implementation is available
        expect(
          () async => await printer.printHybrid(items),
          throwsException,
        );
      },
    );

    test('PrintItem factory constructors work correctly', () {
      // Test text item
      final textItem = PrintItem.text(
        'Hello World',
        alignment: TextAlignment.center,
        bold: true,
        size: TextSize.large,
      );
      expect(textItem, isA<PrintTextItem>());
      expect((textItem as PrintTextItem).content, equals('Hello World'));
      expect(textItem.alignment, equals(TextAlignment.center));
      expect(textItem.bold, equals(true));
      expect(textItem.size, equals(TextSize.large));

      // Test image item
      final imageData = Uint8List.fromList([1, 2, 3, 4]);
      final imageItem = PrintItem.image(
        imageData,
        width: 384,
        alignment: ImageAlignment.center,
      );
      expect(imageItem, isA<PrintImageItem>());
      expect((imageItem as PrintImageItem).imageData, equals(imageData));
      expect(imageItem.width, equals(384));
      expect(imageItem.alignment, equals(ImageAlignment.center));

      // Test line feed item
      final lineFeedItem = PrintItem.lineFeed(3);
      expect(lineFeedItem, isA<PrintLineFeedItem>());
      expect((lineFeedItem as PrintLineFeedItem).lines, equals(3));

      // Test divider item
      final dividerItem = PrintItem.divider(character: '=', width: 48);
      expect(dividerItem, isA<PrintDividerItem>());
      expect((dividerItem as PrintDividerItem).character, equals('='));
      expect(dividerItem.width, equals(48));
    });

    test('PrintItem toMap() serialization works', () {
      final textItem = PrintItem.text('Test', bold: true);
      final textMap = textItem.toMap();

      expect(textMap['type'], equals('text'));
      expect(textMap['content'], equals('Test'));
      expect(textMap['bold'], equals(true));
      expect(textMap['alignment'], equals('left'));
      expect(textMap['size'], equals('normal'));
      expect(textMap['underline'], equals(false));

      final imageData = Uint8List.fromList([1, 2, 3]);
      final imageItem = PrintItem.image(imageData, width: 200);
      final imageMap = imageItem.toMap();

      expect(imageMap['type'], equals('image'));
      expect(imageMap['imageData'], equals(imageData));
      expect(imageMap['width'], equals(200));
      expect(imageMap['alignment'], equals('center'));
    });
  });
}
