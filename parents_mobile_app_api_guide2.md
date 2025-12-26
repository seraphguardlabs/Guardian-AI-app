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
