# AI Data Sharing API Guide

This document specifies the API endpoint requirements for sharing data collected by the Guardian AI system on child devices. The data is collected in real-time and transmitted to the backend server for guardian access.

---

## Overview

The Guardian AI system collects the following types of data from child devices:

| Data Category | Collection Method | Frequency |
|---------------|-------------------|-----------|
| **Screen Time** | App usage monitoring | Every 10 seconds |
| **Location** | GPS coordinates | Every 30 seconds |
| **Site Access** | Website/URL tracking | Every 15 seconds |
| **Text Analysis** | AI-powered content analysis | On-demand |
| **Behavior Alerts** | AI-powered risk detection | Real-time |

---

## Authentication

### Child Device Authentication

Child devices authenticate using their unique child hash:

**Headers:**
```
X-Child-Hash: <child_hash>
```

**OR JSON Body:**
```json
{
  "child_hash": "<child_hash>"
}
```

### Guardian Authentication

Guardians access child data using:

**Headers:**
```
X-Email: parent@example.com
X-Password: your_password
```

---

## Data Ingestion Endpoints (Child Device → Server)

These endpoints are used by the child device to upload AI-collected data.

### 1. WebSocket Data Ingestion (Recommended)

Real-time data transmission via persistent WebSocket connection.

**WebSocket URL:** `ws://<domain>/ws/ingest/<child_hash>/`

**Alternative with Auth Flow:** `ws://<domain>/ws/ingest-auth/`

#### Connection Flow

1. **Connect** - Establish WebSocket connection
2. **Receive Acknowledgment** - Server confirms connection
3. **Send Data** - Transmit data messages
4. **Receive Confirmation** - Server confirms storage

#### Message Types

##### a) Screen Time Data

Send app usage statistics to the server.

**Message Format:**
```json
{
  "type": "screen_time",
  "data": {
    "date": "2026-01-26",
    "total_screen_time": 7200,
    "app_wise_data": {
      "com.instagram.android": {
        "10": 1800,
        "11": 2400
      },
      "com.youtube.android": {
        "10": 900,
        "11": 1200
      }
    }
  }
}
```

**Data Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `date` | string | Yes | Date in YYYY-MM-DD format |
| `total_screen_time` | integer | Yes | Total screen time in seconds |
| `app_wise_data` | object | Yes | Per-app usage breakdown |
| `app_wise_data.<package>` | object | Yes | Package name as key |
| `app_wise_data.<package>.<hour>` | integer | Yes | Seconds used in that hour (00-23) |

**Server Response:**
```json
{
  "type": "screen_time_ack",
  "status": "success",
  "message": "Screen time data stored",
  "apps_processed": 2
}
```

---

##### b) Location Data

Send GPS location updates.

**Message Format:**
```json
{
  "type": "location",
  "data": {
    "timestamp": "2026-01-26T12:30:00+05:30",
    "latitude": 28.6139,
    "longitude": 77.2090
  }
}
```

**Data Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | string | Yes | ISO 8601 timestamp |
| `latitude` | float | Yes | GPS latitude (-90 to 90) |
| `longitude` | float | Yes | GPS longitude (-180 to 180) |

**Server Response:**
```json
{
  "type": "location_ack",
  "status": "success",
  "message": "Location stored"
}
```

---

##### c) Site Access Logs

Send website access/block events.

**Message Format:**
```json
{
  "type": "site_access",
  "data": {
    "logs": [
      {
        "timestamp": "2026-01-26T10:45:00+05:30",
        "url": "https://youtube.com/watch?v=abc123",
        "accessed": true
      },
      {
        "timestamp": "2026-01-26T10:50:00+05:30",
        "url": "https://blocked-site.com",
        "accessed": false
      }
    ]
  }
}
```

**Data Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `logs` | array | Yes | Array of site access log entries |
| `logs[].timestamp` | string | Yes | ISO 8601 timestamp |
| `logs[].url` | string | Yes | Full URL accessed or blocked |
| `logs[].accessed` | boolean | Yes | `true` if allowed, `false` if blocked |

**Server Response:**
```json
{
  "type": "site_access_ack",
  "status": "success",
  "message": "Site access logs stored",
  "entries_processed": 2
}
```

---

##### d) AI Alert Data

Send AI-detected risk alerts (predatory text, harmful content, suspicious behavior).

**Message Format:**
```json
{
  "type": "ai_alert",
  "data": {
    "id": "alert_uuid_12345",
    "timestamp": "2026-01-26T14:30:00+05:30",
    "risk_score": 75,
    "severity": "HIGH",
    "content_type": "TEXT",
    "summary": "Potentially predatory message detected in chat app",
    "detected_content": "<encrypted_or_hashed_content>",
    "source_app": "com.whatsapp",
    "child_hash": "abc123xyz",
    "child_name": "Emma"
  }
}
```

**Data Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique alert identifier (UUID) |
| `timestamp` | string | Yes | ISO 8601 timestamp |
| `risk_score` | integer | Yes | Risk score (0-100) |
| `severity` | string | Yes | `HIGH`, `MEDIUM`, or `LOW` |
| `content_type` | string | Yes | `TEXT`, `IMAGE`, or `BEHAVIOR` |
| `summary` | string | Yes | Human-readable alert summary |
| `detected_content` | string | No | The content that triggered the alert |
| `source_app` | string | No | Package name of source app |
| `child_hash` | string | Yes | Child identifier |
| `child_name` | string | Yes | Child's display name |

**Severity Thresholds:**
- **HIGH**: `risk_score >= 70`
- **MEDIUM**: `risk_score >= 40 && risk_score < 70`
- **LOW**: `risk_score < 40`

**Server Response:**
```json
{
  "type": "ai_alert_ack",
  "status": "success",
  "message": "Alert stored and guardian notified",
  "alert_id": "alert_uuid_12345"
}
```

---

### 2. HTTP Fallback Endpoint

Use when WebSocket connection fails.

**Endpoint:** `POST /api/ingest/`

**Headers:**
```
Content-Type: application/json
X-Child-Hash: <child_hash>
```

**Request Body:**
```json
{
  "child_hash": "abc123xyz",
  "data_type": "screen_time",
  "payload": {
    "date": "2026-01-26",
    "total_screen_time": 7200,
    "app_wise_data": { ... }
  }
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Data ingested successfully"
}
```

**Supported `data_type` values:**
- `screen_time`
- `location`
- `site_access`
- `ai_alert`

---

## Data Retrieval Endpoints (Guardian → Server)

These endpoints allow guardians to retrieve AI-collected data.

### 3. Get Child Metrics (Aggregated Overview)

**Endpoint:** `GET /api/mobile/child/<child_hash>/metrics/`

**Query Parameters:**

| Parameter | Format | Default | Description |
|-----------|--------|---------|-------------|
| `start_date` | YYYY-MM-DD | 30 days ago | Start of date range |
| `end_date` | YYYY-MM-DD | Today | End of date range |

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-27",
    "end_date": "2026-01-26",
    "days": 31
  },
  "metrics": {
    "total_screen_time_seconds": 259200,
    "total_screen_time_formatted": "72h 0m",
    "daily_average_seconds": 8361,
    "daily_average_formatted": "2h 19m",
    "unique_apps_used": 15,
    "latest_location": {
      "latitude": 28.6139,
      "longitude": 77.2090,
      "timestamp": "2026-01-26T12:30:00Z",
      "address": "New Delhi, India"
    },
    "site_access": {
      "total_blocked": 12,
      "total_accessed": 145,
      "total": 157
    },
    "ai_alerts": {
      "total": 3,
      "high_severity": 1,
      "medium_severity": 1,
      "low_severity": 1
    }
  }
}
```

---

### 4. Get Screen Time Trend Data

**Endpoint:** `GET /api/mobile/child/<child_hash>/screen-time/`

**Query Parameters:**
- `start_date` (default: 30 days ago)
- `end_date` (default: today)

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2026-01-20",
    "end_date": "2026-01-26"
  },
  "trend": [
    {
      "date": "2026-01-20",
      "total_seconds": 10800,
      "formatted": "3h 0m",
      "app_count": 8
    },
    {
      "date": "2026-01-21",
      "total_seconds": 14400,
      "formatted": "4h 0m",
      "app_count": 12
    }
  ],
  "summary": {
    "total_seconds": 86400,
    "total_formatted": "24h 0m",
    "average_seconds": 10800,
    "average_formatted": "3h 0m",
    "max_seconds": 14400,
    "max_date": "2026-01-21",
    "min_seconds": 7200,
    "min_date": "2026-01-24",
    "days_with_data": 7
  }
}
```

---

### 5. Get App Usage Data

**Endpoint:** `GET /api/mobile/child/<child_hash>/app-usage/`

**Query Parameters:**
- `start_date` (default: 30 days ago)
- `end_date` (default: today)

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2026-01-01",
    "end_date": "2026-01-26"
  },
  "apps": [
    {
      "domain": "com.youtube.android",
      "name": "YouTube",
      "icon_url": "https://play-lh.googleusercontent.com/...",
      "total_seconds": 54000,
      "formatted": "15h 0m",
      "percentage": 25.5,
      "daily_average_seconds": 2077,
      "daily_average_formatted": "34m"
    },
    {
      "domain": "com.instagram.android",
      "name": "Instagram",
      "icon_url": "https://play-lh.googleusercontent.com/...",
      "total_seconds": 36000,
      "formatted": "10h 0m",
      "percentage": 17.0,
      "daily_average_seconds": 1385,
      "daily_average_formatted": "23m"
    }
  ],
  "summary": {
    "total_seconds": 211765,
    "total_formatted": "58h 49m",
    "app_count": 15,
    "most_used_app": {
      "domain": "com.youtube.android",
      "name": "YouTube",
      "seconds": 54000,
      "formatted": "15h 0m"
    }
  }
}
```

---

### 6. Get Location History

**Endpoint:** `GET /api/mobile/child/<child_hash>/locations/`

**Query Parameters:**

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `start_date` | 7 days ago | - | Start date |
| `end_date` | today | - | End date |
| `limit` | 100 | 1-500 | Max records to return |

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2026-01-20",
    "end_date": "2026-01-26"
  },
  "locations": [
    {
      "latitude": 28.6139,
      "longitude": 77.2090,
      "timestamp": "2026-01-26T14:30:00Z"
    },
    {
      "latitude": 28.5920,
      "longitude": 77.2195,
      "timestamp": "2026-01-26T12:15:00Z"
    }
  ],
  "summary": {
    "total_count": 156,
    "returned_count": 100,
    "unique_locations": 12,
    "limit_applied": 100
  }
}
```

---

### 7. Get Site Access Logs

**Endpoint:** `GET /api/mobile/child/<child_hash>/site-access/`

**Query Parameters:**

| Parameter | Default | Values | Description |
|-----------|---------|--------|-------------|
| `start_date` | 7 days ago | - | Start date |
| `end_date` | today | - | End date |
| `filter` | all | `all`, `accessed`, `blocked` | Filter by status |
| `limit` | 100 | 1-500 | Max records |

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2026-01-20",
    "end_date": "2026-01-26"
  },
  "filter_applied": "all",
  "logs": [
    {
      "url": "https://youtube.com/watch?v=abc123",
      "domain": "youtube.com",
      "timestamp": "2026-01-26T10:45:00Z",
      "accessed": true,
      "status": "accessed"
    },
    {
      "url": "https://blocked-site.com/page",
      "domain": "blocked-site.com",
      "timestamp": "2026-01-26T10:50:00Z",
      "accessed": false,
      "status": "blocked"
    }
  ],
  "summary": {
    "total_count": 157,
    "blocked_count": 12,
    "accessed_count": 145,
    "returned_count": 100,
    "unique_domains": 8,
    "limit_applied": 100
  }
}
```

---

### 8. Get AI Alerts

**Endpoint:** `GET /api/mobile/child/<child_hash>/alerts/`

**Query Parameters:**

| Parameter | Default | Values | Description |
|-----------|---------|--------|-------------|
| `start_date` | 30 days ago | - | Start date |
| `end_date` | today | - | End date |
| `severity` | all | `all`, `HIGH`, `MEDIUM`, `LOW` | Filter by severity |
| `content_type` | all | `all`, `TEXT`, `IMAGE`, `BEHAVIOR` | Filter by content type |
| `limit` | 50 | 1-200 | Max records |

**Response (200 OK):**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-27",
    "end_date": "2026-01-26"
  },
  "alerts": [
    {
      "id": "alert_uuid_12345",
      "timestamp": "2026-01-26T14:30:00Z",
      "risk_score": 75,
      "severity": "HIGH",
      "content_type": "TEXT",
      "summary": "Potentially predatory message detected in chat app",
      "detected_content": "<encrypted_content>",
      "source_app": "com.whatsapp"
    },
    {
      "id": "alert_uuid_12346",
      "timestamp": "2026-01-25T09:15:00Z",
      "risk_score": 55,
      "severity": "MEDIUM",
      "content_type": "BEHAVIOR",
      "summary": "Unusual app installation pattern detected",
      "detected_content": null,
      "source_app": null
    }
  ],
  "summary": {
    "total_count": 5,
    "high_count": 2,
    "medium_count": 2,
    "low_count": 1,
    "returned_count": 5
  }
}
```

---

## Real-Time Alert Notifications (WebSocket)

For real-time alert notifications to guardian devices.

### Guardian Alert WebSocket

**WebSocket URL:** `ws://<domain>/ws/guardian/alerts/`

**Connection Flow:**

1. **Connect**
2. **Authenticate:**
```json
{
  "type": "auth",
  "email": "parent@example.com",
  "password": "your_password"
}
```

3. **Receive Alerts (real-time):**
```json
{
  "type": "alert",
  "source": "parent",
  "data": {
    "id": "alert_uuid_12345",
    "timestamp": "2026-01-26T14:30:00Z",
    "risk_score": 75,
    "severity": "HIGH",
    "content_type": "TEXT",
    "summary": "Potentially predatory message detected",
    "detected_content": "<encrypted>",
    "child_hash": "abc123xyz",
    "child_name": "Emma"
  }
}
```

---

## Error Responses

All endpoints return consistent error responses:

### Common Error Format
```json
{
  "status": "error",
  "message": "Description of the error",
  "code": "ERROR_CODE"
}
```

### HTTP Status Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 200 | Success | Request processed successfully |
| 201 | Created | New record created |
| 400 | Bad Request | Invalid input data |
| 401 | Unauthorized | Invalid or missing credentials |
| 403 | Forbidden | Not authorized for this resource |
| 404 | Not Found | Child or resource not found |
| 405 | Method Not Allowed | Wrong HTTP method |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |

---

## Data Models Reference

### ScreenTimeData
```json
{
  "date": "string (YYYY-MM-DD)",
  "total_screen_time": "integer (seconds)",
  "app_wise_data": {
    "<package_name>": {
      "<hour>": "integer (seconds)"
    }
  }
}
```

### LocationData
```json
{
  "timestamp": "string (ISO 8601)",
  "latitude": "float (-90 to 90)",
  "longitude": "float (-180 to 180)"
}
```

### SiteAccessLog
```json
{
  "timestamp": "string (ISO 8601)",
  "url": "string",
  "accessed": "boolean"
}
```

### Alert
```json
{
  "id": "string (UUID)",
  "timestamp": "string (ISO 8601)",
  "risk_score": "integer (0-100)",
  "severity": "string (HIGH|MEDIUM|LOW)",
  "content_type": "string (TEXT|IMAGE|BEHAVIOR)",
  "summary": "string",
  "detected_content": "string (optional)",
  "child_hash": "string",
  "child_name": "string"
}
```

---

## Rate Limits

| Endpoint Type | Rate Limit |
|---------------|------------|
| WebSocket Data Ingestion | No limit (real-time) |
| HTTP Data Ingestion | 60 requests/minute per child |
| Data Retrieval (GET) | 120 requests/minute per guardian |

---

## Security Considerations

1. **Encryption**: All sensitive content in alerts should be encrypted using the guardian's public key
2. **HTTPS/WSS**: Use secure protocols in production
3. **Data Retention**: Data is retained for 365 days with automatic pruning
4. **Authentication**: All endpoints require proper authentication
5. **Child Hash**: Acts as a unique identifier but should not be exposed publicly

---

## Quick Reference

### Data Ingestion (Child → Server)

| Purpose | Method | Endpoint |
|---------|--------|----------|
| Real-time data | WebSocket | `ws://domain/ws/ingest/<child_hash>/` |
| With auth flow | WebSocket | `ws://domain/ws/ingest-auth/` |
| HTTP fallback | POST | `/api/ingest/` |

### Data Retrieval (Guardian)

| Purpose | Method | Endpoint |
|---------|--------|----------|
| Metrics Overview | GET | `/api/mobile/child/<hash>/metrics/` |
| Screen Time Trend | GET | `/api/mobile/child/<hash>/screen-time/` |
| App Usage | GET | `/api/mobile/child/<hash>/app-usage/` |
| Location History | GET | `/api/mobile/child/<hash>/locations/` |
| Site Access Logs | GET | `/api/mobile/child/<hash>/site-access/` |
| AI Alerts | GET | `/api/mobile/child/<hash>/alerts/` |

### WebSocket Message Types

| Type | Direction | Purpose |
|------|-----------|---------|
| `screen_time` | Child → Server | App usage data |
| `location` | Child → Server | GPS coordinates |
| `site_access` | Child → Server | Website logs |
| `ai_alert` | Child → Server | Risk detection alerts |
| `alert` | Server → Guardian | Real-time alert notification |

---

## Example Implementation (cURL)

### Send Screen Time (HTTP Fallback)
```bash
curl -X POST "http://localhost:8000/api/ingest/" \
  -H "Content-Type: application/json" \
  -H "X-Child-Hash: abc123xyz" \
  -d '{
    "child_hash": "abc123xyz",
    "data_type": "screen_time",
    "payload": {
      "date": "2026-01-26",
      "total_screen_time": 7200,
      "app_wise_data": {
        "com.instagram.android": {"10": 1800},
        "com.youtube.android": {"10": 900}
      }
    }
  }'
```

### Get AI Alerts (Guardian)
```bash
curl -X GET "http://localhost:8000/api/mobile/child/abc123xyz/alerts/?severity=HIGH&limit=10" \
  -H "X-Email: parent@example.com" \
  -H "X-Password: mypassword"
```

---

*Document Version: 1.0*  
*Last Updated: January 26, 2026*
