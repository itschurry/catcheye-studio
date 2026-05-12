# CatchEye Studio

원격 장치에서 실행 중인 CatchEye 장비의 영상을 확인하고, ROI를 편집하기 위한 Flutter 데스크톱 앱입니다.

주 사용 환경은 Windows 데스크톱이며, Guard 또는 Pick 앱은 별도 장치(라즈베리파이5 등)에서 영상 스트림과 REST API를 제공한다고 가정합니다.

## 주요 기능

- `Viewer`
  - 원격 RTSP 또는 WebSocket 스트림 재생
  - Pick viewer-only 다중 WebSocket 스트림(camera/depth/amplitude/rgb/pointcloud) 표시
  - Pick stream별 독립 갱신 수신
  - Pick pointcloud 스트림 2.5D 표시와 point size/axis/depth range/view lock 조절
  - Pick CubeEye property 제어
  - Stream URL과 API Base URL 설정
  - 연결 상태, FPS, 프레임 수 확인

- `ROI Editor`
  - 원격 장치에서 ROI 불러오기 (Load ROI From Device)
  - 폴리곤 존 추가/삭제/이름 변경/활성화 토글
  - 포인트 드래그 편집 및 추가
  - 원격 장치에 ROI 전송 (Push ROI To Device)

## 화면 구성

```
[Viewer]      스트림 연결 및 실시간 영상 확인
[ROI Editor]  ROI 폴리곤 편집과 원격 ROI 동기화
```

좌측 NavigationRail로 두 화면 간 전환합니다.

## 연결 설정

Viewer의 `Change URL` 버튼을 눌러 두 주소를 설정합니다.

| 항목 | 설명 | 예시 |
|---|---|---|
| Stream URL | 영상 수신 주소 (RTSP 또는 WebSocket) | `rtsp://192.168.1.3:8554/live` |
| API Base URL | REST API 주소 (HTTP) | `http://192.168.1.3:8090` |

스트림과 API는 같은 IP라도 포트가 다를 수 있습니다.

## REST API

ROI Editor는 아래 두 엔드포인트를 사용합니다.

- `GET  {apiBaseUrl}/api/roi` — ROI 불러오기
- `PUT  {apiBaseUrl}/api/roi` — ROI 전송

## ROI JSON 형식

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

## 기술 스택

- Flutter / Dart
- `provider` — 상태 관리
- `media_kit` — RTSP 스트림 재생

## 프로젝트 구조

```
lib/
  main.dart                    앱 진입점 및 네비게이션
  models/                      설정/ROI 데이터 모델
  providers/                   상태 관리
  screens/                     화면 UI (viewer, roi_editor)
  services/                    API 통신, 프레임 수신, ROI 파일 입출력
  widgets/                     ROI 캔버스, 뷰어, 존 편집 패널
```

## 실행 방법

```bash
flutter pub get
flutter config --enable-windows-desktop
flutter run -d windows
```

빌드:

```bash
flutter build windows
```

## 참고 사항

- 설정값(URL 등)은 메모리에만 유지되며 앱 재시작 시 초기화됩니다.
- RTSP 재생은 `media_kit` 기반이며, Linux 실행 시 오디오 스택 설정이 필요할 수 있습니다.

### Linux 오디오 스택 (RTSP 재생 시)

```bash
sudo apt install alsa-utils pulseaudio-utils
```

사운드카드가 없는 헤드리스 환경은 더미 장치를 사용합니다.

```bash
sudo modprobe snd-dummy
```
