# CatchEye Studio

CatchEye 장비의 영상 스트림을 확인하고 원격 설정을 조정하는 Flutter 데스크톱 앱.

Studio는 연결 시 `GET /api/device-info`를 호출해서 Guard/Pick을 구분하고, 대상에 맞는 화면만 보여준다.
Guard 연결에서 `person_roi_alert_disabled`가 `true`면 Viewer 툴바와 영상 영역 위에 깜빡이는 `ROI Alert Off` 경고를 표시한다.

## 설치

```bash
flutter pub get
```

## 실행

```bash
flutter run -d macos
```

## 화면 구성

| 화면 | 대상 | 설명 |
| --- | --- | --- |
| Viewer | Guard / Pick | RTSP 또는 WebSocket 영상 표시 |
| Monitor | Guard | 여러 카메라 stream 동시 보기 |
| ROI Editor | Guard / Pick | Person 또는 Pallet ROI 편집 |
| Camera Properties | Guard | 카메라 runtime property 조절 |
| Camera Geometry | Pick | 카메라 intrinsic과 로봇 base 기준 extrinsic 위치 관계 조회 |

Pick 연결에서는 `Viewer`, `ROI Editor`, `Camera Geometry`만 보여준다.

## Pick Viewer 스트림

Pick Viewer는 WebSocket `viewer_frame` multi-stream을 받으면 우측 `Streams` 패널에 RGB와 Depth를 나눠 보여준다.

Desktop에서는 Split View를 켜면 왼쪽은 color/RGB JPEG, 오른쪽은 depth JPEG를 기본 선택한다. Depth stream이 없으면 오른쪽 패널은 비어 있다.

예시 metadata:

```json
{
  "type": "viewer_frame",
  "streams": [
    {
      "name": "camera",
      "kind": "camera",
      "encoding": "jpeg",
      "payload_index": 0,
      "width": 1280,
      "height": 720
    },
    {
      "name": "depth",
      "kind": "depth",
      "encoding": "jpeg",
      "payload_index": 1,
      "width": 1280,
      "height": 720
    }
  ]
}
```

## 연결 설정

Viewer의 URL 설정에서 아래 값을 지정한다.

| 항목 | 설명 | 기본값 |
| --- | --- | --- |
| Stream URL | RTSP 또는 WebSocket 스트림 주소 | `ws://127.0.0.1:8080` |
| API Base URL | REST API 서버 주소 | `http://127.0.0.1:8090` |
| API Base Path | REST API prefix | `/api` |

예시:

```text
Stream URL   ws://192.168.1.4:8080
API Base URL http://192.168.1.4:8090
```

`GET /api/device-info` 응답 예시:

```json
{
  "app": "catcheye-guard",
  "kind": "guard",
  "person_roi_alert_disabled": false,
  "roi_alert_output_active": true
}
```

`kind`는 `guard` 또는 `pick`이어야 한다. `person_roi_alert_disabled`는 bool 필수값이고, `true`면 Person ROI 침범 감지 알림이 꺼진 상태로 보고 Viewer에 반투명 blink 경고를 띄운다.

## Pick API

| Method | Path | 용도 |
| --- | --- | --- |
| GET | `/api/device-info` | 연결 대상 종류 조회 |
| GET | `/api/camera/intrinsics` | camera intrinsic 값 조회 |
| GET | `/api/camera/extrinsics` | camera extrinsic transform 조회 |
| GET | `/api/pallet-roi` | Pallet ROI 조회 |
| PUT | `/api/pallet-roi` | Pallet ROI 저장 |
| GET | `/api/robot-calibration` | robot calibration 조회 |
| PUT | `/api/robot-calibration` | robot calibration 저장 |

## Guard API

| Method | Path | 용도 |
| --- | --- | --- |
| GET | `/api/device-info` | 연결 대상 종류 조회 |
| GET | `/api/roi` | Person ROI 조회 |
| PUT | `/api/roi` | Person ROI 저장 |
| GET | `/api/pallet-roi` | Pallet ROI 조회 |
| PUT | `/api/pallet-roi` | Pallet ROI 저장 |
| GET | `/api/recording` | 녹화 상태 조회 |
| POST | `/api/recording/start` | 녹화 시작 |
| POST | `/api/recording/pause` | 녹화 일시정지 |
| POST | `/api/recording/resume` | 녹화 재시작 |
| POST | `/api/recording/save` | 녹화 저장 |
| POST | `/api/recording/cancel` | 녹화 취소 |

## 디렉터리 구조

```text
.
├── lib/
│   ├── models/
│   ├── providers/
│   ├── screens/
│   ├── services/
│   └── widgets/
├── macos/
├── pubspec.yaml
└── README.md
```
