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
  "set_id": "nut",
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

{"group":"bolt_stud"}
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

운영 프로파일의 `set_id`는 `fastener`야. 그룹 `bolt_stud`는 `["bolt_head", "stud"]`, 그룹 `nut`은 `["nut", "nut_hole_alignment"]`로 구성돼. 이전 그룹 이름의 호환 별칭은 없고 요청하면 HTTP 400 `UNKNOWN_GROUP`이 반환돼. Studio의 선택 항목은 `/api/capture/status`의 `groups`에서 읽어.

스터드 검사에는 `stud`, 카메라에는 `stud_camera`를 사용해. 개별 캡처 요청은 `{"inspection_id":"stud"}`, 미리보기 선택은 `{"camera_id":"stud_camera"}`야. 카메라 역할은 스터드 `.101`, 볼트 머리 `.102`, 너트 `.103`, 너트 홀 `.104`이며 IP 설정은 계속 장비 YAML에서 관리해.

Studio는 상태 API가 반환하는 ID를 사용하고, 표시명은 "스터드"로 통일하십시오. 스터드의 검사 ID와 검출 `class_name`은 모두 `stud`, 카메라 ID는 `stud_camera`입니다. 이전 이름의 별칭은 제공하지 않으므로 클라이언트의 요청 ID·검출 클래스 필터도 갱신해야 합니다.

Add a camera selector to the station Viewer. Populate it from:

```http
GET /api/viewer/source
```

```json
{"camera_id":"","camera_ids":[],"cameras":["bolt_head_camera","stud_camera","nut_camera","nut_hole_camera"]}
```

`POST /api/viewer/source`는 단일 선택 `{"camera_id":"nut_camera"}`와 다중 선택 `{"camera_ids":["stud_camera","bolt_head_camera","nut_camera","nut_hole_camera"]}`를 지원합니다. 두 필드를 동시에 보내면 안 됩니다. 중복·미등록 ID, 배열 안의 빈 ID, 잘못된 타입 또는 4개 초과 선택은 HTTP 400이며 기존 선택을 유지합니다. 빈 문자열 또는 빈 배열은 미리보기를 끕니다. 선택은 연결별이 아닌 장비 전체에 적용되며 IP나 배포 YAML을 수정하지 않습니다.

응답의 `camera_ids`는 선택 순서를 유지하는 전체 목록입니다. `camera_id`는 단일 선택 클라이언트를 위한 첫 번째 ID이며 전체 선택을 나타내지는 않습니다. Studio 선택 UI는 `camera_ids`를 사용하십시오.

한 대 선택 시 기존 `type: "frame"` JSON 텍스트 뒤에 JPEG 바이너리 메시지 하나가 옵니다. `stream_name`은 카메라 ID이며 `metadata`에는 `runtime_mode`, `camera_id`, `frame_sequence`, `status: "PREVIEW"`, `annotated: false`, `app`, `kind`, `set_id`가 포함됩니다.

두 대 이상 선택 시 `type: "viewer_frame"` JSON 뒤에 여러 JPEG 바이너리 메시지가 옵니다. `metadata.camera_ids`는 선택된 전체 카메라 목록이고 `streams`는 이번 메시지에 실제로 포함된 영상 목록입니다. 각 항목은 `name`(카메라 ID), `kind: "camera"`, `encoding: "jpeg"`, 0부터 시작하는 `payload_index`, `payload_size`, `width`, `height`, `source_timestamp_ms`, `frame_sequence`를 포함합니다. **JSON 하나를 받은 뒤 `streams.length`개의 바이너리 메시지를 소비하고 `payload_index`로 연결해야 합니다.**

획득 대기·오류로 프레임이 없는 카메라는 `streams`에서 빠질 수 있으므로 `metadata.camera_ids` 개수만큼 JPEG를 기다리면 안 됩니다. 촬영 시점은 동기화되지 않으며 같은 카메라 프레임이 다음 묶음에 재등장할 수 있습니다. UI는 카메라별 `frame_sequence`와 수신 시점을 추적하고 오래 갱신되지 않는 영상에 대기·오류 상태를 표시하십시오. 선택 전환 중 남은 메시지도 해당 JSON의 개수만큼 소비한 다음, 현재 선택에 없는 카메라 영상은 버리십시오.

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
9. 단일·다중 선택을 전환하면서 네 카메라의 JPEG 순서·크기·ID를 검증하고, 일부 카메라가 프레임을 반환하지 않아도 메시지 구분이 어긋나지 않는지 확인합니다.

Studio source is not changed in this repository. The pinned SDK enforces
total HTTP request/response and WebSocket handshake/send deadlines (see `cpp/README.md`).
Studio should still close abandoned connections, reconnect after send timeouts, and
avoid automatically replaying capture POSTs after a timeout. Hardware smoke results
and remaining optical qualification are recorded in `docs/FASTENER_VALIDATION.md`.

### Deployed service connection

The systemd station can now start at boot and restart after unexpected exit. For this
installation, Studio connects to device HTTP `192.168.0.122:8090` and WebSocket
`192.168.0.122:8080`, not camera addresses `.101` through `.104`. The deployed allowlist
currently trusts `192.168.0.0/24`; moving Studio/PLC to another address range requires
an operator deployment update, not a camera-IP change in Studio. A blocked connection
times out at the IP layer rather than returning HTTP 403.

After restart, treat a missing previously accepted cycle as an unknown outcome, not
NG or permission to replay the POST. Refresh groups/cameras and the shared preview
selection. Surface `EQUIPMENT_ERROR` independently of product NG; a transient frame
error was observed after forced restart during deployment testing. Operational policy,
retention and restart evidence are in [OPERATIONS.md](OPERATIONS.md).

## 예시 이미지 등록과 적용

Studio에서 새 예시 이미지를 촬영하고 검사에 적용하는 흐름입니다. 아래 관리 API는 설치 옵션을 활성화한 C++ 스테이션에서 제공하며, Studio는 기능 플래그를 확인한 뒤 사용합니다.

Inspect 구현 순서와 단계별 완료 조건은 [예시 이미지 구현 계획](REFERENCE_IMAGE_IMPLEMENTATION_PLAN.md)을 따릅니다. Studio는 아래 **예시 이미지 API v1**을 기준으로 화면과 테스트를 준비하되, 서버의 기능 플래그가 활성화되기 전에는 실제 지원 기능으로 노출하지 않습니다.

### 현재 모델의 제약

`python/configs/fastener_export.yaml`은 클래스별 예시 이미지와 대상 박스를 정의합니다. `YOLOERuntime._prime()`이 시각 프롬프트 임베딩을 만들고 `tools/export_yoloe_tensorrt.py`가 이를 고정한 ONNX와 TensorRT 엔진을 생성합니다. 운영 C++은 해당 엔진을 읽으므로 **예시 이미지나 YAML 경로만 교체해도 기존 엔진의 검출 동작은 바뀌지 않습니다.**

새 예시는 시각 프롬프트 갱신에 사용하며, 사용자 데이터로 모델 가중치를 재학습하는 기능과 구분합니다. 현재 방식에서는 예시가 달라지면 ONNX부터 다시 내보내야 하며 `--reuse-onnx`를 사용하면 안 됩니다. fastener는 통합 엔진이므로 한 클래스의 예시만 바꿔도 다른 클래스의 예시를 유지한 전체 엔진을 생성해야 합니다.

### 사용자 흐름

1. Studio에서 카메라와 대상 클래스(`stud`, `bolt_head`, `nut`, `nut_hole`, `plain_hole`)를 선택합니다. 카메라 IP는 계속 장비 YAML에서 관리합니다.
2. Studio의 촬영 요청을 받은 Inspect가 해당 카메라에서 새 원본 프레임을 확보하고 이미지 ID, 카메라 ID, 원본 크기와 촬영 정보를 반환합니다. Studio가 카메라에 직접 연결하거나 WebSocket 화면을 스크린샷으로 저장하지 않습니다.
3. Studio에서 촬영된 원본 위에 대상 박스를 지정합니다. 원본 이미지 좌표의 `[x1, y1, x2, y2]`를 저장하며 화면 확대·축소 좌표와 구분합니다. 동일 클래스의 여러 대상 박스를 지원합니다.
4. Inspect가 이미지와 박스, 클래스, 설정을 새 예시 버전으로 저장합니다. 저장은 초안 등록이며 운영 모델에 즉시 적용하지 않습니다.
5. 사용자가 모델 생성 작업을 요청하면 해당 예시 버전을 고정해 엔진을 생성하고, Studio는 작업 ID로 진행 상태와 실패 사유를 조회합니다.
6. 서버의 기준 이미지 기술 검증 결과를 확인합니다. 별도 양품·불량 이미지에 대한 품질 검토는 운영자가 수행한 뒤 적용을 승인합니다. 문제 발생 시 이전 모델 버전으로 복구합니다.

예시 등록에 사용하는 이미지는 검출 박스·문자·측정선이 없는 원본이어야 합니다. 이는 예시 편집을 위한 단발 원본 조회이며, 운영 WebSocket에서 원본을 계속 송출해야 한다는 요구는 아닙니다. 검출 결과 영상 송출과 예시 이미지 취득은 별도 경로로 취급합니다.

### Inspect 구현 경계

- 원본 단발 촬영·조회: 새 프레임을 식별 가능한 ID로 보관하고, 촬영 실패나 오래된 프레임을 새 예시로 처리하지 않습니다. 검사용 캡처 명령과 의미를 분리합니다.
- 예시 등록·조회: 이미지 ID에 연결된 클래스와 박스를 검증합니다. 임의 파일 경로는 받지 않으며, 원본 경계 밖·빈 영역·잘못된 숫자를 거부합니다. 초기 구현은 현재와 같이 클래스별 이미지 한 장과 여러 박스를 사용합니다.
- 예시 버전 관리: 수정할 클래스 외의 예시·클래스 순서·검사 임계값은 유지합니다. 서버가 생성한 예시 파일과 내보내기용 YAML을 사용하며 카메라 운영 YAML을 임의로 덮어쓰지 않습니다.
- 모델 생성·검증: 운영 C++ 추론과 별도 준비 작업으로 수행하며 기존 내보내기 도구를 활용할 수 있습니다. 같은 장비의 GPU를 사용하면 검사 성능에 영향을 주므로 유지보수 시간에 실행하거나 호환되는 별도 빌드 환경을 사용합니다.
- 모델 적용·복구: 엔진·메타데이터·예시 버전·검증 기록을 하나의 버전으로 관리합니다. 새 캡처 접수를 막고 진행 중 요청을 정리한 뒤 전환하며, 실패 시 마지막 정상 버전을 유지하거나 복구합니다. 적용 후 생성한 검사 결과에는 사용한 모델 버전을 기록합니다.
- 보관·접근 제어: 예시와 활성·복구용 모델은 일반 캡처 보관 정리 대상에서 제외합니다. 모델 생성·적용 권한은 일반 뷰어 접근과 구분하고 동시 적용 요청을 차단해야 합니다.

### 구현 순서와 검증

1. 원본 단발 촬영·조회와 이미지 ID 관리, Studio 촬영·대상 박스 편집 화면을 연결합니다.
2. 예시 등록·버전 조회와 내보내기 설정 생성을 구현합니다. 새 예시 등록 후에도 활성 모델이 그대로인지 확인합니다.
3. 모델 생성·상태 조회·검증 작업을 연결합니다. 클래스 순서 유지, 새 프롬프트 반영, 빌드 실패 시 기존 모델 보존을 검사합니다.
4. 명시적인 모델 적용·이전 버전 복구를 구현하고, 캡처와 모델 전환이 겹칠 때 결과에 다른 버전이 섞이지 않는지 확인합니다.

촬영 직후 엔진 생성 없이 예시를 즉시 교체하는 요구가 있다면, 고정 프롬프트 엔진 대신 실행 중 프롬프트를 갱신할 수 있는 추론 구조를 별도로 설계해야 합니다. 현재 C++ 런타임의 단순 이미지 경로 변경으로는 제공할 수 없습니다.

## 예시 이미지 API v1

상태: **C++ 구현 완료, 설치 옵션으로 활성화**. `--enable-reference-api`로 설치한 fastener 장비에서 아래 API를 제공합니다. 미설치 장비의 404는 미지원으로 처리하십시오. 기존 `/api/capture/request`, 결과 목록 API와 혼용하지 않습니다. Studio 소스 변경은 이 저장소에 포함하지 않습니다.

### 공통 규칙

- `GET /api/reference/status`의 `api_version`, `capabilities`, `device_state`, `active_model_id`로 지원 범위와 운영 상태를 확인합니다. 기존 장비에서 404이면 예시 관리 미지원으로 표시합니다. `device_state`는 `RUNNING`, `MAINTENANCE`, `ERROR` 중 하나입니다.
- 기능 플래그는 `reference_capture`, `reference_revisions`, `model_build`, `model_activation`입니다. 각 플래그는 해당 단계의 저장·권한·API가 준비된 이후에만 true가 됩니다.
- POST에는 클라이언트가 생성한 UUID 문자열 `request_id`를 넣습니다. 같은 ID와 같은 요청 본문은 기존 작업·자원을 반환하고, 다른 본문은 409 `REQUEST_ID_CONFLICT`입니다. 중복 방지 기록은 재시작 후에도 유지하며 최소 7일 보관합니다. 그 기간이 지난 요청을 자동 재전송하지 않습니다.
- 비동기 작업 접수는 202, 동기적인 예시 버전 생성은 201, 조회는 200입니다. 기존 자원을 반환하는 중복 요청은 원래 자원 ID를 유지하며 200을 반환할 수 있습니다.
- 신규 API 오류 형식은 `{"error":{"code":"INVALID_BOX","message":"..."}}`입니다. 400은 입력 오류, 401/403은 인증·권한 오류, 404는 없는 자원, 409는 충돌·작업 포화·이미지 미준비, 413은 요청 크기 초과, 503은 준비되지 않았거나 유지보수 중인 장비입니다.
- 이 계약의 예시·모델 API는 관리 권한을 요구합니다. 기존 API의 오류 형식이나 인증 동작까지 바뀐 것으로 해석하지 않습니다. PNG도 인증된 HTTP 클라이언트로 가져와 표시합니다.
- 모든 신규 요청에 `Authorization: Bearer <token>` 헤더를 넣습니다. 토큰은 장비의 `/etc/catcheye-inspect/reference.token`에서 별도로 전달받아 Studio의 자격 증명 저장소에 보관하고 URL·공유 설정·로그에는 넣지 않습니다. HTTP 자체는 TLS를 제공하지 않으므로 SSH 터널 또는 TLS 프록시 등 보호된 전송 경로가 필요합니다.
- 서버 경로·카메라 IP·셸 명령을 요청에 넣지 않습니다. ID는 서버가 발급하고 반환 URL은 동일 장비의 상대 경로입니다. JSON 요청은 64KiB 이하, 최초 PNG 응답은 16MiB 이하로 제한하며 초과 이미지는 촬영 작업 실패로 보고합니다.

### API 목록

모델 도구까지 설치된 장비의 상태 응답 예시입니다. 실제 기능 노출 여부는 응답의 플래그로 결정합니다. 현재 v1은 정상적인 초기 엔진이 있어야 시작합니다.

```json
{
  "api_version":1,
  "capabilities":{
    "reference_capture":true,
    "reference_revisions":true,
    "model_build":true,
    "model_activation":true
  },
  "device_state":"RUNNING",
  "active_model_id":"model_initial",
  "camera_classes":{
    "stud_camera":["stud"],
    "bolt_head_camera":["bolt_head"],
    "nut_camera":["nut"],
    "nut_hole_camera":["nut_hole","plain_hole"]
  }
}
```

| 메서드·경로 | 요청 또는 응답의 핵심 필드 | 단계 |
| --- | --- | --- |
| `GET /api/reference/status` | 버전, 기능 플래그, 운영 상태, 활성 모델, 카메라별 허용 클래스 | 0 |
| `POST /api/reference/captures` | `request_id`, `camera_id` → `capture_id`, `state` | 1 |
| `GET /api/reference/captures/{capture_id}` | 촬영 상태·오류, 완료 시 이미지 ID·크기·시각·URL | 1 |
| `GET /api/reference/images/{image_id}` | 변경되지 않는 원본 PNG, `Content-Type: image/png` | 1 |
| `POST /api/reference/revisions` | `request_id`, `base_revision_id`, `entries` → 새 예시 버전 | 2 |
| `GET /api/reference/revisions` | `revisions` 목록: ID·기준 버전·생성 시각 | 2 |
| `GET /api/reference/revisions/{revision_id}` | 다섯 클래스의 전체 예시·박스·설정 | 2 |
| `POST /api/model/builds` | `request_id`, `reference_revision_id`, `maintenance_confirmed: true` → `build_id` | 3 |
| `GET /api/model/builds/{build_id}` | 생성 단계·오류, 완료 시 후보 모델 ID·검증 요약 | 3 |
| `GET /api/models` | 활성·후보·과거 모델과 예시 버전·검증 상태 | 3 |
| `POST /api/model/activations` | `request_id`, `model_id`, `expected_active_model_id`, `review_confirmed: true` → `activation_id` | 4 |
| `GET /api/model/activations/{activation_id}` | 적용 단계, 실제 활성 모델, 실패·복구 결과 | 4 |

목록 API는 `limit`(기본 20, 최대 100)과 불투명한 `cursor`를 받으며 `next_cursor`가 null일 때 마지막 페이지입니다. 1차 구현에서는 삭제 API를 제공하지 않습니다. 적용 요청에 이전 정상 모델 ID를 지정하면 되돌리기로 동작합니다.

목록은 생성 시각 내림차순입니다. `GET /api/models`의 각 모델은 `model_id`, `reference_revision_id`, `created_at_ms`, `engine_sha256`, `metadata_sha256`, `technical_passed`, `review_required`를 포함합니다. 생성한 모델에는 `build_id`, `weights_sha256`, `export_config_sha256`, `onnx_sha256`, `validation`도 있습니다. 활성 여부는 상태 API의 `active_model_id`와 비교하고 초기 모델의 기술 검증 기록을 새 빌드의 현장 품질 승인으로 해석하지 않습니다.

v1 한도는 예시 촬영 256건, 예시 버전 512개, 빌드 64건, 적용 64건이며 완료·실패·중단 기록도 포함합니다. 예시 촬영 대기열은 4건입니다. 상태 디렉터리의 파일 용량 한도는 20GiB, 최소 여유 공간은 2GiB입니다. 자동 삭제는 하지 않으며 한도 도달 시 `STORAGE_LIMIT`으로 거부합니다. 재전송 기록은 수동 관리 전까지 계속 보존합니다.

### 촬영과 영역 데이터

촬영 POST 예시:

```json
{"request_id":"550e8400-e29b-41d4-a716-446655440000","camera_id":"stud_camera"}
```

촬영 상태는 `QUEUED`, `CAPTURING`, `READY`, `FAILED`, `INTERRUPTED`입니다. `READY`일 때만 `image`가 존재하며 실패 시 이전 프레임을 대신 반환하지 않습니다. 완료 조회 예시는 다음과 같습니다.

```json
{
  "capture_id":"refcap_123",
  "state":"READY",
  "image":{
    "image_id":"img_123",
    "camera_id":"stud_camera",
    "camera_serial":"40490627",
    "width":1280,
    "height":800,
    "captured_at_ms":1788415200000,
    "source_timestamp_ms":123456,
    "url":"/api/reference/images/img_123"
  },
  "error":null
}
```

`captured_at_ms`는 서버 UTC Unix 밀리초이고 `source_timestamp_ms`는 기존 획득 프레임의 시각입니다. 후자를 다른 장비의 벽시계나 하드웨어 동기 노출 시각으로 해석하지 않습니다. 원본은 보관 기간 동안 불변이며 재촬영은 새 이미지 ID를 생성합니다.

이미지에는 PNG 바이트의 `sha256`도 포함됩니다. 최초 가져온 기준 이미지의 촬영 시각 두 필드는 알 수 없으므로 null입니다. 초기 예시 ID는 `refrev_initial`, 초기 모델 ID는 `model_initial`입니다.

예시 버전 POST 예시:

```json
{
  "request_id":"550e8400-e29b-41d4-a716-446655440001",
  "base_revision_id":"refrev_initial",
  "entries":[
    {"class_name":"stud","image_id":"img_123","boxes":[[475,625,580,755]]}
  ]
}
```

`entries`는 교체할 클래스만 포함합니다. 서버는 기준 버전의 나머지 클래스를 그대로 복사하고 201 응답으로 `revision_id`, `base_revision_id`, `created_at_ms`, 다섯 클래스의 전체 `entries`를 반환합니다. 항목은 `class_name`, `image_id`, `image_url`, `width`, `height`, `boxes`, 유지한 `context_ratio`를 포함합니다. 버전은 불변이고 별도의 자동 활성화 상태를 갖지 않습니다.

박스는 원본 픽셀 좌표의 유한한 숫자 `[x1,y1,x2,y2]`이며 `0 <= x1 < x2 <= width`, `0 <= y1 < y2 <= height`를 만족해야 합니다. 클래스당 1~64개 박스를 허용하고 클래스 중복, 이미지가 준비되지 않은 요청, 잘못된 타입을 거부합니다. 한 이미지를 등록한 뒤 원본 크기가 바뀌는 동작은 허용하지 않습니다. `plain_hole`은 단순한 불량 라벨이 아니라 기존 통합 엔진의 독립 클래스입니다.

카메라별 허용 클래스는 상태 응답에서 얻습니다. 현재 설정 기준으로 `stud_camera: [stud]`, `bolt_head_camera: [bolt_head]`, `nut_camera: [nut]`, `nut_hole_camera: [nut_hole, plain_hole]`입니다. 초기 기준 이미지 가져오기는 서버가 별도로 수행하고 이 매핑 검증을 외부 클라이언트의 임의 경로 입력으로 우회시키지 않습니다.

### 생성·적용 상태와 Studio 동작

- 모델 생성 상태: `QUEUED → PREPARING → EXPORTING → BUILDING → VALIDATING → SUCCEEDED`. 실패·중단은 `FAILED` 또는 `INTERRUPTED`입니다. 응답은 `build_id`, `state`, `reference_revision_id`, `candidate_model_id`(성공 전 null), `validation`(검증 전 null), `error`를 포함합니다.
- 기술 검증 결과는 `validation.technical_passed`와 이미지별 판정·오류를 제공합니다. 양품·불량 승인과 별개이므로 성공한 모델도 사용자 검토 전 자동 적용하지 않습니다.
- 검증 결과의 `results` 항목은 `source`(`prompt` 또는 `baseline`), `class_name`, `status`, `reason`, `latency_ms`를 포함합니다. `baseline`은 최초 다섯 기준 이미지이며 수정하지 않은 예시와 중복될 수 있습니다. 독립된 생산용 평가 데이터가 아니며 `production_approved`는 false입니다. 생성 정책은 FP32, 빌더 최적화 수준 0, 작업 제한 시간 30분입니다.
- 모델 적용 상태: `QUEUED → DRAINING → LOADING → SUCCEEDED`. 새 모델 적재 실패 후 이전 모델 복구 성공은 `ROLLED_BACK`, 복구도 실패하면 `FAILED`입니다. 재시작으로 작업이 끊겼으면 `INTERRUPTED`로 표시하고 `active_model_id`로 실제 복구 결과를 확인합니다.
- 적용 조회는 `activation_id`, `state`, `requested_model_id`, `previous_model_id`, `active_model_id`, `error`를 포함합니다. Studio는 요청 모델이 아니라 서버의 실제 활성 모델을 표시합니다.
- 생성·적용은 장비에서 한 건만 수행합니다. 같은 요청 ID 재조회가 아닌 다른 동시 변경 요청은 409 `MODEL_JOB_BUSY`입니다. 모델 ID의 예상값이 바뀌었으면 409 `ACTIVE_MODEL_CHANGED`이며 사용자가 현재 상태를 다시 확인해야 합니다.
- 모델 작업 중 예시 촬영도 409 `MODEL_JOB_BUSY`입니다. 이미 저장된 이미지의 조회·예시 버전 편집은 가능하며 진행 중인 빌드의 입력 버전은 바뀌지 않습니다.
- 같은 장비의 모델 생성과 적용은 검사·검출 영상 송출을 잠시 중단합니다. 명시적 사용자 승인 없이 요청하지 않으며, `MAINTENANCE` 동안은 제품 NG가 아닌 유지보수 상태를 표시합니다. 아직 수락되지 않은 검사 요청에는 503이 반환됩니다.
- 모델 생성은 기존 모델을 복구한 뒤 종료합니다. 적용은 별도 승인 요청으로만 수행합니다. 실패 화면에서도 현재 활성 모델과 운영 복구 여부를 보여 줍니다.
- Studio는 비동기 작업 ID를 보존해 약 1초 간격으로 상태를 조회하고 연결이 끊겨도 새 작업을 자동 생성하지 않습니다. 예시 편집·저장 완료와 운영 모델 적용 완료를 별도 화면 상태로 관리합니다.

### 전달 기준

**1차: 촬영 → 원본 조회 → 영역 편집 → 예시 버전 저장. 2차: 유지보수 승인 → 모델 생성·검증. 3차: 명시적 적용 → 이전 버전 복구.** 각 단계는 기능 플래그로 구분합니다. 상세 구현·배포·회귀 테스트 항목은 [구현 계획](REFERENCE_IMAGE_IMPLEMENTATION_PLAN.md)에 있습니다.

현재 Inspect는 세 단계의 API를 제공합니다. Studio는 위 순서대로 연결하고, 촬영한 이미지의 실제 대상 박스는 사용자가 확인하도록 해야 합니다. 예시 관리 구현에는 검출 오버레이의 연속 WebSocket 송출 변경이 포함되지 않습니다.
