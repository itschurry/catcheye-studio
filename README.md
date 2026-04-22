# CatchEye Guard App

원격 라즈베리파이5에서 실행 중인 `catcheye-guard` 검출기를 제어하고, ROI JSON을 편집하고, 실시간 프리뷰 스트림을 확인하기 위한 Flutter 데스크톱 앱입니다.

주 사용 환경은 Windows 데스크톱이며, 검출 앱은 별도 라즈베리파이5에서 RTSP 스트림과 제어 API를 제공한다고 가정합니다. Linux 관련 내용은 보조 실행 환경이나 트러블슈팅 용도로만 참고하면 돼.

## 주요 기능

- `Dashboard`
  - 원격 `catcheye-guard` 시작/중지
  - 원격 상태, 연결 대상, 스트림 URL, 최근 동작 로그 확인
- `Viewer`
  - 원격 RTSP 스트림 재생
  - 연결 상태, 연결 URL 확인
- `ROI Editor`
  - ROI JSON 파일 열기/새로 만들기/저장/다른 이름으로 저장
  - 원격 장치에서 ROI 다운로드/업로드
  - 존 추가/삭제/이름 변경/활성화 토글
  - 포인트 드래그 편집 및 포인트 추가
  - 이미지 크기 기준 유효성 검사
- `Settings`
  - 원격 장치 URL, 스트림 경로, API 경로 설정
  - 원격 검출기 설정 불러오기/적용
  - 모델 파일, 메타데이터, ROI 파일 경로 설정
  - 현재 로드된 ROI 구성 요약 확인
- `Logs`
  - 특정 `.log` 파일 또는 디렉터리의 최신 로그 파일 tail 확인

## 화면 구성

- `Dashboard`: 전체 상태 요약과 원격 검출기 제어
- `Viewer`: 프리뷰 스트림 연결 및 실시간 표시
- `ROI Editor`: ROI 폴리곤 편집과 원격 ROI 동기화
- `Settings`: 원격 장치 연결과 검출기 설정
- `Logs`: 로컬 로그 파일 모니터링

## 기술 스택

- Flutter
- Dart
- `provider`
- `file_picker`

## 프로젝트 구조

```text
lib/
  main.dart                    앱 진입점 및 네비게이션
  models/                      설정/ROI 데이터 모델
  providers/                   상태 관리
  screens/                     각 화면 UI
  services/                    원격 제어, 프레임 수신, ROI 파일 입출력
  widgets/                     ROI 캔버스, 뷰어, 존 편집 패널
linux/                         Linux 데스크톱 러너
test/                          위젯 테스트
```

## 실행 환경

다음 환경을 전제로 합니다.

- Flutter SDK 설치
- Windows 데스크톱 타깃 사용 가능 환경
- 원격 라즈베리파이5에서 실행 중인 `catcheye-guard`
- 원격 장치에서 RTSP 스트림과 제어 API 제공
- 필요 시 원격 장치 기준 모델/메타데이터/ROI 설정 파일
  - `.param`
  - `.bin`
  - `.yaml` 또는 `.yml`
  - `.json`

`pubspec.yaml` 기준 SDK 제약은 `Dart ^3.11.1` 입니다.

## Windows 실행 방법

의존성 설치:

```bash
flutter pub get
```

Windows 데스크톱 활성화:

```bash
flutter config --enable-windows-desktop
```

사용 가능한 디바이스 확인:

```bash
flutter devices
```

프로젝트에 `windows/` 러너가 아직 없으면 생성:

```bash
flutter create --platforms=windows .
```

Windows 데스크톱으로 실행:

```bash
flutter run -d windows
```

Windows 빌드:

```bash
flutter build windows
```

테스트 실행:

```bash
flutter test
```

## Linux 참고 사항

아래 내용은 Linux에서 보조적으로 실행하거나 디버깅할 때만 필요해. Windows가 주 타깃이면 평소엔 무시해도 된다.

### Linux 빌드 필수 패키지

이 앱은 Linux 데스크톱에서 `media_kit`, `media_kit_video`, `volume_controller` 플러그인을 사용하므로 시스템 개발 패키지가 필요해.

최소한 아래 패키지는 먼저 깔아둬.

```bash
sudo apt-get update
sudo apt-get install -y \
  pkg-config \
  libasound2-dev \
  libmpv-dev \
  libepoxy-dev
```

패키지가 빠져 있으면 보통 아래 같은 에러로 터져.

- `Could NOT find ALSA (missing: ALSA_LIBRARY ALSA_INCLUDE_DIR)`
- `Target "media_kit_video_plugin" links to: PkgConfig::mpv but the target was not found`

### Linux 런타임 오디오 스택

이 앱은 RTSP 프리뷰를 `media_kit` 기반 플레이어로 재생하므로, Linux 실행 환경에 기본 오디오 스택이 없는 경우 런타임에서 ALSA 또는 오디오 컨트롤러 초기화 에러가 날 수 있어.

먼저 유틸리티 패키지를 깔아.

```bash
sudo apt install alsa-utils
sudo apt install pulseaudio-utils
```

오디오 장치가 실제로 잡히는지 확인:

```bash
aplay -l
pactl info
```

런타임에서 아래 같은 에러가 나면 기본 오디오 장치가 없거나 깨진 상태일 가능성이 커.

- `ALSA lib ... cannot find card '0'`
- `Failed to create AudioController: Failed to attach mixer to card: default`
- `Segmentation fault (core dumped)`

### 사운드카드가 없는 환경

헤드리스 머신, VM, 일부 WSL 환경처럼 실제 사운드카드가 없으면 더미 ALSA 장치를 만들어.

```bash
sudo modprobe snd-dummy
aplay -l
```

부팅 후에도 유지하려면:

```bash
echo snd-dummy | sudo tee /etc/modules-load.d/snd-dummy.conf
```

최소 기준은 `aplay -l` 했을 때 카드가 하나라도 보여야 한다는 거야.

## 기본 사용 흐름

1. `Settings`에서 검출용 라즈베리파이의 Base URL, Stream Path, API Base Path를 지정합니다.
2. 필요하면 원격 장치 기준 모델 `.param`, `.bin`, 메타데이터 `.yaml`, ROI `.json` 경로를 입력합니다.
3. `Load From Device`로 현재 원격 설정을 불러오거나, 값을 수정한 뒤 `Apply To Device`로 반영합니다.
4. `ROI Editor`에서 로컬 ROI 파일을 편집하거나 `Load ROI From Device`로 원격 ROI를 불러옵니다.
5. `Push ROI To Device`로 편집한 ROI를 원격 장치에 올립니다.
6. `Dashboard`에서 `Start`/`Stop`으로 원격 검출기를 제어합니다.
7. `Viewer`에서 원격 RTSP 스트림에 연결합니다.

## 원격 제어 API

앱은 원격 장치의 Base URL과 API Base Path를 조합해서 아래 엔드포인트를 호출합니다.

- `GET /api/status`
  - 예시: `{"status":"running","message":"detector active"}`
- `POST /api/start`
- `POST /api/stop`
- `GET /api/settings`
  - 검출기 설정 JSON 반환
- `PUT /api/settings`
  - 검출기 설정 JSON 반영
- `GET /api/roi`
  - ROI JSON 반환
- `PUT /api/roi`
  - ROI JSON 반영

`status` 값은 `running`, `starting`, `stopping`, `stopped` 중 하나를 기대합니다.

원격 설정 JSON은 아래 필드를 기대합니다.

```json
{
  "camera_pipeline": "libcamerasrc ! ...",
  "model_param_path": "/home/pi/models/model.param",
  "model_bin_path": "/home/pi/models/model.bin",
  "metadata_path": "/home/pi/models/metadata.yaml",
  "roi_config_path": "/home/pi/models/roi.json",
  "roi_enabled": true,
  "roi_auto_reload": true,
  "render_preview": true,
  "filter_by_class": true,
  "filter_class_id": 0
}
```

## 프리뷰 스트림 프로토콜

`Viewer`는 기본적으로 아래 URL로 연결합니다.

```text
rtsp://127.0.0.1:8554/live
```

실제 운영에서는 `Settings`의 `Detector Base URL`과 `Stream Path`(또는 전체 RTSP URL)를 조합한 URL을 사용합니다. `Stream Path`가 `/live` 같은 상대 경로면 `rtsp://<detector-host>:8554/<path>`로 자동 해석합니다. `Viewer`는 `media_kit` 기반 플레이어로 RTSP 스트림을 직접 재생합니다.

## ROI JSON 형식

ROI 편집기는 아래 구조의 JSON을 사용합니다.

```json
{
  "camera_id": "cam_default",
  "image_width": 1280,
  "image_height": 720,
  "allowed_zones": [
    {
      "id": "zone_1",
      "name": "entrance",
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

유효성 검사 기준:

- `image_width`, `image_height`는 0보다 커야 함
- 각 존은 최소 3개의 포인트를 가져야 함
- 모든 포인트는 이미지 경계 안에 있어야 함

## 현재 구현 기준 참고 사항

- 설정값은 메모리에만 유지되며 앱 재시작 후 자동 복원되지 않습니다.
- 로컬 `.json` ROI 파일 편집과 원격 ROI 업로드/다운로드를 함께 지원합니다.
- ROI 기본 자동 로드는 특정 고정 경로를 후보로 검사하는 형태로 유지되어 있습니다.
- Windows를 주 타깃으로 사용한다.
- Linux 실행 경로는 보조 확인용이며, `media_kit` 런타임 의존성 때문에 오디오/그래픽 스택 이슈가 더 쉽게 드러날 수 있다.

## 개발 메모

- 상태 관리는 `provider` 기반입니다.
- 원격 제어 요청 로그는 앱 내부에서 별도로 수집해 `Dashboard`에 표시합니다.
- `Logs` 화면은 파일 시스템을 1초 주기로 폴링합니다.
