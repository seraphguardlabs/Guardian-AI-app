# Messaging & Time Extension API Endpoints

This document describes the API endpoints for the `messaging` app, including E2E encryption, time extension requests, gamified permission system, chat messaging, tasks, and AI alerts. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. E2E Encryption - Public Key Endpoints
- **Child Public Key**
	- **URL:** `/api/mobile/child/<child_hash>/public-key/`
	- **Method:** `GET`, `POST`
	- **Auth:** None (child device)
	- **Description:**
		- `GET`: Retrieve or generate the child's public key
		- `POST`: Set/update the child's public key
	- **Payload (POST, JSON):** `{ "public_key": "..." }`
- **Guardian Public Key**
	- **URL:** `/api/mobile/guardian/public-key/`
	- **Method:** `GET`, `POST`
	- **Auth:** Guardian (session or header)
	- **Description:**
		- `GET`: Retrieve or generate the authenticated guardian's public key
		- `POST`: Set/update the guardian's public key
	- **Payload (POST, JSON):** `{ "public_key": "..." }`
- **Guardian Public Key by ID**
	- **URL:** `/api/mobile/guardian/<guardian_id>/public-key/`
	- **Method:** `GET`
	- **Auth:** None (child device)
	- **Description:** Retrieve a specific guardian's public key
- **Child's Guardians' Public Keys**
	- **URL:** `/api/mobile/child/<child_hash>/guardians/public-keys/`
	- **Method:** `GET`
	- **Auth:** None (child device)
	- **Description:** Retrieve all guardians' public keys for a child

---

## 2. Time Extension Requests
- **List/Create Time Extension Requests**
	- **URL:** `/api/mobile/time-extension-requests/`
	- **Method:** `GET`, `POST`
	- **Auth:** Guardian (session/header) or child (header)
	- **Description:**
		- `GET`: List pending requests (guardian or child)
		- `POST`: Create a new time extension request (child)
- **Child's Time Extension Requests**
	- **URL:** `/api/mobile/child/<child_hash>/time-extension-requests/`
	- **Method:** `GET`
	- **Auth:** Child (header)
	- **Description:** List time extension requests for a child
- **Respond to Time Extension Request**
	- **URL:** `/api/mobile/time-extension-requests/<request_id>/respond/`
	- **Method:** `POST`
	- **Auth:** Guardian (session/header)
	- **Payload (JSON):** `{ "response": "approved|denied", ... }`

---

## 3. Gamified Permission System
- **Suggested Reward Tasks**
	- **URL:** `/api/mobile/time-extension-requests/suggested-tasks/`
	- **Method:** `GET`
	- **Auth:** None
	- **Description:** Get a list of suggested reward tasks
- **Assign Reward Task**
	- **URL:** `/api/mobile/time-extension-requests/<request_id>/assign-task/`
	- **Method:** `POST`
	- **Auth:** Guardian (session/header)
	- **Payload (JSON):** `{ "task_id": "..." }` or custom task
- **Approve Time Extension**
	- **URL:** `/api/mobile/time-extension-requests/<request_id>/approve/`
	- **Method:** `POST`
	- **Auth:** Guardian (session/header)

---

## 4. Chat Messaging (E2E Encrypted)
- **Guardian-Child Chat**
	- **URL:** `/api/mobile/child/<child_hash>/chat/`
	- **Method:** `GET`, `POST`
	- **Auth:** Guardian (session/header)
	- **Description:**
		- `GET`: Retrieve chat messages with a child
		- `POST`: Send a new message to the child
- **Child-Guardian Chat**
	- **URL:** `/api/mobile/guardian/<guardian_id>/chat/`
	- **Method:** `GET`, `POST`
	- **Auth:** Child (header)
	- **Description:**
		- `GET`: Retrieve chat messages with a guardian
		- `POST`: Send a new message to the guardian
- **Mark Messages Read**
	- **URL:** `/api/mobile/child/<child_hash>/chat/mark-read/`
	- **Method:** `POST`
	- **Auth:** Guardian or child
	- **Payload (JSON):** `{ "message_ids": [1,2,3], "guardian_id": 1 }`
- **Unread Message Counts**
	- **URL:** `/api/mobile/chat/unread/`
	- **Method:** `GET`
	- **Auth:** Guardian or child

---

## 5. Task Endpoints
- **Guardian Create Task**
	- **URL:** `/api/mobile/child/<child_hash>/tasks/`
	- **Method:** `POST`
	- **Auth:** Guardian (session/header)
	- **Payload (JSON):** `{ "title": "...", "description": "..." }`
- **Guardian View Child Tasks**
	- **URL:** `/api/mobile/child/<child_hash>/tasks/list/`
	- **Method:** `GET`
	- **Auth:** Guardian (session/header)
- **Child View Tasks**
	- **URL:** `/api/mobile/child/<child_hash>/my-tasks/`
	- **Method:** `GET`
	- **Auth:** Child (header)
- **Child Mark Task Complete**
	- **URL:** `/api/mobile/child/<child_hash>/tasks/<task_id>/complete/`
	- **Method:** `POST`
	- **Auth:** Child (header)
- **Child Mark Task Incomplete**
	- **URL:** `/api/mobile/child/<child_hash>/tasks/<task_id>/incomplete/`
	- **Method:** `POST`
	- **Auth:** Child (header)

---

## 6. AI Alert Endpoints
- **Ingest Data (Child Device -> Server)**
	- **URL:** `/api/ingest/`
	- **Method:** `POST`
	- **Auth:** Child (header)
	- **Description:** Ingest AI alert, screen time, location, or site access data from child device
	- **Payload (JSON):**
		- For AI alert: `{ "type": "ai_alert", "payload": { ... } }`
		- For screen time: `{ "type": "screen_time", "payload": { ... } }`
		- For location: `{ "type": "location", "payload": { ... } }`
		- For site access: `{ "type": "site_access", "payload": { ... } }`
- **Get Alerts (Guardian)**
	- **URL:** `/api/mobile/child/<child_hash>/alerts/`
	- **Method:** `GET`
	- **Auth:** Guardian (session/header)

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (see view decorators for limits).

---

## 7. WebSocket Endpoints (Real-Time Messaging & Time Extension)

The messaging app provides several WebSocket endpoints for real-time communication between child and guardian devices. These are defined in `messaging/routing.py` and handled by consumers in `messaging/consumers.py`.

### a. Data Ingestion WebSocket (Child Device → Server)
- **URL:** `ws://<domain>/ws/ingest/<child_hash>/`
- **Consumer:** `DataIngestionConsumer`
- **Description:** Child devices send real-time data (screen time, location, site access, AI alerts) to the server.
- **Message Format:**
		```json
		{
			"type": "screen_time" | "location" | "site_access" | "ai_alert",
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
		- For `ai_alert`:
			```json
			{
				"type": "ai_alert",
				"data": {
					"risk_type": "inappropriate_content",
					"details": { ... },
					"timestamp": "YYYY-MM-DDTHH:MM:SSZ"
				}
			}
			```
- **Response:**
		- On connection: `{ "type": "connection_established", "child_hash": "...", "message": "Data ingestion WebSocket connected" }`
		- On success: `{ "type": "<type>_ack", "status": "success", ... }`
		- On error: `{ "type": "error", "message": "..." }`

### b. Child Time Extension WebSocket
- **URL:** `ws://<domain>/ws/child/<child_hash>/time-extension/`
- **Consumer:** `ChildTimeExtensionConsumer`
- **Description:** Child devices request screen time extensions and receive responses from guardians in real time.
- **Message Format:**
		- To request extension:
			```json
			{
				"type": "extension_request",
				"data": {
					"app_domain": "com.example.app",
					"requested_hours": 1,
					"message_encrypted": "...",
					"guardian_id": 1
				}
			}
			```
		- To receive response:
			```json
			{
				"type": "time_extension_response",
				"data": { ... }
			}
			```
- **Response:**
		- On connection: `{ "type": "connection_established", "child_hash": "...", "message": "Time extension WebSocket connected" }`
		- On error: `{ "type": "error", "message": "..." }`

### c. Guardian Time Extension WebSocket
- **URL:** `ws://<domain>/ws/guardian/time-extension/`
- **Consumer:** `GuardianTimeExtensionConsumer`
- **Description:** Guardians receive time extension requests from children and send responses in real time. Authentication is required.
- **Authentication Message:**
		```json
		{
			"type": "auth",
			"email": "guardian@example.com",
			"password": "..."
		}
		```
		- On success: `{ "type": "auth_success", "guardian_id": 1, "email": "...", "message": "Authentication successful" }`
		- On failure: `{ "type": "error", "message": "Invalid credentials" }`
- **Other Messages:**
		- Receive time extension requests:
			```json
			{
				"type": "time_extension_request",
				"data": { ... }
			}
			```
		- Respond to requests:
			```json
			{
				"type": "response",
				"data": {
					"request_id": 123,
					"action": "approve" | "deny" | "message",
					"granted_hours": 1, // if approved
					"response_encrypted": "..."
				}
			}
			```
		- Receive pending requests:
			```json
			{
				"type": "pending_requests",
				"count": 2,
				"requests": [ ... ]
			}
			```
- **Response:**
		- On connection: `{ "type": "auth_required", "message": "Please authenticate with email and password" }`
		- On error: `{ "type": "error", "message": "..." }`

### d. Guardian AI Alert WebSocket
- **URL:** `ws://<domain>/ws/guardian/alerts/`
- **Consumer:** `GuardianAlertConsumer`
- **Description:** Guardians receive real-time AI-generated alerts for their children. Authentication is required.
- **Authentication Message:**
		```json
		{
			"type": "auth",
			"email": "guardian@example.com",
			"password": "..."
		}
		```
		- On success: `{ "type": "auth_success", "guardian_id": 1, "email": "...", "message": "Authentication successful" }`
		- On failure: `{ "type": "error", "message": "Invalid credentials" }`
- **Other Messages:**
		- Receive alert:
			```json
			{
				"type": "alert",
				"source": "parent",
				"data": { ... }
			}
			```
- **Response:**
		- On connection: `{ "type": "auth_required", "message": "Please authenticate with email and password" }`
		- On error: `{ "type": "error", "message": "..." }`

---

**See also:**
- WebSocket routing: [messaging/routing.py](../../messaging/routing.py)
- WebSocket consumers: [messaging/consumers.py](../../messaging/consumers.py)
