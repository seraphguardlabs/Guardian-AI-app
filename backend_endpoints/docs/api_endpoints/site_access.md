# Site Access Management API Endpoints

This document describes the API endpoints for the `site_access` app, including dashboard and mobile APIs for site access logs. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard: Get Child Site Access Logs
- **URL:** `/dashboard/site-logs/<child_hash>/`
- **Method:** `GET`
- **Auth:** Session (guardian login required)
- **Description:** Retrieve site access logs for a specific child for dashboard display. Supports optional date range filtering.
- **Query Params:**
	- `start_date` (optional): YYYY-MM-DD
	- `end_date` (optional): YYYY-MM-DD
- **Response (JSON):**
	- On success:
		```json
		{
			"site_logs": [
				{
					"timestamp": "Feb 14, 2026 10:30",
					"url": "https://example.com",
					"accessed": true
				}
			],
			"count": 1
		}
		```
	- On error: `{ "error": "<error_message>" }`

---

## 2. Mobile: Get Site Access Logs
- **URL:** `/api/mobile/child/<child_hash>/site-access/`
- **Method:** `GET`
- **Auth:** X-Email and X-Password headers, or session auth
- **Description:** Retrieve detailed site access/blocked logs for a specific child, with filtering and summary.
- **Query Params:**
	- `start_date` (optional): YYYY-MM-DD (defaults to 7 days ago)
	- `end_date` (optional): YYYY-MM-DD (defaults to today)
	- `filter` (optional): `all` (default), `accessed`, or `blocked`
	- `limit` (optional): max number of logs (default 100, max 500)
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
			"filter_applied": "all",
			"logs": [
				{
					"url": "https://example.com",
					"domain": "example.com",
					"timestamp": "2026-02-14T10:30:00Z",
					"accessed": true,
					"status": "accessed"
				}
			],
			"summary": {
				"total_count": 10,
				"blocked_count": 3,
				"accessed_count": 7,
				"returned_count": 1,
				"unique_domains": 1,
				"limit_applied": 100
			}
		}
		```
	- On error: `{ "status": "error", "message": "<error_message>" }`

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (see view decorators for limits).
