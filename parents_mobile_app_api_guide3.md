# Parents Mobile App API Endpoints Guide

This guide documents the API endpoints available for the Guardian AI mobile app for parents.

---

## Authentication

All endpoints require authentication using one of these methods:

### Header-Based Authentication (Recommended for Mobile)
Include these headers with every request:
```
X-Email: parent@example.com
X-Password: your_password
```

### Session Authentication
If the user is already logged in via web session, requests will be authenticated automatically.

---

## Common Query Parameters

All endpoints support date range filtering:

| Parameter | Format | Default | Description |
|-----------|--------|---------|-------------|
| `start_date` | `YYYY-MM-DD` | Varies by endpoint | Start of date range |
| `end_date` | `YYYY-MM-DD` | Current date | End of date range |

---

## Endpoints

### 1. Get All Children

Retrieve a list of all children registered under the authenticated guardian.

**Endpoint:** `GET /api/mobile/children/`

**Response:**
```json
{
  "status": "ok",
  "count": 2,
  "children": [
    {
      "child_hash": "abc123xyz",
      "first_name": "Emma",
      "last_name": "Smith",
      "full_name": "Emma Smith",
      "date_of_birth": "2015-05-20",
      "age": 10,
      "profile_image_url": "/media/child_profiles/abc123xyz.webp",
      "date_joined": "2025-01-15T10:30:00Z"
    }
  ]
}
```

---

### 2. Get Child Metrics (Aggregated Overview)

Get aggregated metrics for a specific child including screen time, location, and site access stats.

**Endpoint:** `GET /api/mobile/child/<child_hash>/metrics/`

**Query Parameters:**
- `start_date` - Default: 30 days ago
- `end_date` - Default: today

**Example:** `/api/mobile/child/abc123xyz/metrics/?start_date=2025-12-01&end_date=2025-12-23`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-01",
    "end_date": "2025-12-23",
    "days": 23
  },
  "metrics": {
    "total_screen_time_seconds": 259200,
    "total_screen_time_formatted": "72h 0m",
    "daily_average_seconds": 11270,
    "daily_average_formatted": "3h 7m",
    "unique_apps_used": 15,
    "latest_location": {
      "latitude": 37.7749,
      "longitude": -122.4194,
      "timestamp": "2025-12-23T14:30:00Z",
      "address": "San Francisco, CA, USA"
    },
    "site_access": {
      "total_blocked": 12,
      "total_accessed": 145,
      "total": 157
    }
  }
}
```

---

### 3. Screen Time Trend Data

Get detailed daily screen time trend data for charts and analysis.

**Endpoint:** `GET /api/mobile/child/<child_hash>/screen-time/`

**Query Parameters:**
- `start_date` - Default: 30 days ago
- `end_date` - Default: today

**Example:** `/api/mobile/child/abc123xyz/screen-time/?start_date=2025-12-16&end_date=2025-12-23`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-16",
    "end_date": "2025-12-23"
  },
  "trend": [
    {
      "date": "2025-12-16",
      "total_seconds": 10800,
      "formatted": "3h 0m",
      "app_count": 8
    },
    {
      "date": "2025-12-17",
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
    "max_formatted": "4h 0m",
    "max_date": "2025-12-17",
    "min_seconds": 7200,
    "min_formatted": "2h 0m",
    "min_date": "2025-12-20",
    "days_with_data": 8
  }
}
```

---

### 4. App Usage Data

Get detailed breakdown of app usage with time spent on each app.

**Endpoint:** `GET /api/mobile/child/<child_hash>/app-usage/`

**Query Parameters:**
- `start_date` - Default: 30 days ago
- `end_date` - Default: today

**Example:** `/api/mobile/child/abc123xyz/app-usage/?start_date=2025-12-01&end_date=2025-12-23`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-01",
    "end_date": "2025-12-23",
    "days": 23
  },
  "apps": [
    {
      "domain": "com.youtube.android",
      "name": "YouTube",
      "icon_url": "https://play-lh.googleusercontent.com/...",
      "total_seconds": 54000,
      "formatted": "15h 0m",
      "percentage": 25.5,
      "daily_average_seconds": 2348,
      "daily_average_formatted": "39m"
    },
    {
      "domain": "com.instagram.android",
      "name": "Instagram",
      "icon_url": "https://play-lh.googleusercontent.com/...",
      "total_seconds": 36000,
      "formatted": "10h 0m",
      "percentage": 17.0,
      "daily_average_seconds": 1565,
      "daily_average_formatted": "26m"
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

### 5. Location History

Get detailed location history data for the child.

**Endpoint:** `GET /api/mobile/child/<child_hash>/locations/`

**Query Parameters:**
- `start_date` - Default: 7 days ago
- `end_date` - Default: today
- `limit` - Max records to return (default: 100, max: 500)

**Example:** `/api/mobile/child/abc123xyz/locations/?start_date=2025-12-20&end_date=2025-12-23&limit=50`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-20",
    "end_date": "2025-12-23"
  },
  "locations": [
    {
      "latitude": 37.7749,
      "longitude": -122.4194,
      "timestamp": "2025-12-23T14:30:00Z"
    },
    {
      "latitude": 37.7751,
      "longitude": -122.4180,
      "timestamp": "2025-12-23T12:15:00Z"
    }
  ],
  "summary": {
    "total_count": 156,
    "returned_count": 50,
    "unique_locations": 12,
    "limit_applied": 50
  }
}
```

---

### 6. Site Access Logs

Get detailed logs of websites accessed or blocked.

**Endpoint:** `GET /api/mobile/child/<child_hash>/site-access/`

**Query Parameters:**
- `start_date` - Default: 7 days ago
- `end_date` - Default: today
- `filter` - Filter by status: `all`, `accessed`, `blocked` (default: `all`)
- `limit` - Max records to return (default: 100, max: 500)

**Example:** `/api/mobile/child/abc123xyz/site-access/?start_date=2025-12-20&end_date=2025-12-23&filter=blocked&limit=50`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "date_range": {
    "start_date": "2025-12-20",
    "end_date": "2025-12-23"
  },
  "filter_applied": "blocked",
  "logs": [
    {
      "url": "https://example-blocked-site.com/page",
      "domain": "example-blocked-site.com",
      "timestamp": "2025-12-23T10:45:00Z",
      "accessed": false,
      "status": "blocked"
    }
  ],
  "summary": {
    "total_count": 157,
    "blocked_count": 12,
    "accessed_count": 145,
    "returned_count": 12,
    "unique_domains": 8,
    "limit_applied": 50
  }
}
```

---

### 7. Restricted Apps (Screen Time Limits)

Get or update app-wise screen time restrictions for a child. This allows parents to set daily time limits on specific apps.

**Endpoint:** `GET/POST /api/mobile/child/<child_hash>/restricted-apps/`

#### GET - Retrieve Current Restrictions

**Example:** `/api/mobile/child/abc123xyz/restricted-apps/`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "restricted_apps": {
    "com.instagram.android": 2.0,
    "com.zhiliaoapp.musically": 1.5,
    "com.google.android.youtube": 3.0
  },
  "restricted_apps_detailed": [
    {
      "package": "com.instagram.android",
      "hours_limit": 2.0,
      "minutes_limit": 120,
      "name": "Instagram",
      "icon_url": "https://play-lh.googleusercontent.com/..."
    },
    {
      "package": "com.zhiliaoapp.musically",
      "hours_limit": 1.5,
      "minutes_limit": 90,
      "name": "TikTok",
      "icon_url": "https://play-lh.googleusercontent.com/..."
    }
  ],
  "total_restricted": 3
}
```

#### POST - Update Restrictions

There are multiple ways to update restrictions:

##### Option 1: Add a Single App Restriction

**Request Body:**
```json
{
  "action": "add",
  "package": "com.facebook.katana",
  "hours": 2.5
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "App com.facebook.katana restricted to 2.5 hours/day",
  "child_hash": "abc123xyz",
  "restricted_apps": {
    "com.instagram.android": 2.0,
    "com.facebook.katana": 2.5
  },
  "total_restricted": 2
}
```

##### Option 2: Update an Existing App's Time Limit

**Request Body:**
```json
{
  "action": "update",
  "package": "com.instagram.android",
  "hours": 1.0
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "App com.instagram.android limit updated to 1.0 hours/day",
  "child_hash": "abc123xyz",
  "restricted_apps": {
    "com.instagram.android": 1.0
  },
  "total_restricted": 1
}
```

##### Option 3: Remove an App Restriction

**Request Body:**
```json
{
  "action": "remove",
  "package": "com.instagram.android"
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "App com.instagram.android restriction removed",
  "child_hash": "abc123xyz",
  "restricted_apps": {},
  "total_restricted": 0
}
```

##### Option 4: Full Replacement (Set All Restrictions at Once)

**Request Body:**
```json
{
  "restricted_apps": {
    "com.instagram.android": 2.0,
    "com.zhiliaoapp.musically": 1.5,
    "com.google.android.youtube": 3.0,
    "com.facebook.katana": 1.0
  }
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Restricted apps updated successfully",
  "child_hash": "abc123xyz",
  "restricted_apps": {
    "com.instagram.android": 2.0,
    "com.zhiliaoapp.musically": 1.5,
    "com.google.android.youtube": 3.0,
    "com.facebook.katana": 1.0
  },
  "total_restricted": 4
}
```

#### Common App Package Names

| App | Package Name |
|-----|--------------|
| Facebook | `com.facebook.katana` |
| Instagram | `com.instagram.android` |
| TikTok | `com.zhiliaoapp.musically` |
| Snapchat | `com.snapchat.android` |
| YouTube | `com.google.android.youtube` |
| WhatsApp | `com.whatsapp` |
| Twitter/X | `com.twitter.android` |
| Messenger | `com.facebook.orca` |

---

## Error Responses

All endpoints return consistent error responses:

### Authentication Error (401)
```json
{
  "status": "error",
  "message": "Authentication required. Provide X-Email and X-Password headers."
}
```

### Invalid Credentials (401)
```json
{
  "status": "error",
  "message": "Invalid credentials"
}
```

### Child Not Found (404)
```json
{
  "status": "error",
  "message": "Child not found"
}
```

### Access Denied (403)
```json
{
  "status": "error",
  "message": "You do not have access to this child"
}
```

### Method Not Allowed (405)
```json
{
  "status": "error",
  "message": "GET method required"
}
```

---

## Quick Reference

| Endpoint | URL | Description |
|----------|-----|-------------|
| Children List | `GET /api/mobile/children/` | All children for guardian |
| Child Metrics | `GET /api/mobile/child/<hash>/metrics/` | Aggregated overview |
| Screen Time | `GET /api/mobile/child/<hash>/screen-time/` | Daily trend data |
| App Usage | `GET /api/mobile/child/<hash>/app-usage/` | Per-app breakdown |
| Locations | `GET /api/mobile/child/<hash>/locations/` | Location history |
| Site Access | `GET /api/mobile/child/<hash>/site-access/` | Site logs |
| Restricted Apps | `GET/POST /api/mobile/child/<hash>/restricted-apps/` | Manage app restrictions |

---

## Mobile App Integration Tips

1. **Cache child list** - The children list rarely changes, cache it locally
2. **Use date ranges** - Always specify date ranges to reduce payload size
3. **Paginate locations** - Use the `limit` parameter for location data
4. **Filter site logs** - Use `filter=blocked` to show only concerning activity
5. **Handle offline** - Store last successful responses for offline viewing
6. **Sync restrictions** - After setting app restrictions, verify with a GET request

---

## End-to-End Encryption

Guardian AI supports E2E encryption for secure communication between child and guardian devices. This is used primarily for the Time Extension Request feature.

### How E2E Encryption Works

1. Each child and guardian has an RSA key pair (2048-bit)
2. Keys are generated automatically on first access
3. Child encrypts messages using guardian's public key
4. Guardian encrypts responses using child's public key
5. Only the intended recipient can decrypt messages with their private key

### Getting Public Keys

#### Get Child's Public Key

**Endpoint:** `GET /api/mobile/child/<child_hash>/public-key/`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----"
}
```

#### Get Guardian's Public Key (Authenticated)

**Endpoint:** `GET /api/mobile/guardian/public-key/`

**Headers Required:**
```
X-Email: parent@example.com
X-Password: your_password
```

**Response:**
```json
{
  "status": "ok",
  "guardian_id": 123,
  "guardian_name": "John Smith",
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----"
}
```

#### Get Guardian's Public Key by ID (For Child Devices)

**Endpoint:** `GET /api/mobile/guardian/<guardian_id>/public-key/`

**Response:**
```json
{
  "status": "ok",
  "guardian_id": 123,
  "guardian_name": "John Smith",
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----"
}
```

#### Get All Guardian Public Keys for a Child

**Endpoint:** `GET /api/mobile/child/<child_hash>/guardians/public-keys/`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "child_name": "Emma Smith",
  "guardians": [
    {
      "guardian_id": 123,
      "guardian_name": "John Smith",
      "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----"
    },
    {
      "guardian_id": 124,
      "guardian_name": "Jane Smith",
      "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----"
    }
  ],
  "count": 2
}
```

---

## Time Extension Requests

When a child's daily limit for a time-restricted app is reached, the child device can request additional time from their guardian. This feature uses WebSocket connections for real-time communication and E2E encryption for secure message exchange.

### Overview

1. Child reaches daily limit for an app (e.g., Instagram)
2. Child device sends a time extension request with a message
3. Guardian receives the request in real-time via WebSocket
4. Guardian can approve (with hours), deny, or respond with a message
5. Child receives the response in real-time
6. If approved, the app's daily limit is automatically extended

### REST API Endpoints

#### Get Time Extension Requests (Guardian)

**Endpoint:** `GET /api/mobile/time-extension-requests/`

**Headers Required:**
```
X-Email: parent@example.com
X-Password: your_password
```

**Query Parameters:**
- `status` - Filter by status: `pending`, `approved`, `denied`, `responded`, `all` (default: `pending`)

**Response:**
```json
{
  "status": "ok",
  "guardian_id": 123,
  "filter": "pending",
  "requests": [
    {
      "request_id": 456,
      "child_hash": "abc123xyz",
      "child_name": "Emma Smith",
      "app_domain": "com.instagram.android",
      "requested_hours": 1.5,
      "message_encrypted": "<base64 encrypted message>",
      "status": "pending",
      "granted_hours": null,
      "created": "2025-12-27T10:30:00Z",
      "responded_at": null
    }
  ],
  "count": 1
}
```

#### Get Time Extension Requests (Child)

**Endpoint:** `GET /api/mobile/child/<child_hash>/time-extension-requests/`

**Response:**
```json
{
  "status": "ok",
  "child_hash": "abc123xyz",
  "requests": [
    {
      "request_id": 456,
      "app_domain": "com.instagram.android",
      "requested_hours": 1.5,
      "status": "approved",
      "granted_hours": 1.0,
      "response_encrypted": "<base64 encrypted message>",
      "created": "2025-12-27T10:30:00Z",
      "responded_at": "2025-12-27T10:35:00Z",
      "guardian_id": 123,
      "guardian_name": "John Smith"
    }
  ],
  "count": 1
}
```

#### Respond to Time Extension Request

**Endpoint:** `POST /api/mobile/time-extension-requests/<request_id>/respond/`

**Headers Required:**
```
X-Email: parent@example.com
X-Password: your_password
```

**Request Body (Approve):**
```json
{
  "action": "approve",
  "granted_hours": 1.0,
  "response_encrypted": "<base64 encrypted message>"
}
```

**Request Body (Deny):**
```json
{
  "action": "deny",
  "response_encrypted": "<base64 encrypted message>"
}
```

**Request Body (Message Only):**
```json
{
  "action": "message",
  "response_encrypted": "<base64 encrypted message>"
}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Request approved",
  "request_id": 456,
  "action": "approve",
  "granted_hours": 1.0,
  "child_hash": "abc123xyz",
  "app_domain": "com.instagram.android",
  "new_app_limit": 3.5
}
```

---

### WebSocket API for Time Extension Requests

For real-time communication, use WebSocket connections. This is recommended over polling the REST API.

#### Child Device WebSocket

**Connection URL:** `ws://domain/ws/child/<child_hash>/time-extension/`

**On Connect:**
```json
{
  "type": "connection_established",
  "child_hash": "abc123xyz",
  "message": "Time extension WebSocket connected"
}
```

**Sending a Request:**
```json
{
  "type": "time_extension_request",
  "data": {
    "app_domain": "com.instagram.android",
    "requested_hours": 1.5,
    "message_encrypted": "<base64 message encrypted with guardian's public key>",
    "guardian_id": 123
  }
}
```

Note: `guardian_id` is optional. If not provided, the request goes to the first linked guardian.

**Request Created Response:**
```json
{
  "type": "request_created",
  "request_id": 456,
  "status": "pending",
  "message": "Request sent to guardian"
}
```

**Receiving Guardian Response:**
```json
{
  "type": "time_extension_response",
  "data": {
    "request_id": 456,
    "status": "approved",
    "granted_hours": 1.0,
    "response_encrypted": "<base64 message encrypted with child's public key>",
    "app_domain": "com.instagram.android"
  }
}
```

#### Guardian Device WebSocket

**Connection URL:** `ws://domain/ws/guardian/time-extension/`

**On Connect:**
```json
{
  "type": "auth_required",
  "message": "Please authenticate with email and password"
}
```

**Authentication:**
```json
{
  "type": "auth",
  "email": "parent@example.com",
  "password": "your_password"
}
```

**Auth Success Response:**
```json
{
  "type": "auth_success",
  "guardian_id": 123,
  "email": "parent@example.com",
  "message": "Authentication successful"
}
```

**Pending Requests (sent automatically after auth):**
```json
{
  "type": "pending_requests",
  "count": 2,
  "requests": [
    {
      "request_id": 456,
      "child_hash": "abc123xyz",
      "child_name": "Emma Smith",
      "app_domain": "com.instagram.android",
      "requested_hours": 1.5,
      "message_encrypted": "<base64 encrypted message>",
      "created": "2025-12-27T10:30:00Z"
    }
  ]
}
```

**Get Pending Requests Manually:**
```json
{
  "type": "get_pending_requests"
}
```

**Receiving New Request (real-time):**
```json
{
  "type": "time_extension_request",
  "data": {
    "request_id": 456,
    "child_hash": "abc123xyz",
    "child_name": "Emma Smith",
    "app_domain": "com.instagram.android",
    "requested_hours": 1.5,
    "message_encrypted": "<base64 encrypted message>",
    "created": "2025-12-27T10:30:00Z"
  }
}
```

**Sending Response (Approve):**
```json
{
  "type": "time_extension_response",
  "data": {
    "request_id": 456,
    "action": "approve",
    "granted_hours": 1.0,
    "response_encrypted": "<base64 message encrypted with child's public key>"
  }
}
```

**Sending Response (Deny):**
```json
{
  "type": "time_extension_response",
  "data": {
    "request_id": 456,
    "action": "deny",
    "response_encrypted": "<optional encrypted message>"
  }
}
```

**Sending Response (Message Only):**
```json
{
  "type": "time_extension_response",
  "data": {
    "request_id": 456,
    "action": "message",
    "response_encrypted": "<encrypted custom message>"
  }
}
```

**Response Confirmation:**
```json
{
  "type": "response_sent",
  "request_id": 456,
  "status": "approved",
  "message": "Response sent to child"
}
```

---

### Time Extension Flow Example

Here's a complete example of the time extension request flow:

#### 1. Child Device Setup

```python
import asyncio
import websockets
import json
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import padding
import base64

# Get guardian's public key first
guardian_public_key = get_guardian_public_key()  # from REST API

# Encrypt the message
message = "Please can I have more time? I'm doing homework."
encrypted = guardian_public_key.encrypt(
    message.encode(),
    padding.OAEP(
        mgf=padding.MGF1(algorithm=hashes.SHA256()),
        algorithm=hashes.SHA256(),
        label=None
    )
)
message_encrypted = base64.b64encode(encrypted).decode()

# Connect to WebSocket
async with websockets.connect(f"ws://server/ws/child/{child_hash}/time-extension/") as ws:
    # Send request
    await ws.send(json.dumps({
        "type": "time_extension_request",
        "data": {
            "app_domain": "com.instagram.android",
            "requested_hours": 1.5,
            "message_encrypted": message_encrypted
        }
    }))
    
    # Wait for response
    response = await ws.recv()
    print(f"Response: {response}")
```

#### 2. Guardian Device Setup

```python
import asyncio
import websockets
import json

async with websockets.connect("ws://server/ws/guardian/time-extension/") as ws:
    # Wait for auth request
    msg = await ws.recv()
    
    # Authenticate
    await ws.send(json.dumps({
        "type": "auth",
        "email": "parent@example.com",
        "password": "password"
    }))
    
    # Receive auth success and pending requests
    auth_response = await ws.recv()
    pending = await ws.recv()
    
    # Listen for new requests
    while True:
        msg = json.loads(await ws.recv())
        
        if msg["type"] == "time_extension_request":
            request = msg["data"]
            print(f"New request from {request['child_name']}")
            print(f"App: {request['app_domain']}")
            print(f"Requested: {request['requested_hours']} hours")
            
            # Decrypt and read message (using your private key)
            # ... decryption code ...
            
            # Approve the request
            await ws.send(json.dumps({
                "type": "time_extension_response",
                "data": {
                    "request_id": request["request_id"],
                    "action": "approve",
                    "granted_hours": 1.0,
                    "response_encrypted": "<encrypted response>"
                }
            }))
```

---

## Quick Reference (Updated)

| Endpoint | URL | Description |
|----------|-----|-------------|
| Children List | `GET /api/mobile/children/` | All children for guardian |
| Child Metrics | `GET /api/mobile/child/<hash>/metrics/` | Aggregated overview |
| Screen Time | `GET /api/mobile/child/<hash>/screen-time/` | Daily trend data |
| App Usage | `GET /api/mobile/child/<hash>/app-usage/` | Per-app breakdown |
| Locations | `GET /api/mobile/child/<hash>/locations/` | Location history |
| Site Access | `GET /api/mobile/child/<hash>/site-access/` | Site logs |
| Restricted Apps | `GET/POST /api/mobile/child/<hash>/restricted-apps/` | Manage app restrictions |
| Child Public Key | `GET /api/mobile/child/<hash>/public-key/` | Get child's encryption key |
| Guardian Public Key | `GET /api/mobile/guardian/public-key/` | Get guardian's encryption key |
| Guardian Public Key (by ID) | `GET /api/mobile/guardian/<id>/public-key/` | Get specific guardian's key |
| Child's Guardians Keys | `GET /api/mobile/child/<hash>/guardians/public-keys/` | All linked guardians' keys |
| Time Extension Requests (Guardian) | `GET /api/mobile/time-extension-requests/` | Guardian's pending requests |
| Time Extension Requests (Child) | `GET /api/mobile/child/<hash>/time-extension-requests/` | Child's request history |
| Respond to Request | `POST /api/mobile/time-extension-requests/<id>/respond/` | Approve/deny request |

### WebSocket Endpoints

| Purpose | URL | Description |
|---------|-----|-------------|
| Child Time Extension | `ws://domain/ws/child/<hash>/time-extension/` | Send requests, receive responses |
| Guardian Time Extension | `ws://domain/ws/guardian/time-extension/` | Receive requests, send responses |
| Child Data Ingest | `ws://domain/ws/ingest/<hash>/` | Send screen time, location, site logs |
| Auth Data Ingest | `ws://domain/ws/ingest-auth/` | Alternative ingest with auth flow |
