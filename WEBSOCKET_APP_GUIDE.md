# Flutter WebSocket Request App — Developer Guide

A step-by-step reference for building a Flutter app that establishes a persistent WebSocket connection, sends a structured JSON payload on demand, and displays live server responses with full connection-state visibility.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Prerequisites](#2-prerequisites)
3. [Project Setup](#3-project-setup)
4. [Adding the WebSocket Dependency](#4-adding-the-websocket-dependency)
5. [Architecture & File Structure](#5-architecture--file-structure)
6. [Code Walkthrough](#6-code-walkthrough)
   - 6.1 [Entry Point](#61-entry-point)
   - 6.2 [Connection State Enum](#62-connection-state-enum)
   - 6.3 [State Management & WebSocket Lifecycle](#63-state-management--websocket-lifecycle)
   - 6.4 [Sending a Payload](#64-sending-a-payload)
   - 6.5 [Message Model](#65-message-model)
   - 6.6 [UI Widgets](#66-ui-widgets)
7. [Payload Schema](#7-payload-schema)
8. [Theming & Color System](#8-theming--color-system)
9. [Error Handling Strategy](#9-error-handling-strategy)
10. [Running the App](#10-running-the-app)
11. [Customization Reference](#11-customization-reference)
12. [Common Issues & Fixes](#12-common-issues--fixes)

---

## 1. Project Overview

The app provides a single-screen UI that:

- Accepts user input for **Child Hash** (builds the WebSocket URL dynamically), **App Domain**, **Requested Hours**, and **Guardian ID**.
- Connects to a WebSocket endpoint via a **Connect** button (blocked until Child Hash is provided).
- Displays a real-time **connection status indicator** (animated pulsing dot) and the resolved URL.
- Shows a **live payload preview** that updates as the user types.
- Sends a structured JSON request to the server when **Send Request** is tapped (validates fields before sending).
- Renders every sent message, received message, and system event in a **scrollable message log** with colour-coded bubbles.
- Allows the log to be cleared and the connection to be closed on demand.

---

## 2. Prerequisites

| Tool | Minimum Version | Notes |
|------|----------------|-------|
| Flutter SDK | 3.x stable | `flutter --version` to verify |
| Dart SDK | 3.x | Bundled with Flutter |
| Android SDK / Xcode | Latest stable | For device/emulator targets |

---

## 3. Project Setup

```bash
# Create the Flutter project targeting the required platforms
flutter create <project_name> --org <reverse_domain_org> --platforms android,ios

# Example
flutter create my_ws_app --org com.example --platforms android,ios
```

Replace `<project_name>` with your app's snake_case name and `<reverse_domain_org>` with your organisation's reverse domain (e.g. `com.mycompany`).

---

## 4. Adding the WebSocket Dependency

```bash
cd <project_name>
flutter pub add web_socket_channel
```

This appends the following to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  web_socket_channel: ^3.0.0   # actual version resolved at install time
```

`web_socket_channel` wraps the platform WebSocket API and exposes a unified `Stream`/`Sink` interface.

---

## 5. Architecture & File Structure

```
lib/
└── main.dart          # Entire app in a single file (suitable for small/demo apps)
```

The file is divided into well-commented sections:

| Section | Purpose |
|---------|---------|
| `MyApp` | `MaterialApp` root, theme setup |
| `ConnectionStatus` | Enum for the four connection states |
| `WebSocketScreen` | Stateful screen — owns the channel, controllers, state, and message list |
| `_InputsCard` | Four text-input fields that drive the URL and payload |
| `_StatusCard` | Displays the animated connection indicator and resolved URL |
| `_PayloadPreview` | Live JSON payload display — updates on every keystroke |
| `_Message` / `_MessageType` | Immutable message model with named constructors |
| `_MessageBubble` | Renders a single message entry in the log |

---

## 6. Code Walkthrough

### 6.1 Entry Point

```dart
void main() {
  runApp(const MyApp());
}
```

`MyApp` is a stateless widget that wraps a `MaterialApp` with a dark theme and points `home` to the single `WebSocketScreen` widget.

### 6.2 Connection State Enum

```dart
enum ConnectionStatus { disconnected, connecting, connected, error }
```

Four states cover the full lifecycle of a WebSocket connection:

| State | Meaning |
|-------|---------|
| `disconnected` | No active channel. Initial state or after explicit close. |
| `connecting` | `WebSocketChannel.connect()` was called; handshake pending. |
| `connected` | `channel.ready` future resolved successfully. |
| `error` | A stream error or failed handshake was received. |

---

### 6.3 State Management & WebSocket Lifecycle

The widget mixes in `SingleTickerProviderStateMixin` to drive the pulse animation on the status indicator.

**Key instance variables:**

```dart
// Input controllers — drive URL and payload dynamically
TextEditingController _childHashCtrl;   // builds the WS URL
TextEditingController _appDomainCtrl;   // payload: app_domain
TextEditingController _hoursCtrl;       // payload: requested_hours
TextEditingController _guardianIdCtrl;  // payload: guardian_id

// Derived URL from child hash field
String get _wsUrl => '$_wsBase${_childHashCtrl.text.trim()}$_wsPath';

WebSocketChannel? _channel;          // The active channel, null when disconnected
StreamSubscription? _subscription;   // Holds the stream listener so it can be cancelled
ConnectionStatus _status;            // Current state, drives all UI
String? _errorMessage;               // Last error text, shown in status card
List<_Message> _messages;            // Ordered log of all events
ScrollController _scrollController;  // Auto-scroll the log to the latest message
```

**Live rebuild on typing:**

Each controller registers a `_rebuild` listener in `initState` so the payload preview and the URL in the status card refresh on every keystroke without any manual `setState` call at the call sites:

```dart
void initState() {
  // ...
  _childHashCtrl.addListener(_rebuild);
  _appDomainCtrl.addListener(_rebuild);
  _hoursCtrl.addListener(_rebuild);
  _guardianIdCtrl.addListener(_rebuild);
}

void _rebuild() => setState(() {});
```

**Connecting (with validation):**

```dart
void _connect() {
  // Guard 1: already connecting or connected
  if (_status == ConnectionStatus.connected ||
      _status == ConnectionStatus.connecting) return;

  // Guard 2: child hash must be provided before a URL can be built
  if (_childHashCtrl.text.trim().isEmpty) {
    // show SnackBar
    return;
  }

  _channel = WebSocketChannel.connect(Uri.parse(_wsUrl)); // URL built from input
  // ...
}
```

**Disconnecting:**

```dart
void _disconnect() {
  _subscription?.cancel();   // Stop receiving events
  _channel?.sink.close();    // Send a WebSocket close frame to the server
  _channel = null;
  _subscription = null;
  setState(() => _status = ConnectionStatus.disconnected);
}
```

> **Why `.ready`?**  `WebSocketChannel.connect()` returns immediately — it does not wait for the server to accept the connection. The `.ready` future is the correct place to confirm the handshake succeeded.

**Disposing:**

```dart
@override
void dispose() {
  _pulseController.dispose();
  _subscription?.cancel();
  _channel?.sink.close();
  _scrollController.dispose();
  // TextEditingControllers must always be disposed
  _childHashCtrl.dispose();
  _appDomainCtrl.dispose();
  _hoursCtrl.dispose();
  _guardianIdCtrl.dispose();
  super.dispose();
}
```

---

### 6.4 Sending a Payload

```dart
void _sendPayload() {
  // Read and validate all payload fields from controllers
  final domain    = _appDomainCtrl.text.trim();
  final hours     = int.tryParse(_hoursCtrl.text.trim());
  final guardian  = int.tryParse(_guardianIdCtrl.text.trim());

  if (domain.isEmpty || hours == null || guardian == null) {
    // show SnackBar — reject early
    return;
  }

  final payload = {
    "type": "<request_type>",
    "data": {
      "<domain_field>":   domain,
      "<quantity_field>": hours,
      "<secure_field>":   "<base64_or_encrypted_string>",
      "<owner_id_field>": guardian,
    },
  };

  // Send compact JSON over the wire
  _channel!.sink.add(jsonEncode(payload));

  // Log pretty-printed JSON to the message panel
  _addMessage(_Message.sent(const JsonEncoder.withIndent('  ').convert(payload)));
}
```

Two separate JSON representations are used:
- **Compact** (`jsonEncode`) — sent over the wire to minimise bytes.
- **Pretty-printed** (`JsonEncoder.withIndent`) — shown in the UI for readability.

---

### 6.5 Message Model

```dart
enum _MessageType { sent, received, system }

class _Message {
  final String content;
  final _MessageType type;
  final DateTime timestamp;

  _Message.sent(this.content)     : type = _MessageType.sent,     timestamp = DateTime.now();
  _Message.received(this.content) : type = _MessageType.received, timestamp = DateTime.now();
  _Message.system(this.content)   : type = _MessageType.system,   timestamp = DateTime.now();
}
```

Named constructors make the call-sites expressive and ensure `timestamp` is always captured at creation time.

---

### 6.6 UI Widgets

#### `_InputsCard`

A stateless widget that renders four labelled `TextField` widgets:

| Field | Controller | Type | Locked when connected? |
|-------|-----------|------|------------------------|
| Child Hash | `_childHashCtrl` | text | Yes — changes URL |
| App Domain | `_appDomainCtrl` | text | No |
| Requested Hours | `_hoursCtrl` | number | No |
| Guardian ID | `_guardianIdCtrl` | number | No |

All fields are styled with a dark fill, a purple focus border (`#6C63FF`), and a dimmed disabled border. A `connectionActive` boolean is passed in to lock the child hash field while the socket is open.

The private `_field()` helper method reduces repetition across the four `TextField` instances.

#### `_StatusCard`

Accepts the current `ConnectionStatus`, a matching `Color`, a label string, the WebSocket URL, an optional error string, and the pulse `Animation<double>`.

The animated dot is driven by an `AnimatedBuilder` wrapping an `Opacity` widget:

```dart
AnimatedBuilder(
  animation: pulseAnimation,
  builder: (context, child) => Opacity(
    // Only animate opacity when in the 'connecting' state
    opacity: status == ConnectionStatus.connecting
        ? pulseAnimation.value   // oscillates between 0.6 and 1.0
        : 1.0,
    child: /* coloured circle */,
  ),
),
```

The `AnimationController` runs on a 900 ms reverse loop set up in `initState`.

#### `_PayloadPreview`

A stateless widget that accepts **three live values** passed from the parent state: `appDomain` (String), `requestedHours` (int?), and `guardianId` (int?). It builds the payload map inline and formats it with `JsonEncoder.withIndent`. Placeholder strings (`<app_domain>`, `<requested_hours>`, `<guardian_id>`) are shown until the user fills in the corresponding field.

Because the parent rebuilds on every controller keystroke (via `_rebuild`), the preview is always in sync with the inputs without any additional state management.

#### `_MessageBubble`

Uses a Dart 3 **destructuring switch expression** to derive the four visual properties (background colour, border colour, label string, label colour, and icon) from the message type in a single expression:

```dart
final (bg, border, label, labelColor, icon) = switch (message.type) {
  _MessageType.sent     => ( /* purple palette */ ),
  _MessageType.received => ( /* teal palette   */ ),
  _MessageType.system   => ( /* grey palette   */ ),
};
```

`SelectableText` is used for message content so users can copy server responses.

---

## 7. Payload Schema

The WebSocket URL is constructed at runtime from a base, a variable child identifier, and a fixed path suffix:

```
ws://<host>/ws/child/<child_hash>/time-extension/
```

| Part | Description | Example |
|------|-------------|---------|
| `<host>` | Server hostname | `seraphguardlabs.com` |
| `<child_hash>` | Unique hash identifying the child account (entered at runtime) | `RGI3l1IbHya5t6YT` |
| `/time-extension/` | Fixed endpoint path | — |

The generalised payload structure sent to the server:

```json
{
  "type": "<action_identifier>",
  "data": {
    "<domain_field>":    "<target_domain_or_identifier>",
    "<quantity_field>":  <numeric_value>,
    "<secure_field>":    "<base64_or_encrypted_string>",
    "<owner_id_field>":  <integer_id>
  }
}
```

| Generic Field | Description | Example Key | Example Value | User Input? |
|---------------|-------------|-------------|---------------|-------------|
| `type` | Action/event name understood by the server | `"type"` | `"time_extension_request"` | No (hardcoded) |
| `<domain_field>` | The resource or scope the action targets | `"app_domain"` | `"youtube.com"` | **Yes** |
| `<quantity_field>` | A numeric parameter for the action | `"requested_hours"` | `2` | **Yes** |
| `<secure_field>` | An encrypted or encoded authentication/message token | `"message_encrypted"` | `"base64_encrypted_message_here"` | No (hardcoded) |
| `<owner_id_field>` | ID of the supervising entity associated with the request | `"guardian_id"` | `4` | **Yes** |

To adapt the payload for a different backend, update the map inside `_sendPayload()`.

---

## 8. Theming & Color System

The app uses a custom **dark** color scheme defined in `MaterialApp.theme`:

```dart
ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C63FF),   // primary accent (indigo-purple)
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
)
```

Additional one-off colors used directly in widgets:

| Role | Hex | Where Used |
|------|-----|-----------|
| Page background | `#0F0F1A` | `Scaffold.backgroundColor` |
| Card / AppBar background | `#1A1A2E` | Status card, AppBar, payload preview |
| Card border (idle) | `#2A2A4A` | Container borders |
| Log background | `#12122A` | Message log container |
| Connected (green) | `#4CAF50` | Status dot & border |
| Connecting (amber) | `#FFB300` | Status dot & border |
| Error (red) | `#F44336` | Status dot & border |
| Disconnected (grey) | `#9E9E9E` | Status dot & border |
| Sent bubble border | `#6C63FF` | Message bubbles |
| Received bubble border | `#00BFA5` | Message bubbles |

---

## 9. Error Handling Strategy

| Failure point | Handling |
|---------------|---------|| Child Hash empty on Connect tap | SnackBar shown; `_connect()` returns early |
| Any payload field empty/invalid on Send tap | SnackBar shown; `_sendPayload()` returns early || `WebSocketChannel.connect()` throws synchronously | Caught by `try/catch` in `_connect()`; state set to `error` |
| `channel.ready` future rejects | Caught by `.catchError()`; error message stored in `_errorMessage` |
| Stream emits an error event | `onError` callback updates state to `error` |
| Stream closes unexpectedly | `onDone` callback resets state to `disconnected` |
| `_sendPayload()` called while not connected | SnackBar shown; no data sent |

All error messages are stored in `_errorMessage` and rendered below the WebSocket URL inside the `_StatusCard`.

---

## 10. Running the App

```bash
# List available devices
flutter devices

# Run on a specific device
flutter run -d <device_id>

# Run in release mode (no debug banner, optimised)
flutter run --release

# Build an APK
flutter build apk --release
```

For hot-reload during development, press **r** in the terminal. For a full restart, press **R**.

---

## 11. Customization Reference

| What to change | Where | How |
|----------------|-------|-----|
| WebSocket host | `_WebSocketScreenState._wsBase` / `_wsPath` | Edit the `static const` strings |
| Child Hash (runtime) | `_InputsCard` → Child Hash field | Typed by the user at runtime |
| JSON payload fields (runtime) | `_InputsCard` → App Domain, Requested Hours, Guardian ID | Typed by the user at runtime |
| Hardcoded `message_encrypted` value | `_WebSocketScreenState._sendPayload()` | Replace the string literal |
| App title | `MyApp.build()` → `MaterialApp.title` and `AppBar.title` | Change the string literal |
| Primary accent color | `MyApp.build()` → `ColorScheme.fromSeed(seedColor:…)` | Replace the `Color` value |
| Animation duration | `_WebSocketScreenState.initState()` → `AnimationController(duration:…)` | Adjust the `Duration` |
| Message log font size | `_MessageBubble.build()` → `SelectableText` style | Edit `fontSize` |
| Input field label/hint text | `_InputsCard.build()` → each `_field(…)` call | Edit `label:` and `hint:` parameters |

---

## 12. Common Issues & Fixes

### `WebSocketChannelException: Connection refused`
- The server is not running or the URL is incorrect.
- Verify the WebSocket URL scheme (`ws://` for plain, `wss://` for TLS).

### App runs on iOS but WebSocket fails
- iOS requires App Transport Security (ATS) exceptions for plain `ws://` connections.
- Add to `ios/Runner/Info.plist`:
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  ```

### App runs on Android but network call fails
- Ensure `android/app/src/main/AndroidManifest.xml` has:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```
  (Flutter projects include this by default, but verify if it was removed.)

### `Bad state: Stream has already been listened to`
- A `WebSocketChannel` stream can only have one listener. Ensure `_disconnect()` is always called before calling `_connect()` again, and that `_subscription?.cancel()` runs before re-listening.

### `setState() called after dispose()`
- All callbacks that call `setState` must be guarded with `if (mounted)` checks. This is already applied in this implementation's async callbacks (`.then`, `.catchError`, `onError`, `onDone`).

---

*Generated for Flutter 3.x / Dart 3.x. Last updated: February 2026.*
