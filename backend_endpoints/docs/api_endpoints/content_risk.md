# Content Risk Detection API Endpoints

This document describes the API endpoints for the `content_risk` app, including dashboard and mobile APIs for content risk detection and retrieval. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard: Get Child Risk Logs
- **URL:** `/dashboard/risk-logs/<child_hash>/`
- **Method:** `GET`
- **Auth:** Session (guardian login required)
- **Description:** Retrieve content risk logs for a specific child for dashboard display. Supports optional date range filtering.
- **Query Params:**
  - `start_date` (optional): YYYY-MM-DD
  - `end_date` (optional): YYYY-MM-DD
- **Response (JSON):**
  - On success:
    ```json
    {
      "risk_logs": [
        {
          "id": 1,
          "timestamp": "Feb 14, 2026 10:30",
          "total_risk": 0.75,
          "image_risk": 0.8,
          "text_risk": 0.5,
          "behavior_risk": 0.3,
          "vision_labels": ["violence", "weapons"],
          "ocr_labels": ["inappropriate_text"],
          "app_name": "browser"
        }
      ],
      "count": 1
    }
    ```
  - On error: `{ "error": "<error_message>" }`

---

## 2. Mobile: Submit Content Risk (Child App)
- **URL:** `/api/mobile/child/<child_hash>/content-risk/submit/`
- **Method:** `POST`
- **Description:** Submit one or more content risk detection events for a child.
- **Payload (JSON):**
  - Single risk object or a list of risks under `risks` key:
    ```json
    {
      "timestamp": "2026-01-16T10:30:00Z",
      "total_risk": 0.75,
      "image_risk": 0.8,
      "text_risk": 0.5,
      "behavior_risk": 0.3,
      "vision_labels": ["violence", "weapons"],
      "ocr_labels": ["inappropriate_text"],
      "app_name": "browser"
    }
    ```
    or
    ```json
    {
      "risks": [
        {
          "timestamp": "2026-01-16T10:30:00Z",
          "total_risk": 0.75,
          "image_risk": 0.8,
          "text_risk": 0.5,
          "behavior_risk": 0.3,
          "vision_labels": ["violence"],
          "ocr_labels": [],
          "app_name": "social_app"
        }
      ]
    }
    ```
- **Response (JSON):**
  - On success (201):
    ```json
    {
      "status": "ok",
      "message": "Successfully stored 1 risk log(s)",
      "count": 1
    }
    ```
  - On error: `{ "status": "error", "message": "<error_message>" }`

---

## 3. Mobile: Get Content Risk Logs (Parent App)
- **URL:** `/api/mobile/child/<child_hash>/content-risk/`
- **Method:** `GET`
- **Auth:** X-Email and X-Password headers, or session auth
- **Description:** Retrieve content risk logs for a specific child, with filtering and summary.
- **Query Params:**
  - `start_date` (optional): YYYY-MM-DD (defaults to 7 days ago)
  - `end_date` (optional): YYYY-MM-DD (defaults to today)
  - `app_name` (optional): filter by app name
  - `min_total_risk` (optional): minimum total_risk threshold (e.g., 0.5)
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
      "filters_applied": {
        "app_name": "browser",
        "min_total_risk": "0.5"
      },
      "logs": [
        {
          "id": 1,
          "timestamp": "2026-02-14T10:30:00Z",
          "total_risk": 0.75,
          "image_risk": 0.8,
          "text_risk": 0.5,
          "behavior_risk": 0.3,
          "vision_labels": ["violence"],
          "ocr_labels": [],
          "app_name": "browser"
        }
      ],
      "summary": {
        "total_count": 10,
        "high_risk_count": 2,
        "medium_risk_count": 5,
        "low_risk_count": 3,
        "returned_count": 1,
        "limit_applied": 100
      }
    }
    ```
  - On error: `{ "status": "error", "message": "<error_message>" }`

---

# Notes
- All endpoints requiring authentication use either session or header-based authentication as described above.
- Error messages are returned as JSON for all API endpoints.
- Rate limiting is applied to mobile API endpoints (10 requests per minute per IP).
