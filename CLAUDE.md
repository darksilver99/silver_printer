# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
# Get dependencies
flutter pub get

# Run tests
flutter test

# Analyze code (lint) 
flutter analyze

# Format code
dart format .

# Clean build artifacts
flutter clean

# Run example app
cd example && flutter run

# Run on specific platform
flutter run -d android
flutter run -d ios  
flutter run -d chrome

# Run integration tests
cd example && flutter test integration_test/
```

## Architecture

This is a Flutter plugin using the federated plugin pattern with platform interface abstraction. The plugin structure follows Flutter's recommended architecture:

**Core Interface Layer:**
- `SilverPrinterPlatform` - Abstract platform interface using plugin_platform_interface pattern
- `MethodChannelSilverPrinter` - Default implementation using method channels for mobile/desktop
- `SilverPrinterWeb` - Web-specific implementation

**Platform Implementations:**
- Android: Kotlin plugin in `android/src/main/kotlin/` using FlutterPlugin and MethodCallHandler
- iOS/macOS: Swift plugin using FlutterPlugin protocol  
- Linux/Windows: C++ implementations with Flutter plugin API
- Web: Dart implementation with platform-specific web APIs

**Method Channel Communication:**
All platforms communicate through `silver_printer` method channel. The channel name must match exactly across Dart and native implementations.

**Plugin Registration:**
Each platform defines its plugin class in `pubspec.yaml`:
- Android: `SilverPrinterPlugin` 
- iOS/macOS: `SilverPrinterPlugin`
- Windows: `SilverPrinterPluginCApi`
- Web: `SilverPrinterWeb`

The example app demonstrates plugin usage and serves as integration test platform.