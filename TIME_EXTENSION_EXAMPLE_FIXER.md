# Time Extension Request – WebSocket Demo (`time_extension_example_fixer.dart`)

## Overview

This file is a self-contained Flutter application that acts as a **manual testing tool** for the `time-extension` WebSocket endpoint exposed by the Guardian AI backend (`seraphguardlabs.com`).

It lets a tester or developer:
1. Enter the parameters that make up a time-extension request.
2. Open a WebSocket connection to the server.
3. Send a correctly-structured JSON payload.
4. Observe the server's response in a live message log.

---

## WebSocket Endpoint

```
ws://seraphguardlabs.com/ws/child/<child_hash>/time-extension/
```

The `<child_hash>` is supplied at runtime via a text field and is embedded directly in the URL when the connection is established.

---

## Payload Format

```json
{
  "type": "time_extension_request",
  "data": {
    "app_domain": "youtube.com",
    "requested_hours": 2,
    "message_encrypted": "base64_encrypted_message_here",
    "guardian_id": 4
  }
}
```

| Field               | Type    | Description                                             |
|---------------------|---------|---------------------------------------------------------|
| `app_domain`        | string  | Domain of the app the child wants extra time for        |
| `requested_hours`   | int     | Number of additional hours being requested              |
| `message_encrypted` | string  | Base64-encoded encrypted message from the child         |
| `guardian_id`       | int     | Database ID of the guardian who will receive the request|

---

## Application Structure

### `MyApp`
Root widget. Configures a `MaterialApp` with a dark purple/indigo theme using Material 3.

---

### `ConnectionStatus` (enum)
Tracks the state of the WebSocket connection:
- `disconnected` – no active connection
- `connecting` – handshake in progress
- `connected` – stream is open and ready
- `error` – connection or stream error occurred

---

### `WebSocketScreen` / `_WebSocketScreenState`
The main screen and the heart of the application.

**State it manages:**
- Four `TextEditingController` instances for the input fields (child hash, app domain, requested hours, guardian ID).
- A `WebSocketChannel` and its `StreamSubscription`.
- Current `ConnectionStatus` and an optional error message string.
- A list of `_Message` objects that populate the message log.
- A pulse `AnimationController` used to animate the status indicator dot while connecting.

**Key methods:**

| Method | Purpose |
|---|---|
| `_connect()` | Builds the WebSocket URL from the child-hash field and opens the channel. Subscribes to the stream to receive incoming messages, errors, and the close event. |
| `_disconnect()` | Cancels the subscription, closes the sink, and resets status to `disconnected`. |
| `_sendPayload()` | Validates the four input fields, constructs the JSON payload, serialises it, sends it over the channel, and echoes a pretty-printed version to the message log. |
| `_addMessage()` | Appends a `_Message` to the log list and scrolls the log to the bottom. |
| `_clearMessages()` | Empties the message log. |
| `_rebuild()` | Listener attached to every `TextEditingController`; triggers `setState` so the payload preview updates live as the user types. |

---

### `_StatusCard`
Read-only card that displays:
- An animated dot whose colour reflects the current `ConnectionStatus`.
- The human-readable status label.
- The full WebSocket URL being targeted.
- Any error message (shown in red when present).

The dot pulses (opacity animation) when the status is `connecting`.

---

### `_PayloadPreview`
Displays a live, pretty-printed JSON preview of the payload that *would* be sent given the current field values. Placeholder strings (e.g. `<app_domain>`) appear for any field not yet filled in.

---

### `_InputsCard`
Form card containing the four input fields:
- **Child Hash** – locked (disabled) once a connection is active to prevent URL changes mid-session.
- **App Domain** – free-text domain name.
- **Requested Hours** – numeric field.
- **Guardian ID** – numeric field.

Uses a shared private `_field()` helper to render each `TextField` with consistent dark-theme styling.

---

### `_Message` / `_MessageType`
Simple data model for a log entry.

| Type | Colour | Meaning |
|---|---|---|
| `sent` | Purple/indigo | Payload sent by this client |
| `received` | Teal/green | Response received from the server |
| `system` | Grey | Internal events (connected, disconnected, error) |

---

### `_MessageBubble`
Renders a single `_Message` in the log list. Shows:
- A directional icon and coloured label (`SENT` / `RECEIVED` / `SYSTEM`).
- A `HH:MM:SS` timestamp.
- The message body as selectable monospace text.

---

## UI Layout (top to bottom)

```
AppBar  ──────────────────────────────────────
  Title: "Time Extension Request"
  Action: clear-messages button

Body padding
  ┌─ _InputsCard (Child Hash, App Domain, Hours, Guardian ID)
  ├─ _StatusCard (dot · status · URL · error)
  ├─ Connect / Disconnect button │ Send Request button
  ├─ _PayloadPreview (live JSON preview)
  └─ Expanded message log
       header (icon · "Message Log" · count)
       ─────────────────────────────────────
       ListView of _MessageBubble widgets
```

---

## Intended Use

This file is meant to be compiled and run as a **standalone Flutter app** (separate from the main Guardian AI app) to:
- Verify the `time-extension` WebSocket endpoint is reachable.
- Confirm the server accepts and responds to the correct payload structure.
- Debug connection issues or payload parsing errors during development.
