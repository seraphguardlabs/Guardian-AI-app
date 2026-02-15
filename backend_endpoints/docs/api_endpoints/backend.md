# Backend API Endpoints

This document describes the API endpoints for the `backend` app, including dashboard, authentication, child management, data ingestion, AI insights, and mobile app APIs. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard View
- **URL:** `/backend/dashboard/`
- **Method:** `GET`, `POST`
- **Auth:** Session (guardian login required)
- **Description:** Renders the guardian dashboard with activity insights for all linked children. POST creates a new child profile.
- **Payload (POST):**
	- `first_name` (string, required)
	- `last_name` (string, optional)
	- `date_of_birth` (string, optional, format: YYYY-MM-DD)
- **Response:**
	- On GET: HTML dashboard page
	- On POST: Redirects to dashboard with success message

---

## 2. API Signup
- **URL:** `/backend/api/signup/`
- **Method:** `POST`
- **Description:** Mobile app signup endpoint. Creates a new guardian account.
- **Payload (JSON):**
	```json
	{
		"email": "user@example.com",
		"password": "securepassword",
		"full_name": "John Doe" // optional
	}
	```
- **Response (JSON):**
	- On success (201):
		```json
		{
			"status": "ok",
			"message": "Account created successfully",
			"guardian": {
				"id": 1,
				"email": "user@example.com",
				"full_name": "John Doe"
			},
			"children": []
		}
		```
	- On error: `{ "error": "<error_message>" }`

---

## 3. API Login
- **URL:** `/backend/api/login/`
- **Method:** `POST`
- **Description:** Mobile app login endpoint.
- **Payload (JSON):**
	```json
	{
		"email": "user@example.com",
		"password": "securepassword"
	}
	```
- **Response (JSON):**
	- On success:
		```json
		{
			"status": "ok",
			"children": [
				{
					"child_hash": "abc123",
					"first_name": "Jane",
					"last_name": "Doe",
					"date_of_birth": "2015-03-20"
				}
			]
		}
		```
	- On error: `{ "error": "<error_message>" }`

---

## 4. API Ingest
- **URL:** `/backend/api/ingest/`
- **Method:** `POST`
- **Description:** Ingest endpoint for the mobile app to POST metrics for a child.
- **Payload (JSON):**
	```json
	{
		"child_hash": "abc123",
		"screen_time_info": { ... },
		"location_info": { ... },
		"site_access_info": { "logs": [...] }
	}
	```
- **Response (JSON):**
	```json
	{
		"child_hash": "abc123",
		"screen_time": "not provided" | <result>,
		"location": "not provided" | <result>,
		"site_access": "not provided" | <result>
	}
	```
	- On error: `{ "error": "<error_message>" }`

---

## 5. Add Child (Mobile)
- **URL:** `/backend/api/mobile/children/add/`
- **Method:** `POST`
- **Auth:** X-Auth-Email and X-Auth-Password headers
- **Description:** Add a new child under a logged-in guardian.
- **Headers:**
	- `X-Auth-Email`: guardian email
	- `X-Auth-Password`: guardian password
- **Payload (JSON):**
	```json
	{
		"first_name": "Jane",
		"last_name": "Doe",           // optional
		"date_of_birth": "2015-03-20" // optional
	}
	```
- **Response (JSON):**
	- On success (201):
		```json
		{
			"status": "ok",
			"message": "Child added successfully",
			"child": {
				"child_hash": "abc123",
				"first_name": "Jane",
				"last_name": "Doe",
				"date_of_birth": "2015-03-20"
			}
		}
		```
	- On error: `{ "error": "<error_message>" }`

---

## 6. AI Insights
- **URL:** `/backend/api/child/<child_hash>/ai-ask/`
- **Method:** `POST`
- **Auth:** Session (guardian login required)
- **Description:** Get AI-generated insights for a child.
- **Payload (JSON):**
	```json
	{
		"question": "Summarise"
	}
	```
- **Response (JSON):**
	- On success: `{ "insights": "..." }`
	- On error: `{ "error": "<error_message>" }`

---


## 8. Child Metrics (Mobile)
- **URL:** `/backend/api/mobile/child/<child_hash>/metrics/`
- **Method:** `GET`
- **Auth:** X-Email and X-Password headers, or session auth
- **Query Params:**
	- `start_date` (optional): YYYY-MM-DD
	- `end_date` (optional): YYYY-MM-DD
- **Description:** Get aggregated metrics for a specific child (screen time, location, site access, app count, etc).
- **Response (JSON):**
	- On success: JSON with metrics (see view docstring for details)
	- On error: `{ "error": "<error_message>" }`

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- For additional endpoints (screen time, location, site access, messaging), see their respective microservice app documentation.

---

## 9. WebSocket Endpoints (Real-Time Ingest)

The backend provides WebSocket endpoints for real-time data ingestion from mobile clients. These endpoints are defined in `backend/routing.py` and handled by consumers in `backend/consumers.py`.

### a. Ingest WebSocket (Per-Child)
- **URL:** `ws://<domain>/ws/ingest/<child_hash>/`
- **Consumer:** `IngestConsumer`
- **Description:** Receives real-time metrics for a specific child. The connection is only accepted if the `child_hash` exists.
- **Message Format:**
		```json
		{
			"type": "screen_time" | "location" | "site_access",
			"data": { ... } // See below for payloads
		}
		```
		- For `screen_time`:
			```json
			{
				"type": "screen_time",
				"data": {
					"date": "YYYY-MM-DD",
					"total_screen_time": 3600,
					"app_wise_data": {"com.example.app": {"0": 1800, "1": 1800}}
				}
			}
			```
		- For `location`:
			```json
			{
				"type": "location",
				"data": {
					"timestamp": "YYYY-MM-DDTHH:MM:SSZ",
					"latitude": 40.7128,
					"longitude": -74.0060
				}
			}
			```
		- For `site_access`:
			```json
			{
				"type": "site_access",
				"data": {
					"logs": [
						{"timestamp": "YYYY-MM-DDTHH:MM:SSZ", "url": "https://example.com", "accessed": true}
					]
				}
			}
			```
- **Response:**
		- On connection: `{ "type": "connection_established", "child_hash": "...", "message": "WebSocket connection established successfully" }`
		- On success: `{ "type": "ack", "message_type": "screen_time" | "location" | "site_access", "status": "success", "result": { ... } }`
		- On error: `{ "type": "error", "message": "..." }`

### b. Ingest WebSocket (With Authentication)
- **URL:** `ws://<domain>/ws/ingest-auth/`
- **Consumer:** `IngestAuthConsumer`
- **Description:** Receives real-time metrics after authenticating with a `child_hash`. The first message must be an authentication message.
- **Authentication Message:**
		```json
		{
			"type": "auth",
			"child_hash": "abc123"
		}
		```
		- On success: `{ "type": "auth_success", "child_hash": "abc123", "message": "Authentication successful" }`
		- On failure: `{ "type": "error", "message": "Invalid child_hash" }`
- **Subsequent Messages:** Same as the Ingest WebSocket above.
- **Response:**
		- On connection: `{ "type": "auth_required", "message": "Please authenticate with child_hash" }`
		- On success: `{ "type": "ack", ... }`
		- On error: `{ "type": "error", "message": "..." }`

---

**See also:**
- WebSocket routing: [backend/routing.py](../../backend/routing.py)
- WebSocket consumers: [backend/consumers.py](../../backend/consumers.py)
