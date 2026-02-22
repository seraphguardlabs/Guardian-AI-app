# API Documentation

This document lists all the APIs used in the SeraphGuard project, including REST endpoints and WebSocket channels.

## Base Configuration

*   **REST Base URL:** `https://seraphguardlabs.com`
*   **Restrictions Base URL:** `https://seraphguardlabs.com`
*   **Chat WebSocket URL:** `wss://seraphguardlabs.com/ws/guardian/chat`
*   **Ingest WebSocket URL:** `wss://seraphguardlabs.com/ws/ingest`

---

## REST API Endpoints

### Authentication

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/signup/` | Register a new parent account. |
| `POST` | `/api/login/` | Log in a parent account. Returns an auth token and list of children. |

### Child Management

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/mobile/children/add/` | Add a new child profile to the parent account. |
| `GET` | `/api/mobile/children/` | Fetch the list of children associated with the parent account. |
| `GET` | `/api/mobile/child/$childHash/public-key/` | Fetch the child's public key for encryption. |
| `POST` | `/api/mobile/child/$childHash/public-key/` | Upload the child's public key (called from child device). |

### Monitoring & Data Ingestion

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/ingest/` | Upload monitoring data (screen time, location, site access). Supports batch upload. |
| `GET` | `/api/mobile/child/$childHash/metrics/` | Fetch aggregated metrics/overview for a child. |
| `GET` | `/api/mobile/child/$childHash/screen-time/` | Fetch screen time trend data. Supports `start_date` and `end_date` query params. |
| `GET` | `/api/mobile/child/$childHash/app-usage/` | Fetch app usage statistics. |
| `GET` | `/api/mobile/child/$childHash/locations/` | Fetch location history. Query param: `limit`. |
| `GET` | `/api/mobile/child/$childHash/site-access/` | Fetch site access logs. Query params: `filter`, `limit`. |

### Controls & Restrictions

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/mobile/child/$childHash/daily-limit/` | Get the child's global daily screen time limit. |
| `POST` | `/api/mobile/child/$childHash/daily-limit/` | Set or update the child's daily screen time limit. |
| `GET` | `/api/blocked-apps/$childHash/` | Fetch currently blocked/restricted apps (legacy/simple endpoint). |
| `GET` | `/api/mobile/child/$childHash/restricted-apps/` | Fetch detailed app restriction settings. |
| `POST` | `/api/mobile/child/$childHash/restricted-apps/` | Update app restrictions. Supports `add`, `update`, `remove` actions or full replacement. |
| `GET` | `/api/mobile/child/$childHash/exam-mode/` | Get exam mode status and configuration. |
| `POST` | `/api/mobile/child/$childHash/exam-mode/` | Update exam mode settings (enable/disable, configure apps). |

### Tasks

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/mobile/child/$childHash/tasks/` | Create a new task (Guardian). |
| `GET` | `/api/mobile/child/$childHash/tasks/list/` | List all tasks for a child (Guardian view). Query param: `completed`. |
| `GET` | `/api/mobile/child/$childHash/my-tasks/` | List tasks assigned to the child (Child view). Query param: `completed`. |
| `POST` | `/api/mobile/child/$childHash/tasks/$taskId/complete/` | Mark a task as completed (Child). |
| `POST` | `/api/mobile/child/$childHash/tasks/$taskId/incomplete/` | Mark a task as incomplete (Child). |

### Chat

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/mobile/child/$childHash/chat/` | Fetch chat history (HTTP fallback). |
| `POST` | `/api/mobile/child/$childHash/chat/` | Send a message (HTTP fallback when WebSocket is disconnected). |

---

## Data Structures

### Authentication Headers
For most parent-facing endpoints, authentication is provided via custom headers:
*   `X-Email`: Parent's email address
*   `X-Password`: Parent's password (or hash)
*   `X-Auth-Email` / `X-Auth-Password`: Used specifically in `addChild` endpoint.

For child-facing endpoints (e.g., `getMyTasks`, `completeTask`):
*   `X-Child-Hash`: The unique identifier for the child device.

### JSON Payloads

**Daily Limit Update:**
```json
{
  "daily_screen_time_limit": 2.5 // Hours (double) or null to remove
}
```

**Restriction Update (Action-based):**
```json
{
  "action": "add", // or "update", "remove"
  "package": "com.example.game",
  "hours": 0.5
}
```

**Ingest Payload:**
```json
{
  "screen_time_info": { ... },
  "location_info": { ... },
  "site_access_info": { ... }
}
```

**Task Creation:**
```json
{
  "title": "Clean Room",
  "description": "Clean your room before dinner."
}
```

**Chat Message (HTTP):**
```json
{
  "message_encrypted": "base64_encrypted_string",
  "timestamp": "ISO_8601_TIMESTAMP"
}
```
