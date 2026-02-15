# Location Tracking API Endpoints

This document describes the API endpoints for the `location_tracking` app, including dashboard, mobile, and geofence APIs. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard: Get Child Location Data
- **URL:** `/location_tracking/dashboard/locations/<child_hash>/`
- **Method:** `GET`
- **Auth:** Session (guardian login required)
- **Description:** Retrieve location data for a specific child for dashboard display. Supports optional date range filtering.
- **Query Params:**
	- `start_date` (optional): YYYY-MM-DD
	- `end_date` (optional): YYYY-MM-DD
- **Response (JSON):**
	- On success:
		```json
		{
			"locations": [
				{
					"timestamp": "Feb 14, 2026 10:30",
					"latitude": 12.3456,
					"longitude": 78.9012
				}
			],
			"count": 1
		}
		```
	- On error: `{ "error": "<error_message>" }`

---

## 2. Mobile: Get Location History
- **URL:** `/location_tracking/api/mobile/child/<child_hash>/locations/`
- **Method:** `GET`
- **Auth:** X-Email and X-Password headers, or session auth
- **Description:** Retrieve detailed location history for a specific child, with filtering and summary.
- **Query Params:**
	- `start_date` (optional): YYYY-MM-DD (defaults to 7 days ago)
	- `end_date` (optional): YYYY-MM-DD (defaults to today)
	- `limit` (optional): max number of locations (default 100, max 500)
- **Response (JSON):**
	- On success:
		```json
		{
			"status": "ok",
			"child_hash": "abc123",
			"child_name": "Jane Doe",
			"date_range": {
				"start_date": "2026-02-07",
				"end_date": "2026-02-14"
			},
			"locations": [
				{
					"latitude": 12.3456,
					"longitude": 78.9012,
					"timestamp": "2026-02-14T10:30:00Z"
				}
			],
			"summary": {
				"total_count": 10,
				"returned_count": 1,
				"unique_locations": 1,
				"limit_applied": 100
			}
		}
		```
	- On error: `{ "status": "error", "message": "<error_message>" }`

---

## 3. Geofence APIs
- **List/Create Geofences**
	- **URL:** `/location_tracking/api/mobile/child/<child_hash>/geofences/`
	- **Method:** `GET`, `POST`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:**
		- `GET`: List all geofences for a child.
		- `POST`: Create a new geofence for a child.
	- **Payload (POST, JSON):**
		- `label` (string, required)
		- `latitude` (float, required)
		- `longitude` (float, required)
		- `radius` (float, required)
		- `trigger_on` (string, required; e.g., "entry", "exit", "both")
	- **Response (JSON):**
		- On success (POST):
			```json
			{
				"status": "ok",
				"geofence": {
					"id": 1,
					"label": "School",
					"latitude": 12.3456,
					"longitude": 78.9012,
					"radius": 100.0,
					"trigger_on": "both",
					"created_at": "2026-02-14T10:30:00Z"
				}
			}
			```
		- On success (GET):
			```json
			{
				"status": "ok",
				"geofences": [ ... ]
			}
			```
		- On error: `{ "status": "error", "message": "<error_message>" }`
- **Delete Geofence**
	- **URL:** `/location_tracking/api/mobile/child/<child_hash>/geofences/<geofence_id>/`
	- **Method:** `DELETE`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Response (JSON):** `{ "status": "ok", "message": "Geofence deleted" }` or error

---

## 4. Geofence Event Ingestion (HTTP Fallback)
- **URL:** `/location_tracking/api/ingest/`
- **Method:** `POST`
- **Description:** Ingest geofence event from child device. Expects X-Child-Hash header and JSON body.
- **Headers:**
	- `X-Child-Hash`: child hash (required)
- **Payload (JSON):**
	```json
	{
		"data_type": "geofence_event",
		"payload": {
			"geofence_id": 1,
			"event_type": "entry",
			"timestamp": "2026-02-14T10:30:00Z",
			"latitude": 12.3456,
			"longitude": 78.9012
		}
	}
	```
- **Response (JSON):** `{ "status": "ok", "message": "Geofence event received" }` or error

---

## 5. Geofence Alerts/History
- **URL:** `/location_tracking/api/mobile/child/<child_hash>/geofence-alerts/`
- **Method:** `GET`
- **Auth:** X-Email and X-Password headers, or session auth
- **Description:** Retrieve geofence entry/exit events for a child (currently returns empty list; event storage not implemented).
- **Response (JSON):** `{ "status": "ok", "alerts": [] }` or error

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (see view decorators for limits).
