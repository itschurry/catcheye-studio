# CatchEye Studio

CatchEye 장비의 영상 스트림을 확인하고 원격 설정을 조정하는 Flutter 데스크톱 앱.

현재 버전: `v1.4.0`

Studio는 연결 시 `GET /api/device-info`를 호출해서 HSS/Pick/Capture/Inspection을 구분하고, 대상에 맞는 화면만 보여준다.
Inspect의 운영 통합 프로파일은 `fastener`이고 캡처 그룹은 `bolt_stud`와 `nut`이야. Studio는 `/api/capture/status`의 `set_id`로 촬영 버튼을 결정해. 이전 그룹·개별 검사 선택 드롭다운과 구버전 API 호환 처리는 없어.
HSS 연결에서 `person_roi_alert_disabled`가 `true`면 Viewer 툴바와 영상 영역 위에 깜빡이는 `ROI Alert Off` 경고를 표시한다.
기존 버전이 저장한 장비 종류 `guard`는 앱 시작 시 `hss`로 자동 변환한다.

## 설치

Linux (Ubuntu/Debian):

```bash
sudo apt install libsecret-1-0 libsecret-1-dev
flutter pub get
```

예시·모델 관리 Bearer 토큰은 Linux Secret Service, macOS Keychain,
Windows Credential Manager 등 운영체제 자격 증명 저장소에 보관한다.

macOS:

```bash
flutter create --platforms=macos .
flutter pub get
```

Windows:

```bash
flutter create --platforms=windows .
flutter pub get
```

Android:

Windows 빌드 환경은 Flutter stable, JDK 17, Android SDK 36을 사용한다. Flutter와 Android SDK를 설치한 뒤 아래 항목이 모두 정상인지 먼저 확인한다.

```powershell
flutter config --android-sdk "C:\Android\Sdk"
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
flutter doctor --android-licenses
flutter doctor -v
```

JDK 설치 경로가 다르면 `--jdk-dir` 값만 실제 경로로 바꾼다. `flutter doctor -v`의 Android toolchain이 정상이어야 한다.

```bash
flutter create --platforms=android .
flutter pub get
```

Windows에서 프로젝트와 Pub 캐시가 서로 다른 드라이브에 있으면 Kotlin 증분 캐시가 실패할 수 있다. `android/gradle.properties`의 `kotlin.incremental=false` 설정을 유지한다.

Android의 `android/app/src/main/AndroidManifest.xml`은 인터넷 권한과 로컬 장비의 `http://`, `ws://` 통신을 위해 `android.permission.INTERNET`과 `android:usesCleartextTraffic="true"`를 사용한다.

iOS/iPadOS:

```bash
flutter create --platforms=ios .
flutter pub get
```

## 실행

Linux:

```bash
flutter run -d linux
flutter build linux --release
```

macOS:

```bash
dart run flutter_launcher_icons
flutter run -d macos
flutter build macos --release
```

Windows:

```bash
dart run flutter_launcher_icons
flutter run -d windows
```

Windows Release 빌드:

```bash
dart run flutter_launcher_icons
flutter build windows --release
```

Android/iOS 아이콘 생성 및 빌드:

```bash
dart run flutter_launcher_icons -f launcher_icons_android.yaml
flutter build apk --release
```

Release APK는 `build/app/outputs/flutter-apk/app-release.apk`에 생성된다.

```bash
dart run flutter_launcher_icons -f launcher_icons_ios.yaml
flutter build ios --release
```

## 검증

```bash
flutter analyze
flutter test
```

촬영 API 테스트는 프로파일별 경로, 빈 본문, 409·503·404 처리와 재전송 방지를 확인해. 촬영 버튼 테스트는 320px·1280px에서 프로파일별 버튼 수·배치·클릭 대상과 비활성 상태를 확인해. 모의 서버·위젯 테스트이며 실카메라 촬영 검증과는 별도야.

## 화면 구성

| 화면 | 대상 | 설명 |
| --- | --- | --- |
| Viewer | HSS / Pick / Capture / Inspection | RTSP 또는 WebSocket 영상 표시, HSS/Capture 녹화, Capture/Inspection 수동 캡처 |
| Images | Capture | 저장장치 용량/사용률, Capture JPEG 합계, 저장된 JPEG 날짜/목록 조회, 큰 이미지 preview, 확대/축소 |
| Monitor | HSS / Capture | 여러 카메라 stream 동시 보기, 영상 더블클릭으로 해당 Viewer 이동 |
| ROI Editor | HSS / Pick | Person 또는 Pallet ROI 편집 |
| Camera Properties | HSS / Capture | 카메라 runtime property 조절 |
| Camera Geometry | Pick | 카메라 intrinsic과 로봇 base 기준 extrinsic 위치 관계 조회 |
| Results | Inspection | 최근 촬영 cycle의 상태, 검사별 판정, 측정값과 원본 JSON 조회 |
| References | Inspection | 원본 예시 촬영·박스 편집·리비전 저장, 모델 빌드·검증·명시적 적용·이전 모델 복구 |

Pick 연결에서는 `Viewer`, `ROI Editor`, `Camera Geometry`만 보여준다.
Capture 연결에서는 데스크톱에서 `Viewer`, `Images`, `Monitor`, `Camera Properties`만 보여주고, 폰에서는 `Viewer`, `Images`, `Monitor`만 보여준다. Capture Viewer에서는 `Capture` 버튼으로 `/api/capture/request`를 호출하고, `Record` 버튼으로 `/api/recording/*`를 호출한다. Images 화면은 `/api/captures/*`로 저장된 JPEG와 `capture_dir`가 올라간 저장장치 용량을 조회한다.

## Monitor에서 Viewer 열기

- 카메라의 영상 영역을 더블클릭하면 Viewer로 이동하고 해당 스트림에 자동 연결한다. 모바일에서는 두 번 탭한다.
- 연결/해제 및 삭제 버튼은 기존 동작을 유지한다. Monitor를 나가면 모니터 스트림 연결은 해제되고, 다시 들어오면 저장된 카메라 목록에 재연결한다.
- 다른 호스트의 카메라를 열면 API Base URL의 호스트도 해당 카메라로 변경한다. 기존 API 프로토콜, 포트, API Base Path는 유지한다. 예: `ws://192.168.0.125:8080` → `http://192.168.0.125:8090`.
- 현재 Viewer와 같은 호스트의 카메라는 기존 API Base URL을 그대로 사용한다. 카메라마다 API 포트가 다르거나 별도 API 서버를 사용하면 Viewer의 `Change URL`에서 직접 지정한다.
- 기존 연결 절차대로 `/api/device-info`와 녹화 상태를 확인한 뒤 연결한다. API 조회 실패 시 오류를 표시하며 다른 카메라로 대신 연결하지 않는다.

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

## Inspection Station Viewer

Inspect는 `--station`으로 실행해. YAML의 `set_id`에 따라 아래 촬영 버튼을 보여줘.

| 실행 프로파일 | 촬영 버튼 | POST 경로 | 검사 대상 |
| --- | --- | --- | --- |
| `fastener` | `Stud + Bolt Head` | `/api/capture/bolt-stud` | 스터드 `.101` + 볼트 머리 `.102` |
| `fastener` | `Nut + Nut Hole` | `/api/capture/nut` | 너트 `.103` + 너트 홀 `.104` |
| `fastener` | `All Cameras (4)` | `/api/capture/all` | 설정된 네 카메라 |
| `bolt_stud` | `All Cameras (2)`만 표시 | `/api/capture/all` | 설정된 스터드·볼트 머리 |
| `nut` | `All Cameras (2)`만 표시 | `/api/capture/all` | 설정된 너트·너트 홀 |

POST 본문은 보내지 않아. `group`·`inspection_id`로 검사 대상을 덮어쓰지 않고, 버튼마다 정해진 경로만 호출해. 전체 카메라 수는 상태 응답의 `cameras` 항목 수이며 미리보기 선택이나 `open:true` 개수가 아니야. 카메라 획득 실패도 검사 결과에서 제외하지 않고 장비 오류로 표시해.

`set_id`가 없거나 상태 조회가 실패하면 촬영 버튼을 표시하지 않고 오류를 보여줘. 연결 끊김·요청 전송 중·준비 안 됨·대기열 포화 상태에서는 버튼을 비활성화해. 버튼은 좁은 화면에서 여러 줄로 배치돼.

**Inspect와 Studio를 함께 업데이트해야 해.** Inspect의 이전 `/api/capture/request`와 개별 프로파일의 그룹 경로는 404야. 오류가 나도 다른 경로로 자동 전환하거나 POST를 재전송하지 않아. Inspect 단일 검사 모드도 `/api/capture/all`을 사용하지만 선택된 검사 하나만 처리해. 별도 CatchEye Capture 앱은 기존 `/api/capture/request`를 그대로 사용해. GPIO 입력 연동은 이번 수정에 포함하지 않아.

`kind: inspection`, `runtime_mode: station` 장비는 Viewer에서 `1×1`, `1×2`,
`2×2` 레이아웃을 제공한다. 각 슬롯은 `/api/viewer/source`가 반환한 카메라
ID 중 하나를 선택한다. 선택 목록은 최대 4개이며 장비 전체에 적용된다.

`1×1`은 기존 `{"camera_id":"..."}` 요청과 호환된다. 다중 레이아웃은
`{"camera_ids":["camera_a","camera_b"]}` 요청과 WebSocket
`viewer_frame` 다중 payload 지원이 필요하다. 각 stream의 `name`은 카메라
ID이며 뒤따르는 JPEG binary frame은 `payload_index` 순서로 매칭된다. 선택을
바꾸더라도 수신 중인 묶음의 binary payload는 끝까지 소비한 뒤 현재 선택에
없는 영상을 버린다. 카메라별 `frame_sequence`가 증가할 때만 영상 수신 시각을
갱신하므로 다른 카메라 때문에 같은 JPEG가 재전송돼도 정지 영상을 정상으로
표시하지 않는다.

미리보기는 raw 영상이며 Capture 결과와 연결하지 않는다. Capture 결과는
cycle ID로 별도 폴링하여 Viewer 상단 결과 행에 표시한다.

Inspect의 결과 파일은 `outputs/{bolt_stud,nut,all}/YYYY-MM-DD/<cycle_id>/`에 저장돼. 결과 JSON의 `storage_path`는 저장 루트 기준 상대 경로이고, Studio의 조회는 계속 `cycle_id`를 사용해. 기존 archive 파일을 결과 API에서 다시 불러오지는 않아.

Inspection의 `Results` 탭은 `GET /api/capture/results`에서 runtime이 보존한
최근 cycle을 조회한다. Studio가 조회한 완료 cycle은 실행 중 자체 보관하며,
runtime 재시작이나 서버 이력 제한으로 응답 목록에서 빠져도 제거하지 않는다.
`last_result`는 다른 요청 결과일 수 있으므로 결과 목록의 대체값으로 사용하지
않는다.

예시 관리 옵션이 설치된 장비는 Viewer의 방패 아이콘에서 전달받은 관리
토큰을 등록한다. Studio는 인증된 `GET /api/reference/status` 기능 플래그를
확인한다. 상태 API의 404나 비활성 기능 플래그만 미지원으로 처리하고, 인증
실패나 일시적인 연결 실패는 관리 화면을 유지한 채 오류로 표시한다. 같은 연결
설정으로 다시 연결해도 기능을 다시 조회한다. 진행 중인 촬영·모델 빌드·적용
상태와 요청 ID는 다른 탭으로 이동해도 유지하고 폴링을 계속한다. 모델 빌드와 적용은 검사를 잠시
중단하므로 각각 별도 확인을 요구하며, 기술 검증 통과를 생산 품질 승인으로
표시하지 않는다. HTTP 자체에는 TLS가 없으므로 원격 관리에는 SSH 터널이나
TLS 프록시를 사용한다.

모바일 `References` 도구 모음은 상태와 작업 전환 버튼을 여러 줄로 배치해서
390px 너비에서도 가로 스크롤이나 오버플로 없이 동작한다.

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
  "app": "catcheye-capture",
  "kind": "capture"
}
```

`kind`는 `hss`, `pick`, `capture`, `inspection` 중 하나여야 한다.
Inspection station은 `runtime_mode: "station"`을 함께 반환한다. HSS 응답에
`person_roi_alert_disabled` bool이 있으면 `true`일 때 Person ROI 침범 감지
알림이 꺼진 상태로 보고 Viewer에 반투명 blink 경고를 띄운다.

## Capture API

아래 표는 별도 CatchEye Capture 앱의 API야. Inspect 촬영 경로는 위 스테이션 표를 따라.

| Method | Path | 용도 |
| --- | --- | --- |
| GET | `/api/device-info` | 연결 대상 종류 조회 |
| GET | `/api/capture/status` | 캡처 상태 조회 |
| POST | `/api/capture/request` | 수동 캡처 요청 |
| GET | `/api/captures/dates` | 저장된 JPEG 날짜 목록 조회 |
| GET | `/api/captures?date=YYYY-MM-DD&limit=100&cursor=<filename>` | 저장된 JPEG 목록 조회 |
| GET | `/api/captures/file/<date>/<filename>` | 저장된 JPEG 원본 조회 |
| GET | `/api/captures/latest` | 최신 저장 JPEG metadata 조회 |
| GET | `/api/recording` | 녹화 상태 조회 |
| POST | `/api/recording/start` | 녹화 시작 |
| POST | `/api/recording/pause` | 녹화 일시정지 |
| POST | `/api/recording/resume` | 녹화 재시작 |
| POST | `/api/recording/save` | 녹화 저장 |
| POST | `/api/recording/cancel` | 녹화 취소 |
| GET | `/api/rgb-camera/properties` | RGB 카메라 속성 조회 |
| PUT | `/api/rgb-camera/properties/<key>` | RGB 카메라 속성 변경 |

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

## HSS API

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
├── assets/
│   ├── app_icon.ico
│   └── app_icon.png
├── android/
│   ├── app/src/main/AndroidManifest.xml
│   └── gradle.properties
├── launcher_icons_android.yaml
├── launcher_icons_ios.yaml
├── pubspec.yaml
└── README.md
```
