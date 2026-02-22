# Messaging & Time Extension API Endpoints

This document describes the API endpoints for the `messaging` app, including E2E encryption, time extension requests, gamified permission system, chat messaging, tasks, and AI alerts. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

## Authentication Methods

| Auth Type | Headers Required | Description |
|-----------|-----------------|-------------|
| Guardian (header) | `X-Email`, `X-Password` | Guardian authenticates with email and password headers |
| Guardian (session) | Session cookie | Logged-in guardian session |
| Child (header) | `X-Child-Hash` | Child authenticates with their unique hash |

---

## 1. E2E Encryption - Public Key Endpoints

### Child Public Key
- **URL:** `/api/mobile/child/<child_hash>/public-key/`
- **Methods:** `GET`, `POST`
- **Auth:** None (child device)

#### GET - Retrieve or generate child's public key
**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "child_name": "John Doe",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
}
```

#### POST - Set/update child's public key
**Request:**
```json
{
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----",
    "private_key": "-----BEGIN PRIVATE KEY-----\n..."  // Optional
}
```
**Response:**
```json
{
    "status": "ok",
    "message": "Public key updated successfully",
    "child_hash": "abc123def456",
    "child_name": "John Doe",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
}
```

---

### Guardian Public Key
- **URL:** `/api/mobile/guardian/public-key/`
- **Methods:** `GET`, `POST`
- **Auth:** Guardian (header) for POST, optional for GET

#### GET - Retrieve or generate guardian's public key
**Response:**
```json
{
    "status": "ok",
    "guardian_id": 1,
    "guardian_name": "Jane Doe",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
}
```

#### POST - Set/update guardian's public key
**Request:**
```json
{
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----",
    "private_key": "-----BEGIN PRIVATE KEY-----\n..."  // Optional
}
```
**Response:**
```json
{
    "status": "ok",
    "message": "Public key updated successfully",
    "guardian_id": 1,
    "guardian_name": "Jane Doe",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
}
```

---

### Guardian Public Key by ID
- **URL:** `/api/mobile/guardian/<guardian_id>/public-key/`
- **Method:** `GET`
- **Auth:** None (child device)

**Response:**
```json
{
    "status": "ok",
    "guardian_id": 1,
    "guardian_name": "Jane Doe",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
}
```

---

### Child's Guardians' Public Keys
- **URL:** `/api/mobile/child/<child_hash>/guardians/public-keys/`
- **Method:** `GET`
- **Auth:** None (child device)

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "child_name": "John Doe",
    "guardians": [
        {
            "guardian_id": 1,
            "guardian_name": "Jane Doe",
            "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
        },
        {
            "guardian_id": 2,
            "guardian_name": "Jim Doe",
            "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkq...\n-----END PUBLIC KEY-----"
        }
    ],
    "count": 2
}
```

---

## 2. Time Extension Requests

### List/Create Time Extension Requests
- **URL:** `/api/mobile/time-extension-requests/` (Guardian)
- **URL:** `/api/mobile/child/<child_hash>/time-extension-requests/` (Child)
- **Methods:** `GET`, `POST`
- **Auth:** Guardian (header) or Child (header)

#### GET (Guardian) - List pending requests
**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | `pending` | Filter by status: `pending`, `approved`, `denied`, `responded`, `all` |

**Response:**
```json
{
    "status": "ok",
    "guardian_id": 1,
    "filter": "pending",
    "requests": [
        {
            "request_id": 42,
            "child_hash": "abc123def456",
            "child_name": "John Doe",
            "app_domain": "youtube.com",
            "requested_hours": 2,
            "message_encrypted": "base64_encrypted_message",
            "status": "pending",
            "granted_hours": null,
            "created": "2026-02-22T10:30:00+00:00",
            "responded_at": null
        }
    ],
    "count": 1
}
```

#### GET (Child) - List own requests
**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "requests": [
        {
            "request_id": 42,
            "app_domain": "youtube.com",
            "requested_hours": 2,
            "status": "approved",
            "granted_hours": 1,
            "response_encrypted": "base64_encrypted_response",
            "created": "2026-02-22T10:30:00+00:00",
            "responded_at": "2026-02-22T10:45:00+00:00",
            "guardian_id": 1,
            "guardian_name": "Jane Doe"
        }
    ],
    "count": 1
}
```

#### POST (Child) - Create a new time extension request
**Request:**
```json
{
    "app_domain": "youtube.com",
    "requested_hours": 2,
    "message_encrypted": "base64_encrypted_message",
    "guardian_id": 1
}
```
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app_domain` | string | **Yes** | App or website domain |
| `requested_hours` | number | **Yes** | Hours requested (0-24) |
| `message_encrypted` | string | No | Encrypted message to guardian |
| `guardian_id` | integer | No | Specific guardian (uses default if omitted) |

**Response (201 Created):**
```json
{
    "status": "ok",
    "message": "Time extension request created",
    "request_id": 42,
    "child_hash": "abc123def456",
    "app_domain": "youtube.com",
    "requested_hours": 2,
    "guardian_id": 1,
    "guardian_name": "Jane Doe",
    "created": "2026-02-22T10:30:00+00:00"
}
```

---

### Respond to Time Extension Request
- **URL:** `/api/mobile/time-extension-requests/<request_id>/respond/`
- **Method:** `POST`
- **Auth:** Guardian (header)

**Request:**
```json
{
    "action": "approve",
    "granted_hours": 1,
    "response_encrypted": "base64_encrypted_response"
}
```
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | **Yes** | One of: `approve`, `deny`, `message` |
| `granted_hours` | number | **Yes** (if approve) | Hours granted |
| `response_encrypted` | string | No | Encrypted response message |

**Response:**
```json
{
    "status": "ok",
    "message": "Request approved",
    "request_id": 42,
    "action": "approve",
    "granted_hours": 1,
    "child_hash": "abc123def456",
    "app_domain": "youtube.com",
    "new_app_limit": 3
}
```

---

## 3. Gamified Permission System

### Suggested Reward Tasks
- **URL:** `/api/mobile/time-extension-requests/suggested-tasks/`
- **Method:** `GET`
- **Auth:** None

**Response:**
```json
{
    "status": "ok",
    "suggested_tasks": [
        {
            "id": "play_chess",
            "title": "Play Chess",
            "description": "Engage in a game of chess"
        },
        {
            "id": "exercise",
            "title": "Exercise for 20 mins",
            "description": "Do some light stretching or cardio"
        },
        {
            "id": "read",
            "title": "Read Newspaper",
            "description": "Read at least three major articles"
        }
    ]
}
```

### Assign Reward Task
- **URL:** `/api/mobile/time-extension-requests/<request_id>/assign-task/`
- **Method:** `POST`
- **Auth:** Guardian (header)

**Request:**
```json
{
    "task_id": "play_chess"
}
```

**Response:**
```json
{
    "status": "ok",
    "message": "Task assigned (stub)"
}
```

### Approve Time Extension
- **URL:** `/api/mobile/time-extension-requests/<request_id>/approve/`
- **Method:** `POST`
- **Auth:** Guardian (header)

**Response:**
```json
{
    "status": "ok",
    "message": "Time extension approved (stub)"
}
```

---

## 4. Chat Messaging (E2E Encrypted)

### Guardian-Child Chat
- **URL:** `/api/mobile/child/<child_hash>/chat/`
- **Methods:** `GET`, `POST`
- **Auth:** Guardian (header)

#### GET - Retrieve chat messages
**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 50 | Max messages to return |
| `before_id` | integer | - | Get messages before this ID (pagination) |
| `after_id` | integer | - | Get messages after this ID (new messages) |
| `mark_read` | boolean | false | Mark retrieved messages as read |

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "guardian_id": 1,
    "messages": [
        {
            "id": 100,
            "sender_type": "child",
            "message_encrypted": "base64_encrypted_message",
            "is_read": true,
            "created": "2026-02-22T10:30:00+00:00"
        },
        {
            "id": 101,
            "sender_type": "guardian",
            "message_encrypted": "base64_encrypted_message",
            "is_read": false,
            "created": "2026-02-22T10:35:00+00:00"
        }
    ],
    "unread_count": 0,
    "marked_read": 1,
    "count": 2
}
```

#### POST - Send a message to child
**Request:**
```json
{
    "message_encrypted": "base64_encrypted_message"
}
```

**Response:**
```json
{
    "status": "ok",
    "message": "Message sent successfully",
    "message_id": 102,
    "child_hash": "abc123def456",
    "guardian_id": 1,
    "created": "2026-02-22T10:40:00+00:00"
}
```

---

### Child-Guardian Chat
- **URL:** `/api/mobile/guardian/<guardian_id>/chat/`
- **Methods:** `GET`, `POST`
- **Auth:** Child (header)

#### GET - Retrieve chat messages
**Query Parameters:** Same as Guardian-Child Chat

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "guardian_id": 1,
    "messages": [
        {
            "id": 100,
            "sender_type": "child",
            "message_encrypted": "base64_encrypted_message",
            "is_read": true,
            "created": "2026-02-22T10:30:00+00:00"
        }
    ],
    "unread_count": 2,
    "marked_read": 0,
    "count": 1
}
```

#### POST - Send a message to guardian
**Request:**
```json
{
    "message_encrypted": "base64_encrypted_message"
}
```

**Response:**
```json
{
    "status": "ok",
    "message": "Message sent successfully",
    "message_id": 103,
    "child_hash": "abc123def456",
    "guardian_id": 1,
    "created": "2026-02-22T10:45:00+00:00"
}
```

---

### Mark Messages Read
- **URL:** `/api/mobile/child/<child_hash>/chat/mark-read/`
- **Method:** `POST`
- **Auth:** Guardian (header) or Child (header)

**Request:**
```json
{
    "message_ids": [100, 101, 102],
    "guardian_id": 1
}
```
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message_ids` | array | No | Specific message IDs to mark read (all if omitted) |
| `guardian_id` | integer | **Yes** (for child) | Required when authenticating as child |

**Response:**
```json
{
    "status": "ok",
    "marked_read": 3,
    "child_hash": "abc123def456"
}
```

---

### Unread Message Counts
- **URL:** `/api/mobile/chat/unread/`
- **Method:** `GET`
- **Auth:** Guardian (header) or Child (header)

**Response (Guardian):**
```json
{
    "status": "ok",
    "user_type": "guardian",
    "conversations": [
        {
            "child_hash": "abc123def456",
            "child_name": "John Doe",
            "unread_count": 3
        },
        {
            "child_hash": "xyz789abc",
            "child_name": "Jane Jr",
            "unread_count": 0
        }
    ],
    "total_unread": 3
}
```

**Response (Child):**
```json
{
    "status": "ok",
    "user_type": "child",
    "child_hash": "abc123def456",
    "conversations": [
        {
            "guardian_id": 1,
            "guardian_name": "Jane Doe",
            "guardian_email": "jane@example.com",
            "unread_count": 2
        }
    ],
    "total_unread": 2
}
```

---

## 5. Task Endpoints

### Guardian Create Task
- **URL:** `/api/mobile/child/<child_hash>/tasks/`
- **Method:** `POST`
- **Auth:** Guardian (header)

**Request:**
```json
{
    "title": "Complete homework",
    "description": "Finish math homework before asking for more screen time"
}
```

**Response (201 Created):**
```json
{
    "status": "ok",
    "task": {
        "id": 15,
        "title": "Complete homework",
        "description": "Finish math homework before asking for more screen time",
        "is_completed": false,
        "created": "2026-02-22T10:30:00+00:00"
    }
}
```

---

### Guardian View Child Tasks
- **URL:** `/api/mobile/child/<child_hash>/tasks/list/`
- **Method:** `GET`
- **Auth:** Guardian (header)

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `completed` | string | `all` | Filter: `true`, `false`, or `all` |

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "child_name": "John Doe",
    "total_tasks": 2,
    "tasks": [
        {
            "id": 15,
            "title": "Complete homework",
            "description": "Finish math homework",
            "is_completed": false,
            "completed_at": null,
            "created": "2026-02-22T10:30:00+00:00",
            "updated": "2026-02-22T10:30:00+00:00"
        },
        {
            "id": 14,
            "title": "Clean room",
            "description": "Tidy up your bedroom",
            "is_completed": true,
            "completed_at": "2026-02-21T15:00:00+00:00",
            "created": "2026-02-21T10:00:00+00:00",
            "updated": "2026-02-21T15:00:00+00:00"
        }
    ]
}
```

---

### Child View Tasks
- **URL:** `/api/mobile/child/<child_hash>/my-tasks/`
- **Method:** `GET`
- **Auth:** Child (header)

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `completed` | string | `all` | Filter: `true`, `false`, or `all` |

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "total_tasks": 2,
    "pending_tasks": 1,
    "completed_tasks": 1,
    "tasks": [
        {
            "id": 15,
            "title": "Complete homework",
            "description": "Finish math homework",
            "is_completed": false,
            "completed_at": null,
            "created": "2026-02-22T10:30:00+00:00",
            "assigned_by": "Jane Doe"
        }
    ]
}
```

---

### Child Mark Task Complete
- **URL:** `/api/mobile/child/<child_hash>/tasks/<task_id>/complete/`
- **Method:** `POST`
- **Auth:** Child (header)

**Response:**
```json
{
    "status": "ok",
    "message": "Task marked as completed",
    "task": {
        "id": 15,
        "title": "Complete homework",
        "description": "Finish math homework",
        "is_completed": true,
        "completed_at": "2026-02-22T11:30:00+00:00"
    }
}
```

---

### Child Mark Task Incomplete
- **URL:** `/api/mobile/child/<child_hash>/tasks/<task_id>/incomplete/`
- **Method:** `POST`
- **Auth:** Child (header)

**Response:**
```json
{
    "status": "ok",
    "message": "Task marked as incomplete",
    "task": {
        "id": 15,
        "title": "Complete homework",
        "description": "Finish math homework",
        "is_completed": false,
        "completed_at": null
    }
}
```

---

## 6. AI Alert Endpoints

### Ingest Data (Child Device → Server)
- **URL:** `/api/ingest/`
- **Method:** `POST`
- **Auth:** Child (header)
- **Description:** HTTP fallback endpoint for child device data ingestion (prefer WebSocket)

**Request:**
```json
{
    "data_type": "ai_alert",
    "payload": { ... }
}
```

#### AI Alert Payload
```json
{
    "data_type": "ai_alert",
    "payload": {
        "id": "alert_12345",
        "timestamp": "2026-02-22T10:30:00Z",
        "risk_score": 0.85,
        "content_type": "inappropriate_content",
        "summary": "Potentially harmful content detected in chat app",
        "detected_content": "...",
        "source_app": "com.example.chatapp"
    }
}
```
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | **Yes** | Unique alert identifier |
| `timestamp` | string | **Yes** | ISO 8601 timestamp |
| `risk_score` | number | **Yes** | Risk score (0-1) |
| `content_type` | string | **Yes** | Type of content detected |
| `summary` | string | **Yes** | Alert summary |
| `detected_content` | string | No | Actual detected content |
| `source_app` | string | No | App package name |

**Response:**
```json
{
    "status": "success",
    "message": "Alert stored and guardian notified",
    "alert_id": "alert_12345"
}
```

#### Screen Time Payload
```json
{
    "data_type": "screen_time",
    "payload": {
        "date": "2026-02-22",
        "total_screen_time": 7200,
        "app_wise_data": {
            "com.youtube": {"0": 1800, "1": 1200},
            "com.tiktok": {"0": 900, "1": 600}
        }
    }
}
```

**Response:**
```json
{
    "status": "success",
    "message": "Screen time data stored",
    "apps_processed": 2
}
```

#### Location Payload
```json
{
    "data_type": "location",
    "payload": {
        "timestamp": "2026-02-22T10:30:00Z",
        "latitude": 40.7128,
        "longitude": -74.0060
    }
}
```

**Response:**
```json
{
    "status": "success",
    "message": "Location stored"
}
```

#### Site Access Payload
```json
{
    "data_type": "site_access",
    "payload": {
        "logs": [
            {
                "timestamp": "2026-02-22T10:30:00Z",
                "url": "https://youtube.com",
                "accessed": true
            },
            {
                "timestamp": "2026-02-22T10:35:00Z",
                "url": "https://blocked-site.com",
                "accessed": false
            }
        ]
    }
}
```

**Response:**
```json
{
    "status": "success",
    "message": "Site access logs stored",
    "entries_processed": 2
}
```

---

### Get Alerts (Guardian)
- **URL:** `/api/mobile/child/<child_hash>/alerts/`
- **Method:** `GET`
- **Auth:** Guardian (header)

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `start_date` | string | 30 days ago | Start date (YYYY-MM-DD) |
| `end_date` | string | today | End date (YYYY-MM-DD) |
| `severity` | string | `all` | Filter: `high`, `medium`, `low`, `all` |
| `content_type` | string | `all` | Filter by content type |
| `limit` | integer | 50 | Max alerts to return |

**Response:**
```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "child_name": "John Doe",
    "date_range": {
        "start_date": "2026-01-23",
        "end_date": "2026-02-22"
    },
    "alerts": [
        {
            "id": "alert_12345",
            "timestamp": "2026-02-22T10:30:00+00:00",
            "risk_score": 0.85,
            "severity": "high",
            "content_type": "inappropriate_content",
            "summary": "Potentially harmful content detected",
            "detected_content": "...",
            "source_app": "com.example.chatapp",
            "is_acknowledged": false,
            "acknowledged_at": null
        }
    ],
    "summary": {
        "total_count": 15,
        "high_count": 3,
        "medium_count": 7,
        "low_count": 5,
        "returned_count": 1
    }
}
```

---

## Error Responses

All endpoints return errors in a consistent format:

```json
{
    "status": "error",
    "message": "Description of the error"
}
```

Common HTTP status codes:
| Code | Description |
|------|-------------|
| 400 | Bad Request - Invalid or missing parameters |
| 401 | Unauthorized - Authentication required or invalid |
| 403 | Forbidden - Access denied |
| 404 | Not Found - Resource does not exist |
| 500 | Internal Server Error |

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (see view decorators for limits).
- All timestamps are in ISO 8601 format.
- Encrypted fields contain base64-encoded encrypted data for E2E encryption.

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

#### Messages FROM Child Device (Sending)

- **Time Extension Request:**
	```json
	{
		"type": "time_extension_request",
		"data": {
			"app_domain": "youtube.com",
			"requested_hours": 2,
			"message_encrypted": "base64_encrypted_message_here",
			"guardian_id": 123
		}
	}
	```
	| Field | Type | Required | Description |
	|-------|------|----------|-------------|
	| `app_domain` | string | **Yes** | App or website domain requesting extra time |
	| `requested_hours` | number | **Yes** | Number of additional hours requested |
	| `message_encrypted` | string | No | Optional encrypted message to guardian (default: empty string) |
	| `guardian_id` | integer | No | Specific guardian to send request to (uses default guardian if omitted) |

- **Ping (Keep-alive):**
	```json
	{
		"type": "ping"
	}
	```

#### Messages TO Child Device (Receiving)

- **Connection Established** (on successful connect):
	```json
	{
		"type": "connection_established",
		"child_hash": "abc123def456",
		"message": "Time extension WebSocket connected"
	}
	```

- **Request Created** (after sending a time extension request):
	```json
	{
		"type": "request_created",
		"request_id": 42,
		"status": "pending",
		"message": "Request sent to guardian"
	}
	```

- **Time Extension Response** (when guardian responds):
	```json
	{
		"type": "time_extension_response",
		"data": {
			"request_id": 42,
			"status": "approved",
			"granted_hours": 1,
			"response_encrypted": "base64_encrypted_response",
			"app_domain": "youtube.com"
		}
	}
	```
	| `status` values | Description |
	|-----------------|-------------|
	| `approved` | Guardian approved the request |
	| `denied` | Guardian denied the request |
	| `responded` | Guardian sent a message only (no approval/denial) |

- **Pong** (response to ping):
	```json
	{
		"type": "pong"
	}
	```

- **Error:**
	```json
	{
		"type": "error",
		"message": "app_domain and requested_hours are required"
	}
	```

#### Connection Codes
| Code | Description |
|------|-------------|
| 4000 | Internal server error during child verification |
| 4004 | Child not found (invalid child_hash) |

#### Complete Flow Example
```json
// 1. Child connects → receives:
{"type": "connection_established", "child_hash": "abc123", "message": "Time extension WebSocket connected"}

// 2. Child sends request:
{"type": "time_extension_request", "data": {"app_domain": "tiktok.com", "requested_hours": 1, "message_encrypted": "UGxlYXNl..."}}

// 3. Child receives acknowledgment:
{"type": "request_created", "request_id": 42, "status": "pending", "message": "Request sent to guardian"}

// 4. When guardian responds, child receives:
{"type": "time_extension_response", "data": {"request_id": 42, "status": "approved", "granted_hours": 1, "response_encrypted": "", "app_domain": "tiktok.com"}}
```

### c. Guardian Time Extension WebSocket
- **URL:** `ws://<domain>/ws/guardian/time-extension/`
- **Consumer:** `GuardianTimeExtensionConsumer`
- **Description:** Guardians receive time extension requests from children and send responses in real time. Authentication is required.

#### Authentication (required before any other messages)
- **Send:**
	```json
	{
		"type": "auth",
		"email": "guardian@example.com",
		"password": "your_password"
	}
	```
- **Response on success:**
	```json
	{
		"type": "auth_success",
		"guardian_id": 1,
		"email": "guardian@example.com",
		"message": "Authentication successful"
	}
	```
- **Response on failure:**
	```json
	{
		"type": "error",
		"message": "Invalid credentials"
	}
	```

#### Messages FROM Guardian Device (Sending)

- **Respond to Time Extension Request:**
	```json
	{
		"type": "time_extension_response",
		"data": {
			"request_id": 42,
			"action": "approve",
			"granted_hours": 1,
			"response_encrypted": "base64_encrypted_response"
		}
	}
	```
	| Field | Type | Required | Description |
	|-------|------|----------|-------------|
	| `request_id` | integer | **Yes** | ID of the time extension request |
	| `action` | string | **Yes** | One of: `approve`, `deny`, `message` |
	| `granted_hours` | number | **Yes** (if approve) | Hours granted (required when action is `approve`) |
	| `response_encrypted` | string | No | Optional encrypted response message (default: empty string) |

- **Get Pending Requests:**
	```json
	{
		"type": "get_pending_requests"
	}
	```

- **Ping (Keep-alive):**
	```json
	{
		"type": "ping"
	}
	```

#### Messages TO Guardian Device (Receiving)

- **Auth Required** (on connect, before authentication):
	```json
	{
		"type": "auth_required",
		"message": "Please authenticate with email and password"
	}
	```

- **Time Extension Request** (incoming request from child):
	```json
	{
		"type": "time_extension_request",
		"data": {
			"request_id": 42,
			"child_hash": "abc123def456",
			"child_name": "John Doe",
			"app_domain": "youtube.com",
			"requested_hours": 2,
			"message_encrypted": "base64_encrypted_message",
			"created": "2026-02-22T10:30:00+00:00"
		}
	}
	```

- **Pending Requests** (sent after auth and on `get_pending_requests`):
	```json
	{
		"type": "pending_requests",
		"count": 2,
		"requests": [
			{
				"request_id": 42,
				"child_hash": "abc123def456",
				"child_name": "John Doe",
				"app_domain": "youtube.com",
				"requested_hours": 2,
				"message_encrypted": "base64_encrypted_message",
				"created": "2026-02-22T10:30:00+00:00"
			}
		]
	}
	```

- **Response Sent** (confirmation after responding):
	```json
	{
		"type": "response_sent",
		"request_id": 42,
		"status": "approved",
		"message": "Response sent to child"
	}
	```

- **Pong** (response to ping):
	```json
	{
		"type": "pong"
	}
	```

- **Error:**
	```json
	{
		"type": "error",
		"message": "request_id and action are required"
	}
	```

#### Connection Codes
| Code | Description |
|------|-------------|
| 4001 | Authentication failed (invalid credentials) |

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
