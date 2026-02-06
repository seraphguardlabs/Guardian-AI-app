# Geofencing API Reference (Backend Implementation)

This document describes the structure, headers, and JSON formats for all geofencing-related API endpoints implemented in the GuardianAI-backend, along with the files where each endpoint is coded.

---

## 1. Create Geofence

- **Method:** POST
- **URL:** `/api/mobile/child/<child_hash>/geofences/`
- **Headers:**
  - `X-Email`: Guardian email
  - `X-Password`: Guardian password
  - `Content-Type`: application/json
- **Body (JSON):**
  ```json
  {
    "label": "Home",
    "latitude": 40.7128,
    "longitude": -74.0060,
    "radius": 100.0,
    "trigger_on": "both"
  }
  ```
- **Response (201):**
  ```json
  {
    "status": "ok",
    "geofence": {
      "id": 101,
      "label": "Home",
      "latitude": 40.7128,
      "longitude": -74.0060,
      "radius": 100.0,
      "trigger_on": "both",
      "created_at": "2026-01-30T12:00:00Z"
    }
  }
  ```
- **Files:**
  - location_tracking/views.py (`api_geofences`)
  - location_tracking/urls.py

---

## 2. List Geofences

- **Method:** GET
- **URL:** `/api/mobile/child/<child_hash>/geofences/`
- **Headers:**
  - `X-Email`: Guardian email
  - `X-Password`: Guardian password
- **Response (200):**
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
        "trigger_on": "both",
        "created_at": "2026-01-30T12:00:00Z"
      }
    ]
  }
  ```
- **Files:**
  - location_tracking/views.py (`api_geofences`)
  - location_tracking/urls.py

---

## 3. Delete Geofence

- **Method:** DELETE
- **URL:** `/api/mobile/child/<child_hash>/geofences/<geofence_id>/`
- **Headers:**
  - `X-Email`: Guardian email
  - `X-Password`: Guardian password
- **Response (200):**
  ```json
  {
    "status": "ok",
    "message": "Geofence deleted"
  }
  ```
- **Files:**
  - location_tracking/views.py (`api_geofence_delete`)
  - location_tracking/urls.py

---

## 4. Geofence Event Ingestion (HTTP Fallback)

- **Method:** POST
- **URL:** `/api/ingest/`
- **Headers:**
  - `X-Child-Hash`: Child hash
  - `Content-Type`: application/json
- **Body (JSON):**
  ```json
  {
    "child_hash": "...",
    "data_type": "geofence_event",
    "payload": {
      "geofence_id": 101,
      "event_type": "enter",
      "timestamp": "2026-01-30T12:00:00Z"
    }
  }
  ```
- **Response (200):**
  ```json
  {
    "status": "ok",
    "message": "Geofence event received"
  }
  ```
- **Files:**
  - location_tracking/views.py (`api_geofence_event_ingest`)
  - location_tracking/urls.py

---

## 5. Geofence Alerts/History

- **Method:** GET
- **URL:** `/api/mobile/child/<child_hash>/geofence-alerts/`
- **Headers:**
  - `X-Email`: Guardian email
  - `X-Password`: Guardian password
- **Response (200):**
  ```json
  {
    "status": "ok",
    "alerts": []
  }
  ```
- **Files:**
  - location_tracking/views.py (`api_geofence_alerts`)
  - location_tracking/urls.py

---

## Model Definition
- **Geofence model:** location_tracking/models.py

---

> Replace `<child_hash>` and `<geofence_id>` with actual values from your database.
> All endpoints are implemented in the `location_tracking` app.
