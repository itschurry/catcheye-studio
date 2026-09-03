# CatchEye Studio integration

`catcheye-inspect` exposes a live WebSocket viewer on port `8080` and an HTTP
control API on port `8090`. CatchEye Studio must recognize the new
`inspection` device kind instead of treating the runtime as `capture`.

Camera IP remains owned by the existing `catcheye-inspect` YAML camera profile.
Studio does not read or update it.

## Device contract

Studio first requests:

```http
GET http://<device>:8090/api/device-info
```

The response is:

```json
{
  "app": "catcheye-inspect",
  "kind": "inspection"
}
```

The live stream URL is:

```text
ws://<device>:8080
```

Each viewer frame uses the existing Catcheye SDK contract: one JSON WebSocket
text frame followed by one JPEG binary frame. Inspection fields are nested in
the top-level viewer frame's `metadata` object.

```json
{
  "app": "catcheye-inspect",
  "kind": "inspection",
  "set_id": "set_b",
  "inspection_id": "nut_hole_alignment",
  "status": "PRESENT",
  "reason": "TARGET_CONFIRMED",
  "latency_ms": 18.432,
  "detections": []
}
```

## Required Studio changes

### `lib/models/app_settings.dart`

Add a device kind:

```dart
enum RemoteDeviceKind {
  hss('hss', 'HSS'),
  pick('pick', 'Pick'),
  capture('capture', 'Capture'),
  inspection('inspection', 'Inspection');
}
```

### `lib/main.dart`

Expose only the Viewer for `inspection`. Do not expose Capture Images, ROI,
recording, or camera-property screens because `catcheye-inspect` does not
implement those contracts.

```dart
RemoteDeviceKind.inspection => const [0],
```

Add the branch to both phone and desktop `visibleAppItemIndexes` switches.

### `lib/screens/viewer_screen.dart`

Enable the Capture button for inspection devices:

```dart
final captureControlsEnabled =
    remoteDeviceKind == RemoteDeviceKind.capture ||
    remoteDeviceKind == RemoteDeviceKind.inspection;
```

Apply the same condition in desktop and phone toolbar builders.

Do not include `inspection` in `recordingControlsEnabled`. In `_connect`, keep
the recording-status request restricted to `hss` and `capture`; otherwise a
missing `/api/recording` endpoint prevents the WebSocket connection.

In single-inspection mode, the existing `RemoteCaptureApiService.requestCapture`
can be reused without changes. It already sends the required request:

```http
POST /api/capture/request
```

### Nut-hole measurements

`nut_hole_alignment` emits `OK`/`NG` after shape evaluation, or `RECHECK` when
geometry or configured quality limits are missing. Presence-only inspections
still emit `PRESENT`/`ABSENT`. Studio must not interpret a detected nut hole as a
shape pass without checking the final status.

Inspection metadata now includes a `measurements` object. It contains
`inner_circle` and `outer_circle` (center/radius in original-frame pixels,
circularity, axis ratio, arc detection rate, and residual),
`measurement_roi_xyxy`, `center_distance_px`, `quality_metrics`, `quality_limits`,
and `failed_metrics`. Relative eccentricity is in
`measurements.quality_metrics.relative_eccentricity`; missing limits are JSON
`null`. The object is `{}` when no measurement is available. Circle overlays are
also included in the published JPEG.

### Optional result presentation

`FrameReceiverService.latestMetadata['metadata']` contains the inspection
result. A later Studio change may present `status`, `reason`, and `latency_ms`
as a compact viewer status row. This is not required for connection or Capture
button operation because the annotated JPEG already contains detection boxes.

## Single-inspection Capture API

Request the next-frame inspection:

```http
POST /api/capture/request
```

Read current state:

```http
GET /api/capture/status
```

Example response:

```json
{
  "app": "catcheye-inspect",
  "kind": "inspection",
  "busy": false,
  "capture_requested": false,
  "capture_count": 3,
  "ignored_capture_count": 0,
  "last_result": {
    "status": "PRESENT",
    "reason": "TARGET_CONFIRMED"
  },
  "last_error": ""
}
```

The POST returns HTTP `200` and the same status object. Repeated requests while
one is pending or executing are ignored and increment `ignored_capture_count`.

## Single-inspection Acceptance test

1. Start `catcheye-inspect-runtime` on the inspection device.
2. Verify `GET http://<device>:8090/api/device-info` returns kind `inspection`.
3. Connect Studio to `ws://<device>:8080` and `http://<device>:8090`.
4. Confirm live frames continue when inference cadence is greater than one.
5. Press Capture and verify `/api/capture/status` increments `capture_count`.
6. Confirm the next WebSocket metadata contains the new inspection result.
7. Confirm Studio does not request `/api/recording` for this device kind.

## Station mode: required Studio changes

The C++ runtime additionally supports `--station` for multiple YAML cameras and
grouped inspections on one device. Studio must branch on the optional discovery field:

```json
{"app":"catcheye-inspect","kind":"inspection","runtime_mode":"station"}
```

Absence of `runtime_mode` retains the single-inspection contract above. Do not infer
mode from device kind alone and do not apply the capture application's recording,
camera-property, ROI or image-download contracts to this device.

### Group capture and result correlation

Extend `RemoteCaptureApiService` with a station request returning `accepted`,
`cycle_id`, and `error`, rather than treating the response as capture status:

```http
POST /api/capture/request
Content-Type: application/json

{"group":"a"}
```

```json
{"accepted":true,"cycle_id":"<generated-id>","error":""}
```

The same route accepts `{"inspection_id":"nut_hole_alignment"}` for an individual
inspection, or an empty body / `{}` for every configured inspection. Do not send
both nonempty selectors. Empty selectors mean no selection, not a group named `""`.
Unknown fields, invalid JSON/types, or unknown groups/inspection IDs return HTTP 400.
HTTP 409 means the queue is full; HTTP 503 means the station is not ready. A 200 response
means accepted, not inspection passed. Do not automatically replay a timed-out POST:
requests are not idempotent and a second request creates another cycle.

Read `GET /api/capture/status` for `ready`, `busy`, `pending_count`,
`max_pending_captures`, `active_cycle_id`, `capture_count`, `groups`, `cameras`,
`last_result` and `last_error`. `groups` maps group IDs to inspection-ID arrays.
`cameras` maps camera IDs to `open`, `frame_sequence` and `last_error`; a closed idle
camera is not itself an equipment fault. Show queue occupancy rather than disabling
all captures while one is running. The queue limit excludes the active cycle.

Poll each accepted ID using:

```http
GET /api/capture/results/<cycle_id>
```

`state` progresses from `QUEUED` to `RUNNING` to `COMPLETED` or `CANCELLED`.
Only completed/cancelled results have final `status`. The result includes `set_id`,
`group`, `inspection_ids`, and millisecond wall-clock `requested_at_ms`,
`started_at_ms`, `finished_at_ms`. Per-inspection results are keyed by inspection ID:

```json
{
  "cycle_id":"<generated-id>",
  "state":"COMPLETED",
  "status":"NG",
  "inspections":{
    "bolt_head":{
      "inspection_id":"bolt_head",
      "camera_id":"bolt_head_camera",
      "camera_serial":"<configured-serial>",
      "source_timestamp_ms":123456,
      "status":"ABSENT",
      "reason":"NO_CANDIDATE",
      "latency_ms":500,
      "detections":[],
      "measurements":{}
    }
  }
}
```

Aggregate priority is `EQUIPMENT_ERROR > NG > RECHECK > OK`. Per-inspection presence
results remain `PRESENT`/`ABSENT`, mapped to cycle `OK`/`NG`. Display equipment faults
separately from defects; cancelled cycles must not appear as passes. `source_timestamp_ms`
is host-monotonic frame retrieval time, not wall time or a synchronized exposure timestamp.
Capture happens when a queued cycle starts executing, not when its POST was accepted.

Completed history is bounded (32 by default) and lost on restart; unknown/evicted IDs
return HTTP 404. Retain the completed result in Studio after polling it. `last_result`
can belong to another request, so it is not sufficient to correlate simultaneous callers.
When saving is configured, `artifacts` names files relative to the cycle directory on the
device. No artifact-download endpoint is implemented. `artifact_error` indicates a save
failure and forces aggregate `EQUIPMENT_ERROR`; per-inspection detection results may still exist.

### Preview source

Add a camera selector to the station Viewer. Populate it from:

```http
GET /api/viewer/source
```

```json
{"camera_id":"","cameras":["bolt_head_camera","bolt_body_camera","nut_camera","nut_hole_camera"]}
```

Select a source using `POST /api/viewer/source` with `{"camera_id":"nut_camera"}`.
An empty ID disables preview. This is a global device selection, not per-connection.
Do not send IP addresses or allow this selector to modify the deployment YAML.

The existing WebSocket text-plus-JPEG framing is unchanged. `stream_name` is now the
camera ID. `metadata` contains `runtime_mode: "station"`, `camera_id`, `frame_sequence`,
`status: "PREVIEW"`, `annotated: false`, `app`, `kind`, and `set_id`. Frame dimensions come
from each envelope and may change on source selection. Clear the previous displayed
frame/result association on a switch, and discard buffered frames whose camera ID does
not match the selected source. Show waiting/error state when no fresh preview arrives.

Station preview is raw live imagery, not a capture result or overlay. Do not draw
capture detections on it: those detections belong to a different frozen frame. Show
per-cycle status/geometry in a separate result view or row. Polling results must work
with preview disabled and must not depend on receiving a new WebSocket frame.

### Station acceptance tests

1. Discover station mode and retrieve available groups/cameras without changing YAML.
2. Select each camera, verify identity/dimensions, and disable preview without blocking capture.
3. Submit A then B while A runs. Verify distinct cycle IDs, FIFO completion and two results.
4. Fill the pending queue and display HTTP 409 without automatic retries or lost accepted IDs.
5. Verify NG, RECHECK, camera timeout, and storage-error presentation independently.
6. Verify correlated result polling, expiration (404), reconnect and runtime restart behavior.
7. Verify raw preview continues during inference without reusing capture overlays.
8. Validate actual four-camera acquisition and unified-model results on the installation;
   the C++ synthetic tests do not establish synchronized exposure or production throughput.

Studio source is not changed in this repository. The blocking-client transport deadline
limitation described in `cpp/README.md` also needs resolution in the shared SDK before
unattended deployment; Studio should close failed/abandoned HTTP and WebSocket connections.
