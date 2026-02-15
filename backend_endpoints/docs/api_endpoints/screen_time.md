# Screen Time Management API Endpoints

This document describes the API endpoints for the `screen_time` app, including dashboard, restricted apps, mobile, and child device APIs. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard API Endpoints
- **Chart Data**
	- **URL:** `/screen_time/dashboard/chart-data/<child_hash>/`
	- **Method:** `GET`
	- **Auth:** Session (guardian login required)
	- **Description:** Get chart data for a child's screen time (line, bar, and app list data)
- **Stats Data**
	- **URL:** `/screen_time/dashboard/stats/<child_hash>/`
	- **Method:** `GET`
	- **Auth:** Session (guardian login required)
	- **Description:** Get statistics for a child's screen time, location, and site access

---

## 2. Restricted Apps API
- **Get Blocked Apps**
	- **URL:** `/screen_time/api/blocked-apps/<child_hash>/`
	- **Method:** `GET`
	- **Auth:** None (child device)
	- **Description:** Retrieve the list of restricted apps and exam mode status for a child
- **Update Blocked Apps**
	- **URL:** `/screen_time/api/blocked-apps/<child_hash>/update/`
	- **Method:** `POST`
	- **Auth:** Session (guardian login required)
	- **Payload (JSON):** `{ "restricted_apps": { "com.example.app1": 2.5, ... } }`
- **Update Daily Screen Time Limit**
	- **URL:** `/screen_time/api/daily-limit/<child_hash>/update/`
	- **Method:** `POST`
	- **Auth:** Session (guardian login required)
	- **Payload (JSON):** `{ "daily_limit_hours": 4.5 }` or `{ "daily_limit_hours": null }`
- **Search Available Apps**
	- **URL:** `/screen_time/api/apps/search/`
	- **Method:** `GET`
	- **Auth:** Session (guardian login required)
	- **Query Param:** `q` (optional)

---

## 3. Mobile App API Endpoints
- **Screen Time Trend**
	- **URL:** `/screen_time/api/mobile/child/<child_hash>/screen-time/`
	- **Method:** `GET`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:** Get detailed screen time trend data for a child
- **App Usage**
	- **URL:** `/screen_time/api/mobile/child/<child_hash>/app-usage/`
	- **Method:** `GET`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:** Get detailed app usage data for a child
- **Restricted Apps**
	- **URL:** `/screen_time/api/mobile/child/<child_hash>/restricted-apps/`
	- **Method:** `GET`, `POST`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:** Get or update app-wise screen time restrictions for a child
- **Exam Mode**
	- **URL:** `/screen_time/api/mobile/child/<child_hash>/exam-mode/`
	- **Method:** `GET`, `POST`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:** Get or update exam mode settings for a child
- **Daily Screen Time Limit**
	- **URL:** `/screen_time/api/mobile/child/<child_hash>/daily-limit/`
	- **Method:** `GET`, `POST`
	- **Auth:** X-Email and X-Password headers, or session auth
	- **Description:** Get or update daily screen time limit for a child
	- **Payload (POST, JSON):** `{ "daily_limit_hours": 4.5 }` or `{ "daily_limit_hours": null }`

---

## 4. Child Device Endpoint
- **Get Daily Screen Time Limit**
	- **URL:** `/screen_time/api/child/<child_hash>/daily-limit/`
	- **Method:** `GET`
	- **Auth:** None (child device)
	- **Description:** Retrieve daily screen time limit for a child (for child device)

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (see view decorators for limits).
