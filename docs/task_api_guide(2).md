# Task API Guide

This guide documents the Task API endpoints for the Guardian AI mobile application. Tasks allow guardians (parents) to assign tasks to children, who can then view and mark them as complete.

---

## Authentication

### Guardian Authentication
Guardians authenticate using their email and password via:
- **Headers**: `X-Email` and `X-Password`
- **JSON Body**: `{"email": "...", "password": "..."}`

### Child Authentication
Children authenticate using their unique child hash via:
- **Headers**: `X-Child-Hash`
- **JSON Body**: `{"child_hash": "..."}`

No password is required for child authentication - the child hash acts as the identifier.

---

## Guardian Endpoints

### 1. Create Task

Assign a new task to a child.

**Endpoint:** `POST /api/mobile/child/<child_hash>/tasks/`

**Authentication:** Guardian (must be linked to the child)

**Request Body:**
```json
{
    "title": "Complete homework",
    "description": "Finish your math and science homework before dinner"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Title of the task (max 255 chars) |
| `description` | string | Yes | Detailed description of the task |

**Response (201 Created):**
```json
{
    "status": "ok",
    "task": {
        "id": 1,
        "title": "Complete homework",
        "description": "Finish your math and science homework before dinner",
        "is_completed": false,
        "created": "2026-01-15T10:30:00+00:00"
    }
}
```

**Error Responses:**
- `400 Bad Request` - Missing required fields or invalid data
- `401 Unauthorized` - Invalid credentials
- `403 Forbidden` - Guardian not linked to child
- `404 Not Found` - Child not found

---

### 2. View Child's Tasks

View all tasks assigned to a specific child.

**Endpoint:** `GET /api/mobile/child/<child_hash>/tasks/list/`

**Authentication:** Guardian (must be linked to the child)

**Query Parameters:**

| Parameter | Values | Description |
|-----------|--------|-------------|
| `completed` | `true`, `false`, `all` | Filter by completion status (default: `all`) |

**Example:** `GET /api/mobile/child/abc123xyz/tasks/list/?completed=false`

**Response (200 OK):**
```json
{
    "status": "ok",
    "child_hash": "abc123xyz",
    "child_name": "John Doe",
    "total_tasks": 3,
    "tasks": [
        {
            "id": 1,
            "title": "Complete homework",
            "description": "Finish your math and science homework before dinner",
            "is_completed": false,
            "completed_at": null,
            "created": "2026-01-15T10:30:00+00:00",
            "updated": "2026-01-15T10:30:00+00:00"
        },
        {
            "id": 2,
            "title": "Clean room",
            "description": "Organize your desk and make your bed",
            "is_completed": true,
            "completed_at": "2026-01-15T14:00:00+00:00",
            "created": "2026-01-14T09:00:00+00:00",
            "updated": "2026-01-15T14:00:00+00:00"
        }
    ]
}
```

---

## Child Endpoints

### 3. View My Tasks

Child views their assigned tasks.

**Endpoint:** `GET /api/mobile/child/<child_hash>/my-tasks/`

**Authentication:** Child (must match the child_hash in URL)

**Query Parameters:**

| Parameter | Values | Description |
|-----------|--------|-------------|
| `completed` | `true`, `false`, `all` | Filter by completion status (default: `all`) |

**Example:** `GET /api/mobile/child/abc123xyz/my-tasks/?completed=false`

**Response (200 OK):**
```json
{
    "status": "ok",
    "child_hash": "abc123xyz",
    "total_tasks": 5,
    "pending_tasks": 3,
    "completed_tasks": 2,
    "tasks": [
        {
            "id": 1,
            "title": "Complete homework",
            "description": "Finish your math and science homework before dinner",
            "is_completed": false,
            "completed_at": null,
            "created": "2026-01-15T10:30:00+00:00",
            "assigned_by": "Mom"
        }
    ]
}
```

---

### 4. Mark Task as Complete

Child marks a task as completed.

**Endpoint:** `POST /api/mobile/child/<child_hash>/tasks/<task_id>/complete/`

**Authentication:** Child (must match the child_hash in URL)

**Request Body:** Empty (no body required)

**Response (200 OK):**
```json
{
    "status": "ok",
    "message": "Task marked as completed",
    "task": {
        "id": 1,
        "title": "Complete homework",
        "description": "Finish your math and science homework before dinner",
        "is_completed": true,
        "completed_at": "2026-01-15T16:30:00+00:00"
    }
}
```

**If already completed:**
```json
{
    "status": "ok",
    "message": "Task already completed",
    "task": {
        "id": 1,
        "title": "Complete homework",
        "is_completed": true,
        "completed_at": "2026-01-15T16:30:00+00:00"
    }
}
```

**Error Responses:**
- `401 Unauthorized` - Invalid credentials
- `403 Forbidden` - Child hash mismatch
- `404 Not Found` - Task not found

---

### 5. Mark Task as Incomplete

Child reopens a completed task (marks it as incomplete).

**Endpoint:** `POST /api/mobile/child/<child_hash>/tasks/<task_id>/incomplete/`

**Authentication:** Child (must match the child_hash in URL)

**Request Body:** Empty (no body required)

**Response (200 OK):**
```json
{
    "status": "ok",
    "message": "Task marked as incomplete",
    "task": {
        "id": 1,
        "title": "Complete homework",
        "description": "Finish your math and science homework before dinner",
        "is_completed": false,
        "completed_at": null
    }
}
```

---

## Error Response Format

All error responses follow this format:

```json
{
    "status": "error",
    "message": "Description of the error"
}
```

### Common HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created (for POST creating new resources) |
| 400 | Bad Request (invalid input) |
| 401 | Unauthorized (missing or invalid credentials) |
| 403 | Forbidden (not authorized for this resource) |
| 404 | Not Found |
| 405 | Method Not Allowed |
| 500 | Internal Server Error |

---

## Example Usage (cURL)

### Guardian creates a task:
```bash
curl -X POST "http://localhost:8000/api/mobile/child/abc123xyz/tasks/" \
  -H "Content-Type: application/json" \
  -H "X-Email: parent@example.com" \
  -H "X-Password: mypassword" \
  -d '{"title": "Do homework", "description": "Complete all assignments"}'
```

### Child views their tasks:
```bash
curl -X GET "http://localhost:8000/api/mobile/child/abc123xyz/my-tasks/?completed=false" \
  -H "X-Child-Hash: abc123xyz"
```

### Child marks a task complete:
```bash
curl -X POST "http://localhost:8000/api/mobile/child/abc123xyz/tasks/1/complete/" \
  -H "X-Child-Hash: abc123xyz"
```
