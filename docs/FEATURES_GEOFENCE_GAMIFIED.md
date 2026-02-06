Geofencing & Gamified Permission Features (local demo)

- `GeofenceService` (lib/services/geofence_service.dart): local geofence model and utilities to add/remove geofences and check if a point is inside a geofence (Haversine calculation).
- `GamifiedPermissionService` (lib/services/gamified_permission_service.dart): suggested reward tasks, add custom tasks, assign task stub, and mark complete.
- `AssignTaskScreen` (lib/screens/assign_task_screen.dart): UI to choose a suggested task, add custom tasks, or choose "No Task" and send the selection (demo stubbed).

How to try locally:

1. Run the app in your usual Flutter environment.
2. Navigate to the app where routes are available and open `/assign_task` (there is a route registered).
3. Use the "Add New Task" to add a custom task, select a task and press "Send" to exercise the flow.

Notes:
- These implementations are local/demo-only stubs. Integrate backend endpoints documented in `GAMIFIED_PERMISSIONS_API_REFERENCE.md` to persist and operate across devices.
- `GeofenceService` contains reliable distance math and can be fed coordinates from a tracker to detect enter/exit.
