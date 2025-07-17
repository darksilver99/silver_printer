// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:silver_printer_example/main.dart';

void main() {
  testWidgets('Verify app launches correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the main screen loads with expected elements
    expect(find.text('Silver Printer Demo'), findsOneWidget);
    expect(find.text('Bluetooth Status'), findsOneWidget);
    expect(find.text('Connection Status'), findsOneWidget);
    expect(find.text('Food Order Receipt'), findsOneWidget);
    expect(find.text('Print Receipt'), findsOneWidget);
  });
}
