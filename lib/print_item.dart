import 'dart:typed_data';

/// Base class for hybrid print items
abstract class PrintItem {
  final String type;

  const PrintItem(this.type);

  /// Convert to map for method channel communication
  Map<String, dynamic> toMap();

  /// Create a text print item
  factory PrintItem.text(
    String content, {
    TextAlignment? alignment,
    TextSize? size,
    bool? bold,
    bool? underline,
  }) = PrintTextItem;

  /// Create an image print item
  factory PrintItem.image(
    Uint8List imageData, {
    int? width,
    int? height,
    ImageAlignment? alignment,
  }) = PrintImageItem;

  /// Create a line feed item
  factory PrintItem.lineFeed([int? lines]) = PrintLineFeedItem;

  /// Create a divider line
  factory PrintItem.divider({String? character, int? width}) = PrintDividerItem;
}

/// Text alignment options
enum TextAlignment { left, center, right }

/// Text size options
enum TextSize { small, normal, large, extraLarge }

/// Image alignment options
enum ImageAlignment { left, center, right }

/// Text print item
class PrintTextItem extends PrintItem {
  final String content;
  final TextAlignment alignment;
  final TextSize size;
  final bool bold;
  final bool underline;

  const PrintTextItem(
    this.content, {
    TextAlignment? alignment,
    TextSize? size,
    bool? bold,
    bool? underline,
  }) : alignment = alignment ?? TextAlignment.left,
       size = size ?? TextSize.normal,
       bold = bold ?? false,
       underline = underline ?? false,
       super('text');

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'content': content,
      'alignment': alignment.name,
      'size': size.name,
      'bold': bold,
      'underline': underline,
    };
  }
}

/// Image print item
class PrintImageItem extends PrintItem {
  final Uint8List imageData;
  final int? width;
  final int? height;
  final ImageAlignment alignment;

  const PrintImageItem(
    this.imageData, {
    this.width,
    this.height,
    ImageAlignment? alignment,
  }) : alignment = alignment ?? ImageAlignment.center,
       super('image');

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'imageData': imageData,
      'width': width,
      'height': height,
      'alignment': alignment.name,
    };
  }
}

/// Line feed print item
class PrintLineFeedItem extends PrintItem {
  final int lines;

  const PrintLineFeedItem([int? lines]) : lines = lines ?? 1, super('lineFeed');

  @override
  Map<String, dynamic> toMap() {
    return {'type': type, 'lines': lines};
  }
}

/// Divider print item
class PrintDividerItem extends PrintItem {
  final String character;
  final int? width;

  const PrintDividerItem({String? character, this.width})
    : character = character ?? '-',
      super('divider');

  @override
  Map<String, dynamic> toMap() {
    return {'type': type, 'character': character, 'width': width};
  }
}
