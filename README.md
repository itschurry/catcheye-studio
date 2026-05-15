# CatchEye Studio

CatchEye 장비의 영상 스트림을 확인하고, 원격 설정을 조정하는 Flutter 데스크톱 앱.

Guard 또는 Pick 앱은 별도 장치에서 영상 스트림과 REST API를 제공하고, Studio는 PC에서 붙어서 상태 확인과 설정 변경을 담당해.

## 주요 기능

- Viewer
  - RTSP 스트림 재생
  - WebSocket JPEG/pointcloud 다중 스트림 표시
  - 스트림별 독립 갱신 수신
  - RGB Camera / CubeEye ToF / Other Streams 그룹 표시
  - 좌우 분할 화면에서 표시할 스트림 직접 선택
  - pointcloud point size, palette, axis, depth range, view lock 조절
  - depth 영상 컬러바와 축 표시
  - CubeEye property 제어
  - RGB-CubeEye 오프셋 조절
  - pointcloud ROI, robot calibration 설정

- ROI Editor
  - Person ROI / Pallet ROI 전환
  - 원격 장치에서 ROI 불러오기
  - 폴리곤 존 추가/삭제/이름 변경/활성화 토글
  - 포인트 드래그 편집 및 추가
  - 원격 장치에 ROI 전송

## 화면 구성

```text
Viewer      스트림 연결, 다중 스트림 표시, CubeEye/pointcloud 설정
ROI Editor  Person/Pallet ROI 편집과 원격 동기화
```

좌측 NavigationRail로 화면을 전환해.

## 연결 설정

Viewer의 URL 설정에서 아래 값을 지정해.

| 항목 | 설명 | 기본값 |
| --- | --- | --- |
| Stream URL | RTSP 또는 WebSocket 스트림 주소 | `ws://127.0.0.1:8080` |
| API Base URL | REST API 서버 주소 | `http://127.0.0.1:8090` |
| API Base Path | REST API prefix | `/api` |

예시:

```text
Stream URL   ws://192.168.1.3:8080
API Base URL http://192.168.1.3:8090
```

RTSP를 쓸 때는 `rtsp://192.168.1.3:8554/live`처럼 전체 URL을 넣으면 돼.

## REST API

Studio가 사용하는 주요 엔드포인트야. 실제 prefix는 `API Base Path` 값이 붙어.

| Method | Path | 용도 |
| --- | --- | --- |
| GET | `/api/roi` | Person ROI 불러오기 |
| PUT | `/api/roi` | Person ROI 저장 |
| GET | `/api/pallet-roi` | Pallet ROI 불러오기 |
| PUT | `/api/pallet-roi` | Pallet ROI 저장 |
| GET | `/api/cubeeye/properties` | CubeEye property 조회 |
| PUT | `/api/cubeeye/properties/{key}` | CubeEye property 변경 |
| GET | `/api/rgb-cubeeye-offset` | RGB-CubeEye 오프셋 조회 |
| PUT | `/api/rgb-cubeeye-offset` | RGB-CubeEye 오프셋 저장 |
| GET | `/api/pointcloud-roi` | pointcloud ROI 조회 |
| PUT | `/api/pointcloud-roi` | pointcloud ROI 저장 |
| GET | `/api/robot-calibration` | robot calibration 조회 |
| PUT | `/api/robot-calibration` | robot calibration 저장 |

## ROI JSON

```json
{
  "camera_id": "cam_default",
  "image_width": 1280,
  "image_height": 720,
  "allowed_zones": [
    {
      "id": "zone_1",
      "name": "main_safe_zone",
      "enabled": true,
      "points": [
        [120.0, 100.0],
        [600.0, 110.0],
        [640.0, 420.0],
        [140.0, 430.0]
      ]
    }
  ]
}
```

## 실행

의존성 설치:

```bash
flutter pub get
```

macOS 실행:

```bash
flutter config --enable-macos-desktop
flutter run -d macos
```

macOS 빌드:

```bash
flutter build macos
```

Windows 실행:

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

Windows 빌드:

```bash
flutter build windows
```

## 프로젝트 구조

```text
lib/
  main.dart                    앱 진입점
  models/                      설정, ROI 데이터 모델
  providers/                   설정/ROI 상태 관리
  screens/                     Viewer, ROI Editor 화면
  services/                    REST API, 프레임 수신, ROI 파일 처리
  widgets/                     뷰어, 스트림 선택, ROI 캔버스, pointcloud UI
```

## 저장소 기준

- `macos/`, `windows/`, `linux/` 폴더는 Flutter가 생성하는 플랫폼 산출물이라 Git에 올리지 않아.
- macOS 빌드가 필요하면 로컬에서 `flutter build macos`로 생성해서 써.
- URL, pointcloud viewer 설정은 `shared_preferences`에 저장돼.

## 참고

- RTSP 재생은 `media_kit` 기반이야.
- WebSocket viewer는 text metadata와 binary payload를 받아서 stream별 최신 프레임을 표시해.
- 실패한 REST 요청은 숨기지 않고 그대로 에러로 보여주는 구조야.
