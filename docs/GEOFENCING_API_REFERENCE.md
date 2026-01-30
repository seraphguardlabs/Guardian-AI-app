# Guardian AI - Geofencing API Specification

Geofencing allows guardians to define virtual boundaries on a map and receive alerts when a child enters or exits these areas.

## 1. Geofence Management (REST)
These endpoints are used by the **Guardian** to manage protected zones.

### Create Geofence
- **Endpoint:** `POST /api/mobile/child/<child_hash>/geofences/`
- **Headers:** `X-Email`, `X-Password`
- **Request Body:**
```json
{
  "label": "Home",
  "latitude": 40.7128,
  "longitude": -74.0060,
  "radius": 100.0,
  "trigger_on": "both"
}
```
| Field | Type | Description |
|---|---|---|
| `label` | String | User-defined name (e.g., "School", "Home"). |
| `latitude` | Double | Center point latitude. |
| `longitude` | Double | Center point longitude. |
| `radius` | Double | Accuracy radius in meters (typical: 50m - 500m). |
| `trigger_on` | Enum | `enter`, `exit`, or `both`. |

### List Geofences
- **Endpoint:** `GET /api/mobile/child/<child_hash>/geofences/`
- **Headers:** `X-Email`, `X-Password`
- **Response:**
```json
{
  "status": "ok",
  "geofences": [
    {
      "id": 101,
      "label": "Home",
      "latitude": 40.7128,
      "longitude": -74.0060,
      "radius": 100.0,
      "created_at": "..."
    }
  ]
}
```

### Delete Geofence
- **Endpoint:** `DELETE /api/mobile/child/<child_hash>/geofences/<geofence_id>/`
- **Headers:** `X-Email`, `X-Password`

---

## 2. Geofence Event Ingestion (Real-time)
These events are sent by the **Child device** when it detects a boundary crossing.

### Via WebSocket
- **Type:** `geofence_event`
- **Payload:**
```json
{
  "geofence_id": 101,
  "event_type": "enter",
  "timestamp": "2026-01-29T19:30:00Z",
  "latitude": 40.7129,
  "longitude": -74.0061
}
```

### Via HTTP Ingest (Fallback)
- **Endpoint:** `POST /api/ingest/`
- **Headers:** `X-Child-Hash`
- **Payload:**
```json
{
  "child_hash": "...",
  "data_type": "geofence_event",
  "payload": {
    "geofence_id": 101,
    "event_type": "enter",
    "timestamp": "..."
  }
}
```

---

## 3. Alerts & History (Guardian View)

### Get Geofence Alerts
- **Endpoint:** `GET /api/mobile/child/<child_hash>/geofence-alerts/`
- **Headers:** `X-Email`, `X-Password`
- **Response:** A chronological list of entry/exit events for dashboard notification.

---

## 4. Implementation Notes
1. **Device-side Monitoring:** The child mobile app should use the native Geofencing API (Android `GeofencingClient` / iOS `CLCircularRegion`) to minimize battery usage. 
2. **Synchronization:** Geofence definitions should be synced to the child device whenever the app starts or a WebSocket `refresh_geofences` message is received.
