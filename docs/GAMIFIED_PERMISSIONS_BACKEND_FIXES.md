# Gamified Permission System — Backend Fix Specification

> **Purpose:** This document describes the required backend changes to make the gamified time-request feature fully functional. Currently, the assign-task endpoint is a stub and the child/parent list endpoints do not return task-related fields.

---

## Overview of the Flow

```
Child requests time  →  Parent assigns a task  →  Child completes task
       →  Parent is notified  →  Parent approves  →  Child gets time
```

---

## Fix 1 🔴 — Persist Task on `assign-task` Endpoint

**Endpoint:** `POST /api/mobile/time-extension-requests/<request_id>/assign-task/`  
**Auth:** Guardian (header)  
**Current state:** Stub — does nothing, returns `{"status": "ok", "message": "Task assigned (stub)"}`

### Required Behaviour

1. Accept the request body:
```json
{
    "task_id": "play_chess",
    "task_title": "Play Chess",
    "task_description": "Play a game of chess with someone"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `task_id` | string | Yes | ID from suggested tasks list OR a custom slug |
| `task_title` | string | Yes | Human-readable task name |
| `task_description` | string | No | Optional details |

2. Create a `Task` record linked to the child.
3. Update the `TimeExtensionRequest`:
   - `status` → `"task_assigned"`
   - `task_id` → ID of the created Task
   - `task_title` → task title (denormalised for fast reads)
   - `task_description` → task description (optional)

4. Return:
```json
{
    "status": "ok",
    "message": "Task assigned",
    "request_id": 42,
    "task_id": 17,
    "task_title": "Play Chess"
}
```

### Django Example

```python
@api_view(['POST'])
def assign_task(request, request_id):
    time_request = get_object_or_404(TimeExtensionRequest, id=request_id)
    
    task_title = request.data.get('task_title', '')
    task_desc  = request.data.get('task_description', '')
    
    # Create task record for child
    task = Task.objects.create(
        child=time_request.child,
        assigned_by=request.guardian,
        title=task_title,
        description=task_desc,
    )
    
    # Link task to this time extension request
    time_request.status = 'task_assigned'
    time_request.task = task
    time_request.task_title = task_title
    time_request.task_description = task_desc
    time_request.save()
    
    # Notify child via WebSocket (see Fix 6)
    push_task_assigned_to_child(time_request, task)
    
    return Response({
        'status': 'ok',
        'message': 'Task assigned',
        'request_id': time_request.id,
        'task_id': task.id,
        'task_title': task.title,
    })
```

---

## Fix 2 🔴 — Include Task Fields in Child's Time-Request List

**Endpoint:** `GET /api/mobile/child/<child_hash>/time-extension-requests/`  
**Auth:** Child (`X-Child-Hash`)  
**Current state:** Returns basic fields only — no task data.

### Required Response Format

```json
{
    "status": "ok",
    "child_hash": "abc123def456",
    "requests": [
        {
            "request_id": 42,
            "app_domain": "youtube.com",
            "requested_hours": 1.5,
            "status": "task_assigned",
            "task_id": 17,
            "task_title": "Play Chess",
            "task_description": "Play a game of chess with someone",
            "is_task_completed": false,
            "created": "2026-02-28T10:00:00+00:00",
            "responded_at": null
        }
    ],
    "count": 1
}
```

### New Fields Required

| Field | Type | Description |
|---|---|---|
| `status` | string | Now includes `task_assigned`, `task_completed` in addition to `pending`, `approved`, `denied` |
| `task_id` | int \| null | ID of the assigned Task, null if no task |
| `task_title` | string \| null | Display title of the task |
| `task_description` | string \| null | Optional task details |
| `is_task_completed` | bool | Whether the child has marked the task done |

> **Note:** The frontend filters requests by `status == 'task_assigned'` or `status == 'task_completed'` to show them in the "Earn Screen Time" section. Both values must be included in the `status` field.

---

## Fix 3 🔴 — `complete-task` Must Update Linked Time Request

**Endpoint:** `POST /api/mobile/child/<child_hash>/tasks/<task_id>/complete/`  
**Auth:** Child (`X-Child-Hash`)  
**Current state:** Marks task complete but does NOT update the linked `TimeExtensionRequest`.

### Required Behaviour

After marking the task complete:
1. Find the linked `TimeExtensionRequest` (if any).
2. Set `status → "task_completed"` and `is_task_completed → True`.
3. Push a WebSocket notification to the parent (see Fix 6).

### Django Example

```python
@api_view(['POST'])
def complete_task(request, child_hash, task_id):
    task = get_object_or_404(Task, id=task_id, child__child_hash=child_hash)
    task.is_completed = True
    task.completed_at = now()
    task.save()
    
    # Check if this task is linked to a time extension request
    linked_request = TimeExtensionRequest.objects.filter(task=task).first()
    if linked_request:
        linked_request.status = 'task_completed'
        linked_request.is_task_completed = True
        linked_request.save()
        
        # Notify parent via WebSocket (see Fix 6)
        push_task_done_to_parent(linked_request)
    
    return Response({
        'status': 'ok',
        'message': 'Task completed',
        'task': serialize_task(task),
    })
```

---

## Fix 4 🟠 — Include Task Fields in Parent's Pending-Request List

**Endpoint:** `GET /api/mobile/time-extension-requests/?status=pending`  
**Auth:** Guardian (header)  
**Current state:** Returns basic fields, no task data.

### Additional Fields Required

```json
{
    "requests": [
        {
            "request_id": 42,
            "child_hash": "abc123",
            "child_name": "Alex",
            "app_domain": "youtube.com",
            "requested_hours": 1.5,
            "status": "task_assigned",
            "task_id": 17,
            "task_title": "Play Chess",
            "is_task_completed": false,
            "created": "2026-02-28T10:00:00+00:00"
        }
    ]
}
```

> **Note:** The parent dashboard splits requests into "Pending" (status=`pending`) and "Task Waiting" (status=`task_assigned`/`task_completed`) cards. Include both in the list and let the frontend filter by `status`.

---

## Fix 5 🟡 — Status Filter on Child Endpoint

**Endpoint:** `GET /api/mobile/child/<child_hash>/time-extension-requests/?status=all`

Support the query parameter `status` with these values:

| Value | Behaviour |
|---|---|
| `pending` | Only requests with `status = pending` |
| `task_assigned` | Only requests where a task has been assigned |
| `task_completed` | Only requests where child has completed the task |
| `approved` | Only approved requests |
| `denied` | Only denied requests |
| `all` | All requests (default) |

---

## Fix 6 🟡 — WebSocket Push Notifications

### 6a. Push `task_assigned` to child when parent assigns a task

Send on the child's WebSocket channel after Fix 1 completes:

```json
{
    "type": "task_assigned",
    "data": {
        "request_id": 42,
        "task_id": 17,
        "task_title": "Play Chess",
        "task_description": "Play a game of chess with someone",
        "app_domain": "youtube.com",
        "requested_hours": 1.5
    }
}
```

### 6b. Push `task_completed` to parent when child marks done

Send on the guardian's WebSocket channel after Fix 3 completes:

```json
{
    "type": "request_status_update",
    "data": {
        "request_id": 42,
        "status": "task_completed",
        "child_name": "Alex",
        "task_title": "Play Chess"
    }
}
```

> **Frontend readiness:** The child app already listens for `task_assigned` events and calls `_loadRewardRequests()` in response. The parent dashboard already listens for `request_status_update` and refreshes the request list.

---

## Fix 7 🟡 — Database Schema Changes

Add the following fields to `TimeExtensionRequest` model:

```python
class TimeExtensionRequest(models.Model):
    # ... existing fields ...
    
    # Gamified fields
    task = models.ForeignKey('Task', null=True, blank=True, on_delete=models.SET_NULL)
    task_title = models.CharField(max_length=255, null=True, blank=True)
    task_description = models.TextField(null=True, blank=True)
    is_task_completed = models.BooleanField(default=False)
```

Update `STATUS_CHOICES`:
```python
STATUS_CHOICES = [
    ('pending', 'Pending'),
    ('task_assigned', 'Task Assigned'),
    ('task_completed', 'Task Completed by Child'),
    ('approved', 'Approved'),
    ('denied', 'Denied'),
    ('responded', 'Responded'),
]
```

---

## Implementation Priority

| # | Fix | Impact | Effort |
|---|---|---|---|
| 1 | Persist task on assign-task | 🔴 Critical | Medium |
| 2 | Child list includes task fields | 🔴 Critical | Low |
| 3 | complete-task updates linked request | 🔴 Critical | Low |
| 4 | Parent list includes task fields | 🟠 High | Low |
| 5 | Status filter on child endpoint | 🟡 Medium | Low |
| 6 | WebSocket push notifications | 🟡 Medium | Medium |
| 7 | Schema migration | Prerequisite for #1–4 | Low |

> **Start with Fix 7 (schema), then Fix 1 → Fix 2 → Fix 3.** Fixes 4–6 are enhancements that improve the UX but are not blocking.
