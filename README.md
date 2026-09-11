# CatchEye Studio

## Inspect 제품 레시피와 PLC 진단

Inspect 연결 시 뷰어 다음에 표시되는 **검사 관리** 메인 탭에서 다음 기능을 사용합니다.
메뉴 순서는 **카메라 설정 / 제품 레시피 / 생산 검사 / PLC 통신 진단 / PLC 디버그**입니다. 모든 메뉴는 같은 화면의 탭으로 표시되며, 처음에는 제품 레시피가 선택됩니다.
다른 메인 탭으로 이동해도 저장하지 않은 레시피·카메라 설정(선택한 보정 파일 포함)과 내부 메뉴 선택은 유지됩니다.
검사 관리 탭이 숨겨져 있을 때는 주기적인 상태 조회를 멈추고, 돌아오면 서버 상태를 다시 조회합니다.
연결 장비의 API 주소가 바뀌면 이전 장비의 편집 내용은 초기화됩니다.

- 기본 제품 5종의 포인트·검사 항목·기대 개수 편집, **제품 추가**로 최대 255종 확장
- 포인트 추가·복제·삭제·위/아래 이동과 실시간 카메라 확인. 목록 번호가 PLC의 포인트 번호입니다.
- 미정 값은 초안 저장, 필수 기준 검증 후 운영 적용
- 제품·포인트를 직접 지정한 **1회 촬영**, 촬영별 이미지·판정 사유·이력 조회
- **PLC 통신 진단 → PLC 설정**에서 IP·포트, 프레임 크기·바이트 순서·신호 매핑 편집과 즉시 적용
- PLC 신호의 ON/OFF, 트리거·오류·OK/NG 송신 기록 확인
- **PLC 디버그**에서 실제 PLC/내장 시뮬레이터 선택, 제품·포인트·하드웨어 신호 전송 및 실제 촬영 결과 확인

Inspect는 요청된 포인트를 한 번 판정하며 검사 시작·종료·순서 강제·전체 판정·결과 ACK를 처리하지 않습니다.
로봇 이동과 이후 동작은 PLC가 관리합니다. Studio 수동 검증은 PLC 연결을 해제한 상태에서 사용합니다.
레시피는 Inspect의 state/production에 저장되며 촬영 중에는 적용을 막고 초안 편집은 허용합니다.

PLC는 제품·포인트·하드웨어 ON/OFF 단일 규약을 사용하며 버전을 선택하지 않습니다. 신호 하나는 2바이트의 0/1이고 위치는 0부터 시작합니다.
입력은 제품별 전용 선택 신호·포인트별 전용 선택 신호·하드웨어 선택 4칸, 출력은 OK·NG·Heartbeat 세 칸입니다.
제품 5·포인트 2·스터드라면 product_5, point_2, hardware_1을 켭니다. 세 종류가 각각 하나씩 ON이 되면 1회 촬영합니다.
하드웨어는 0=볼트 머리, 1=스터드, 2=너트, 3=너트 홀이며 해당 포인트 레시피와 일치해야 합니다.
한 종류라도 모두 OFF이면 준비 상태입니다. 세 종류가 채워졌을 때 다중 선택이나 레시피 불일치는 촬영 없이 NG입니다.
**PLC 설정 → 신호표 자동 생성**에서 제품 수와 최대 촬영 포인트 수를 입력합니다.
제품은 **1~255종**, 최대 촬영 포인트는 **1~200개**로 지정할 수 있습니다. 레시피에 제품 5종·포인트 5개가 있어도 PLC에서 사용할 범위를 각각 1개로 생성할 수 있습니다.
위치가 지정된 기존 선택 신호가 있으면 그 범위를 채우고, 없으면 저장된 초안·적용 레시피의 개수를 제안합니다. 1개로 저장한 신호표도 다시 열 때 그대로 유지합니다.
포인트가 아직 없으면 최대 촬영 포인트 수를 직접 입력해야 합니다. 하드웨어는 4종 고정입니다.

1. PLC IP·포트를 입력하고 제품 수·최대 촬영 포인트 수를 확인합니다.
2. 미리보기에서 제품 → 포인트 → 하드웨어 순으로 배정될 위치를 확인합니다.
3. 촬영 완료·PLC 연결 해제 상태에서 **신호표 생성 · 편집에 반영**을 누릅니다.
4. **저장 및 적용**으로 Inspect에 저장하고 PLC 프로그램의 신호표·프레임 길이도 맞춥니다. 연결은 별도입니다.

예: 제품 5종·최대 5포인트이면 제품 `0~4`, 포인트 `5~9`, 하드웨어 `10~13`이며 수신은 14워드입니다.
송신은 OK=0·NG=1·Heartbeat=2, 총 3워드로 생성됩니다. 1워드는 2바이트입니다.
A 제품이 5포인트, B 제품이 3포인트여도 공통 포인트 신호는 5개를 사용합니다. B 제품에 포인트 4 요청이 오면 촬영 없이 `UNKNOWN_POINT` NG입니다.
**개수 입력·레시피 변경만으로 기존 신호표를 바꾸지 않습니다.** 생성 버튼을 누르면 기존 수신·송신 위치와 워드 수를 미리보기대로 교체합니다.
제품 수가 늘면 뒤의 포인트·하드웨어 위치가 이동하므로 PLC 프로그램도 함께 수정해야 합니다. 레시피 추가와 PLC 신호표 저장은 별도입니다.
기존 개별 위치를 유지하려면 **고급 설정 · 프레임과 신호 매핑**을 펼쳐 **선택 신호 추가**로 빈 위치에 추가합니다.
고급 설정에서는 수신·송신 워드 수, 바이트 순서, 송신 주기, 제한 시간과 개별 위치를 편집합니다. RX는 6~512칸, TX는 3~512칸입니다.
제품은 1~255, 포인트는 1~200이며 등록·적용된 레시피만 검사할 수 있습니다.
새 요청마다 이전 결과를 최소 한 송신 주기 동안 0/0으로 내리고 새 OK/NG를 출력합니다. PLC는 0/0 이후 새 결과를 처리해야 합니다.
다음 요청 전에는 한 종류의 선택이 모두 OFF인 프레임이 필요합니다. 제품·포인트는 유지하고 하드웨어만 모두 OFF로 내렸다가 다시 선택해도 됩니다.
ON을 계속 유지하면 중복 촬영하지 않습니다. 별도 트리거는 없으며 결과는 다음 요청까지 유지합니다. 자동 재시도와 별도 ACK는 없습니다.

설정은 촬영 완료 및 PLC 연결 해제 후 저장하며 재시작 없이 적용됩니다. 연결은 별도로 실행합니다.
운영 설정은 Inspect의 state/production/plc_network.json에 저장합니다.
생산 API v3를 지원하는 Inspect가 필요합니다. PLC 설정·상태의 protocol 필드와 저장 JSON의 schema_version은 사용하지 않습니다.
저장 JSON에는 revision과 config만 포함하며 revision은 동시 저장 충돌 방지에 사용합니다.
필수 신호 누락·중복 위치·잘못된 값은 오류로 표시합니다. 설정 초기화가 필요하면 서버의 docs/PRODUCTION_RECIPES.md 절차에 따라
운영 PLC JSON을 삭제하고 새 설치본의 YAML로 시작한 뒤 신호표를 다시 입력하세요. 버전별 보관이나 자동 변환은 하지 않습니다.
기존 5종 레시피는 보존됩니다. 제품 추가 API는 POST /api/production/products, 촬영 이력은 GET /api/production/captures입니다.
PLC IP가 서버의 허용 대역 밖이면 관리자 네트워크 설정이 필요합니다.

**카메라 설정:** 검사 관리 메뉴에서 제품 레시피 앞의 **카메라 설정** 탭에서 Inspect가 검색한 Basler 카메라의 시리얼·IP·모델을 확인합니다.
각 카메라에 미사용 또는 하드웨어 하나를 배정하고 **보정 파일 선택**으로 최대 64 KiB의 ROS camera_info YAML을 업로드합니다.
보정 파일은 시리얼에 연결되어 하드웨어를 바꿔도 유지됩니다. 왜곡 보정 사용 여부를 선택하고 촬영 완료·PLC 연결 해제 후 저장합니다.
Inspect가 카메라를 열어 프레임을 읽고 보정 파일·촬영 해상도를 검증한 뒤 재시작 없이 적용합니다. 저장 후 **영상 확인**으로 확인합니다.
중복 배정·연결 누락·잘못된 파일은 오류로 표시합니다. 미배정 하드웨어의 촬영 요청은 오류이며 카메라를 임의 대체하지 않습니다.
ROI 정보가 없는 보정 파일은 화면에 표시된 촬영 크기·센서 ROI와 보정 당시 조건이 같은지 확인해야 합니다.
GET/PUT `/api/production/camera-setup`을 지원하는 Inspect가 필요합니다. 설정과 파일은 Inspect의 `state/production/cameras/`에 저장됩니다.
Studio PC의 파일 경로는 서버에 전달하지 않고 파일 내용을 전송합니다. 저장 오류 후에는 재검색으로 서버 상태를 확인해야 합니다.

**GUI 사용:** `PLC 디버그 → PLC 시뮬레이터 → 시뮬레이터 연결`을 누르고 제품·포인트·하드웨어를 선택한 뒤
**신호 전송 · 실제 촬영**을 누릅니다. 예: 제품 5·포인트 2·스터드(1).
Inspect 내부의 TCP 시뮬레이터가 실제 PLC 수신 경로로 ON/OFF를 보내고,
GUI에서 수신 확인·결과 초기화·OK/NG·Heartbeat와 실제 이미지·기대/검출 개수·판정 사유를 확인합니다.
레시피와 다른 하드웨어를 선택하면 촬영 없이 NG를 반환하는 경로도 시험할 수 있습니다.
이전 이미지는 이번 요청 결과로 재사용하지 않습니다. 테스트 촬영은 `plc_simulator`로 기록됩니다.

**현장 사용:** `연결 해제 → 실제 PLC → 실제 PLC 연결`을 누릅니다.
실제 PLC 모드에서는 PLC가 보낸 선택 신호와 Inspect 결과를 감시하며 GUI 입력 전송은 제공하지 않습니다.
IP·포트·현장 신호표는 기존 PLC 설정을 사용합니다. 시뮬레이터 연결은 이 설정을 저장하거나 변경하지 않습니다.
연결 중 모드 전환은 잠기고 촬영 완료·연결 해제 후 다시 연결할 수 있습니다.
Studio를 닫아도 서버 시뮬레이터는 유지되므로 종료할 때 **연결 해제**를 누르세요.
GUI와 원격 Inspect 사이에 별도 PLC 수신 포트를 열 필요는 없습니다. 시뮬레이터는 Inspect의 loopback에서 실행됩니다.

내장 시뮬레이터는 `plc.simulator_supported:true`가 필요하며 미지원 서버에는 업데이트 안내를 표시합니다.
RX 459/TX 3칸으로 제품 1~255·포인트 1~200·하드웨어 0~3을 지원합니다.
실제 카메라·추론은 그대로 사용하며 TCP 검증은 내부 연결에 대한 검증입니다. 현장 PLC/Wi-Fi 검증은 별도로 수행하세요.

터미널 도구 `python3 tools/plc_simulator.py --fragment`도 유지합니다.
이 도구는 제품 1~5·포인트 1~16, RX/TX 32칸이며 내장 GUI 배치와 다릅니다.
터미널 도구를 사용하려면 기존 PLC 설정에서 `plc_network.simulator.yaml` 배치를 직접 설정하고
`capture 5 2 1`처럼 명령을 입력합니다.


Inspect의 `/api/production/*` v3과 독립 촬영 `capture_api_version: 2`가 필요합니다.
fastener의 기존 두 그룹 버튼은 볼트 머리·스터드·너트·너트 홀 네 개별 버튼으로 바뀌었습니다.
구버전 그룹 경로로 전환하지 않습니다. 서버와 Studio를 함께 업데이트해야 합니다.

생산 화면은 `lib/screens/production_screen.dart`, API는 `lib/services/remote_production_api_service.dart`, 응답 모델과 제어 조건은 `lib/models/production.dart`에서 관리합니다.
화면 테스트와 API 테스트는 `test/production_screen_test.dart`, `test/production_api_test.dart`에 있습니다.
GUI 디버그는 `lib/widgets/plc_debug_panel.dart`와 `test/plc_debug_panel_test.dart`에서 관리합니다.
PLC 설정 입력창과 회귀 테스트는 `lib/widgets/plc_settings_dialog.dart`, `test/plc_settings_dialog_test.dart`에 있습니다.

```bash
flutter analyze --no-pub
flutter test --no-pub
```

Inspect의 C++ Docker 빌드는 서버에서 수행합니다. Studio 앱의 검증과 Linux 빌드는 아래 명령을 사용합니다.
현장 PLC의 IP·포트·워드 길이·신호 위치는 별도 확정이 필요하며, Wi-Fi 자체가 PLC 프로토콜은 아닙니다.
Inspect 저장소의 `docs/PRODUCTION_RECIPES.md`가 TCP 신호 규약과 서버 검증 절차의 기준입니다.


CatchEye 장비의 영상 스트림을 확인하고 원격 설정을 조정하는 Flutter 데스크톱 앱입니다.

현재 버전: `v1.4.0`

Studio는 연결 시 `GET /api/device-info`를 호출해서 HSS/Pick/Capture/Inspection을 구분하고, 대상에 맞는 화면만 보여 줍니다.
Inspect의 운영 통합 프로파일은 `fastener`이고 캡처 그룹은 `bolt_stud`와 `nut`입니다. Studio는 `/api/capture/status`의 `set_id`로 촬영 버튼을 결정합니다. 이전 그룹·개별 검사 선택 드롭다운과 구버전 API 호환 처리는 없습니다.
HSS 연결에서 `person_roi_alert_disabled`가 `true`면 뷰어 툴바와 영상 영역 위에 깜빡이는 `ROI 경고 꺼짐` 경고를 표시합니다.
기존 버전이 저장한 장비 종류 `guard`는 앱 시작 시 `hss`로 자동 변환합니다.

## 설치

Linux (Ubuntu/Debian):

```bash
sudo apt install libsecret-1-0 libsecret-1-dev libmpv-dev libswscale-dev
flutter pub get
```

예시·모델 관리 Bearer 토큰은 Linux Secret Service, macOS Keychain,
Windows Credential Manager 등 운영체제 자격 증명 저장소에 보관합니다.

macOS:

```bash
flutter create --platforms=macos .
flutter pub get
```

Windows:

Visual Studio Installer에서 C++ 데스크톱 빌드 도구와 설치된 MSVC 버전에 맞는 C++ ATL(x86 및 x64) 구성 요소를 설치합니다. `flutter_secure_storage_windows` 빌드에 ATL이 필요하며, 누락되면 `atlstr.h`를 찾을 수 없다는 오류가 발생합니다.

```bash
flutter create --platforms=windows .
flutter pub get
```

Android:

Windows 빌드 환경은 Flutter stable, JDK 17, Android SDK 36을 사용합니다. Flutter와 Android SDK를 설치한 뒤 아래 항목이 모두 정상인지 먼저 확인합니다.

```powershell
flutter config --android-sdk "C:\Android\Sdk"
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
flutter doctor --android-licenses
flutter doctor -v
```

JDK 설치 경로가 다르면 `--jdk-dir` 값만 실제 경로로 바꿉니다. `flutter doctor -v`의 Android toolchain이 정상이어야 합니다.

```bash
flutter create --platforms=android .
flutter pub get
```

Windows에서 프로젝트와 Pub 캐시가 서로 다른 드라이브에 있으면 Kotlin 증분 캐시가 실패할 수 있습니다. `android/gradle.properties`의 `kotlin.incremental=false` 설정을 유지합니다.

Android의 `android/app/src/main/AndroidManifest.xml`은 인터넷 권한과 로컬 장비의 `http://`, `ws://` 통신을 위해 `android.permission.INTERNET`과 `android:usesCleartextTraffic="true"`를 사용합니다.

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

Release APK는 `build/app/outputs/flutter-apk/app-release.apk`에 생성됩니다.

```bash
dart run flutter_launcher_icons -f launcher_icons_ios.yaml
flutter build ios --release
```

## 검증

```bash
flutter analyze
flutter test
```

촬영 API 테스트는 프로파일별 경로, 빈 본문, 409·503·404 처리와 재전송 방지를 확인합니다. 촬영 버튼 테스트는 320px·1280px에서 프로파일별 버튼 수·배치·클릭 대상과 비활성 상태를 확인합니다. 모의 서버·위젯 테스트이며 실카메라 촬영 검증과는 별도입니다.

## 화면 구성

| 화면 | 대상 | 설명 |
| --- | --- | --- |
| 뷰어 | HSS / Pick / Capture / Inspection | RTSP 또는 WebSocket 영상 표시, HSS/Capture 녹화, Capture/Inspection 수동 캡처 |
| 검사 관리 | Inspection | 제품 레시피 편집·적용, 생산 검사, PLC 통신 진단·설정·디버그 |
| 저장 이미지 | Capture | 저장장치 용량/사용률, Capture JPEG 합계, 저장된 JPEG 날짜/목록 조회, 큰 이미지 preview, 확대/축소 |
| 모니터 | HSS / Capture | 여러 카메라 stream 동시 보기, 영상 더블클릭으로 해당 뷰어 이동 |
| ROI 편집 | HSS / Pick | Person 또는 Pallet ROI 편집 |
| 카메라 설정 | HSS / Capture | 카메라 runtime property 조절 |
| 카메라 위치 | Pick | 카메라 intrinsic과 로봇 base 기준 extrinsic 위치 관계 조회 |
| 검사 결과 | Inspection | 날짜별 저장 결과·용량, 검사 이미지, 검사별 판정·점검 안내, 측정값과 원본 JSON 조회 |
| 기준 이미지 | Inspection | 원본 예시 촬영·박스 편집·리비전 저장, 모델 빌드·검증·명시적 적용·이전 모델 복구 |

Pick 연결에서는 `뷰어`, `ROI 편집`, `카메라 위치`만 보여 줍니다.
Inspection 연결에서는 데스크톱과 폰 모두 `뷰어`, `검사 관리`, `검사 결과` 순서로 표시하고, 기준 이미지 관리가 제공되면 `기준 이미지`를 마지막에 표시합니다.
Capture 연결에서는 데스크톱에서 `뷰어`, `저장 이미지`, `모니터`, `카메라 설정`만 보여주고, 폰에서는 `뷰어`, `저장 이미지`, `모니터`만 보여 줍니다. Capture 뷰어에서는 `촬영` 버튼으로 `/api/capture/request`를 호출하고, `녹화` 버튼으로 `/api/recording/*`를 호출합니다. 저장 이미지 화면은 `/api/captures/*`로 저장된 JPEG와 `capture_dir`가 올라간 저장장치 용량을 조회합니다.

## 모니터에서 뷰어 열기

- 카메라의 영상 영역을 더블클릭하면 Viewer로 이동하고 해당 스트림에 자동 연결합니다. 모바일에서는 두 번 탭합니다.
- 연결/해제 및 삭제 버튼은 기존 동작을 유지합니다. Monitor를 나가면 모니터 스트림 연결은 해제되고, 다시 들어오면 저장된 카메라 목록에 재연결합니다.
- 다른 호스트의 카메라를 열면 API Base URL의 호스트도 해당 카메라로 변경합니다. 기존 API 프로토콜, 포트, API Base Path는 유지합니다. 예: `ws://192.168.0.125:8080` → `http://192.168.0.125:8090`.
- 현재 Viewer와 같은 호스트의 카메라는 기존 API Base URL을 그대로 사용합니다. 카메라마다 API 포트가 다르거나 별도 API 서버를 사용하면 Viewer의 `연결 주소 변경`에서 직접 지정합니다.
- 기존 연결 절차대로 `/api/device-info`와 녹화 상태를 확인한 뒤 연결합니다. API 조회 실패 시 오류를 표시하며 다른 카메라로 대신 연결하지 않습니다.

## Pick 뷰어 스트림

Pick Viewer는 WebSocket `viewer_frame` multi-stream을 받으면 우측 `영상 목록` 패널에 RGB와 Depth를 나눠 보여 줍니다.

Desktop에서는 Split View를 켜면 왼쪽은 color/RGB JPEG, 오른쪽은 depth JPEG를 기본 선택합니다. Depth stream이 없으면 오른쪽 패널은 비어 있습니다.

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

## Inspection Station 뷰어

Inspect는 `--station`으로 실행합니다. YAML의 `set_id`에 따라 아래 촬영 버튼을 표시합니다. 데스크톱·모바일 모두 스테이션 패널의 대상별 버튼으로 촬영하고, 상단 툴바의 일반 `촬영` 버튼은 표시하지 않습니다.

| 실행 프로파일 | 촬영 버튼 | POST 경로 | 검사 대상 |
| --- | --- | --- | --- |
| `fastener` | `Bolt Head` | `/api/capture/bolt-head` | 볼트 머리 `.102` |
| `fastener` | `Stud` | `/api/capture/stud` | 스터드 `.101` |
| `fastener` | `Nut` | `/api/capture/nut` | 너트 `.103` |
| `fastener` | `Nut Hole` | `/api/capture/nut-hole` | 너트 홀 `.104` |
| `bolt_stud` | `전체 카메라 (2)`만 표시 | `/api/capture/all` | 설정된 스터드·볼트 머리 |
| `nut` | `전체 카메라 (2)`만 표시 | `/api/capture/all` | 설정된 너트·너트 홀 |

POST 본문은 보내지 않습니다. `group`·`inspection_id`로 검사 대상을 덮어쓰지 않고, 버튼마다 정해진 경로만 호출합니다. 전체 카메라 수는 상태 응답의 `cameras` 항목 수이며 미리보기 선택이나 `open:true` 개수가 아닙니다. 카메라 획득 실패도 검사 결과에서 제외하지 않고 장비 오류로 표시합니다.

`set_id`가 없거나 상태 조회가 실패하면 촬영 버튼을 표시하지 않고 오류를 표시합니다. 연결 끊김·요청 전송 중·준비 안 됨·대기열 포화 상태에서는 버튼을 비활성화합니다. 버튼은 좁은 화면에서 여러 줄로 배치됩니다.

**Inspect와 Studio를 함께 업데이트해야 합니다.** Inspect의 이전 `/api/capture/request`와 개별 프로파일의 그룹 경로는 404입니다. 오류가 나도 다른 경로로 자동 전환하거나 POST를 재전송하지 않습니다. Inspect 단일 검사 모드도 `/api/capture/all`을 사용하지만 선택된 검사 하나만 처리합니다. 별도 CatchEye Capture 앱은 기존 `/api/capture/request`를 그대로 사용합니다. GPIO 입력 연동은 이번 수정에 포함하지 않습니다.

`kind: inspection`, `runtime_mode: station` 장비는 Viewer에서 `1×1`, `1×2`,
`2×2` 레이아웃을 제공합니다. 각 슬롯은 `/api/viewer/source`가 반환한 카메라
ID 중 하나를 선택합니다. 선택 목록은 최대 4개이며 장비 전체에 적용됩니다.

`1×1`은 기존 `{"camera_id":"..."}` 요청과 호환됩니다. 다중 레이아웃은
`{"camera_ids":["camera_a","camera_b"]}` 요청과 WebSocket
`viewer_frame` 다중 payload 지원이 필요합니다. 각 stream의 `name`은 카메라
ID이며 뒤따르는 JPEG binary frame은 `payload_index` 순서로 매칭됩니다. 선택을
바꾸더라도 수신 중인 묶음의 binary payload는 끝까지 소비한 뒤 현재 선택에
없는 영상을 버립니다. 카메라별 `frame_sequence`가 증가할 때만 영상 수신 시각을
갱신하므로 다른 카메라 때문에 같은 JPEG가 재전송돼도 정지 영상을 정상으로
표시하지 않습니다.

미리보기는 카메라의 보정 ON/OFF 설정이 적용된 영상이며 Capture 결과와 연결하지 않습니다. Capture 결과는
cycle ID로 별도 폴링하여 뷰어 상단 결과 행에 표시합니다.

### 날짜별 저장 결과 조회

`검사 결과` 화면은 런타임의 최근 결과 목록 대신 디스크의 저장 이력을 사용합니다.
`output_dir/{bolt_stud,nut,all}/YYYY-MM-DD/<cycle_id>/result.json`이 게시된 완료·취소 기록을 조회하므로,
장비 재시작이나 메모리 이력 제한과 관계없이 파일이 보존된 결과를 볼 수 있습니다.
날짜는 장비의 현지 접수일 폴더를 그대로 사용하고, `archive/`·기준 이미지·임시 촬영 폴더는 제외합니다.

| 메서드·경로 | 응답·용도 |
| --- | --- |
| `GET /api/capture/archive/dates` | 날짜 내림차순 `dates: [{date, count}]`와 `storage` |
| `GET /api/capture/archive?date=YYYY-MM-DD&limit=100&cursor=...` | 해당 날짜의 `results`, `date`, `next_cursor` |
| `GET /api/capture/archive/<분류>/<날짜>/<cycle_id>/image?inspection_id=<id>&kind=raw\|overlay` | 선택한 저장 결과의 PNG |

`storage`는 저장장치의 `path`, `total_bytes`, `available_bytes`, `used_bytes`, `used_percent`와
검사 데이터의 `capture_bytes`(결과 JSON+PNG 합계), `capture_count`(PNG 개수), `result_count`(검사 건수)를 반환합니다.
장치 사용률은 전체 파일시스템 기준이고, 검사 데이터 합계는 위 저장 이력만 포함합니다.
각 결과에는 해당 사이클의 JSON+PNG 용량인 `size_bytes`가 추가됩니다.

목록은 접수 시각·cycle ID 내림차순이며 `limit`은 1~100, 기본 100입니다.
`next_cursor`는 불투명한 문자열이고 `null`이면 마지막 페이지입니다. 다음 요청에 그대로 전달합니다.
잘못된 날짜·커서는 400, 비활성화된 저장은 409, 없는 저장 폴더·삭제된 이미지는 404,
손상된 결과·안전하게 읽을 수 없는 파일은 오류로 반환합니다. 심볼릭 링크는 따라가지 않습니다.
이미지는 카메라를 다시 촬영하지 않고 `storage_path`와 `inspection_id`·`kind`로 명시한 저장 파일만 읽습니다.

Studio는 최초 진입·날짜 선택·새로고침·최신 결과·더 보기에서 조회합니다. 매초 저장 폴더를 스캔하지 않습니다.
삭제된 기록을 클라이언트에 누적 보관하지 않으며 새로고침 때 서버 목록으로 교체합니다.
구버전 서버의 API 미지원은 오류로 표시하고 최근 결과 API로 자동 전환하지 않습니다.
뷰어의 진행 중 촬영 폴링은 기존 `/api/capture/results/<cycle_id>`를 계속 사용합니다.

저장 이력 조회 예시:

```bash
curl --fail http://127.0.0.1:8090/api/capture/archive/dates
curl --fail --get http://127.0.0.1:8090/api/capture/archive \
  --data-urlencode 'date=2026-09-10' --data-urlencode 'limit=100'
```


`검사 결과`는 Capture의 저장 이미지 화면과 같은 용량 카드·날짜 선택·결과 목록을 사용합니다.
각 날짜의 건수와 사이클별 용량을 표시하고, `최신 결과`로 최신 날짜의 첫 결과를 엽니다.
부위 버튼과 `검출 결과` / `원본`으로 저장된 PNG를 비교하고 `Ctrl + 휠`·+/− 확대와 드래그 이동을 지원합니다.
판정 이유·점검 항목·형상 측정값은 이미지 아래에서 확인하고 전체 ID·JSON은 상세에서 펼칩니다.
모바일에서는 용량·날짜·목록을 위에, 이미지를 아래에 배치합니다. 다른 날짜·장비로 전환하면 이전 응답을 버립니다.
이 기능을 사용하려면 Studio와 Inspect 서버를 함께 업데이트해야 합니다.
Inspect는 빌드 서버에서 빌드·검증한 `install/arm64/release/` 폴더를 실행 장비로 복사해서 적용합니다.
실행 장비에서는 Inspect 소스나 개발 Docker 환경을 빌드하지 않습니다. 기존 설정과 저장된 결과는 보존합니다.

예시 관리 옵션이 설치된 장비는 Viewer의 방패 아이콘에서 전달받은 관리
토큰을 등록합니다. Studio는 인증된 `GET /api/reference/status` 기능 플래그를
확인합니다. 상태 API의 404나 비활성 기능 플래그만 미지원으로 처리하고, 인증
실패나 일시적인 연결 실패는 관리 화면을 유지한 채 오류로 표시합니다. 같은 연결
설정으로 다시 연결해도 기능을 다시 조회합니다. 진행 중인 촬영·모델 빌드·적용
상태와 요청 ID는 다른 탭으로 이동해도 유지하고 폴링을 계속합니다. 모델 빌드와 적용은 검사를 잠시
중단하므로 각각 별도 확인을 요구하며, 기술 검증 통과를 생산 품질 승인으로
표시하지 않습니다. HTTP 자체에는 TLS가 없으므로 원격 관리에는 SSH 터널이나
TLS 프록시를 사용합니다.

모델과 리비전은 별도 ID를 사용해 같은 리비전의 여러 빌드를 구분합니다.
기준 이미지에서는 `모델 a0736e17`, `개정본 d446ad82`처럼 ID 앞 8자리만 표시합니다.
모델 목록·상세의 `Source`와 활성 모델 표시에서 원본 리비전을 확인하고,
`Build source`에서 빌드 대상 리비전을 확인합니다. 전체 ID는 모델 상세의
`Full identifiers`를 펼쳐 선택·복사할 수 있습니다. API와 저장 데이터는 전체 ID를 사용합니다.

Models는 빌드 상태, 기술 검증 통과 여부, 원본 리비전과 모델 적용·복구를 표시합니다.
이미지 검증 영역은 제공하지 않습니다. 실제 검사 이미지와 판정은 모델 적용 후 새로 촬영하여
`검사 결과`에서 확인합니다. 기술 검증 통과는 생산 품질 승인을 의미하지 않습니다.

모바일 `기준 이미지` 도구 모음은 상태와 작업 전환 버튼을 여러 줄로 배치해서
390px 너비에서도 가로 스크롤이나 오버플로 없이 동작합니다.

## 연결 설정

Viewer의 URL 설정에서 아래 값을 지정합니다.

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

`kind`는 `hss`, `pick`, `capture`, `inspection` 중 하나여야 합니다.
Inspection station은 `runtime_mode: "station"`을 함께 반환합니다. HSS 응답에
`person_roi_alert_disabled` bool이 있으면 `true`일 때 Person ROI 침범 감지
알림이 꺼진 상태로 보고 Viewer에 반투명 blink 경고를 띄웁니다.

## Capture API

아래 표는 별도 CatchEye Capture 앱의 API입니다. Inspect 촬영 경로는 위 스테이션 표를 따릅니다.

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

## 언어와 글꼴

UI 기본 언어는 한국어입니다. 메뉴·버튼·도움말·상태·앱 오류 안내와 Flutter 기본 대화상자 문구에 적용합니다.
앱 안내·오류·확인 메시지와 프로젝트 문서는 경어체를 사용합니다. 설명은 `~습니다`, 요청은 `~해 주세요`, 확인 질문은 `~하시겠습니까?`로 작성합니다. 메뉴·버튼명과 짧은 상태 표시는 명사형을 유지합니다.
`Bolt Head`, `Stud`, `Nut`, `Nut Hole`, `Plain Hole` 등 부품명과 제품명은 영어로 유지합니다.
API 경로·JSON 키·카메라 및 모델 ID·서버가 전달한 원본 진단 정보는 번역하지 않습니다.

- `assets/fonts/NotoSansCJKkr-Regular.otf` / `NotoSansCJKkr-Bold.otf`: Noto Sans CJK KR 2.004, 일반 400 / 굵게 700
- 앱 글꼴 이름: `NotoSansKR`. 기본 테마와 이미지 위 표시 글씨에 사용합니다.
- 두 글꼴 모두 한글 완성형 11,172자를 포함합니다. 두 글꼴 파일의 합계는 약 32 MiB입니다. 시스템 한글 폰트 설치나 실행 중 다운로드가 필요 없습니다.
- 출처: [Noto CJK](https://github.com/notofonts/noto-cjk). 원본 TTC의 한국어 글꼴을 개별 OTF로 추출했으며 글리프를 축소하지 않았습니다.
- SIL Open Font License 1.1 고지를 `assets/fonts/LICENSE.txt`에 포함하고 Flutter 라이선스 목록에도 등록합니다.
- 기본 위젯 번역에는 Flutter SDK의 `flutter_localizations`를 사용합니다. `flutter pub get` 후 기존 빌드 명령을 실행하면 글꼴과 라이선스가 함께 패키징됩니다.

## 화면 가독성

- 공통 테마: `lib/theme/studio_theme.dart`. 한글 본문은 14–15px, 설명은 12px, 제목은 16–20px을 사용합니다.
- 본문·버튼은 일반 굵기, 제목·선택 메뉴는 굵게 표시합니다. 자간은 0, 본문 줄높이는 1.5입니다.
- 검사 관리의 메뉴는 밑줄 탭, 제품 선택은 선택 버튼, 서버 갱신 상태는 헤더로 구분합니다.
- 레시피는 제품 선택 → 제품 정보 → 촬영 포인트 순서로 표시합니다. 넓은 화면에서는 포인트 정보와 조작 버튼을 한 줄에 배치하고, 작은 화면에서는 줄을 나눕니다.
- PLC 진단은 연결 상태, 송수신 신호, 통신 기록을 구분합니다. 상세 동작 안내는 펼쳐서 확인할 수 있고 오류·조작 제한은 계속 표시합니다.

## 디렉터리 구조

```text
.
├── lib/
│   ├── theme/                # 공통 색상·한글 타이포그래피·컨트롤 스타일
│   ├── controllers/          # 촬영 조회·스테이션·모델 작업 상태를 관리합니다.
│   ├── models/
│   ├── providers/
│   ├── screens/
│   ├── services/
│   └── widgets/
├── assets/
│   ├── app_icon.ico
│   ├── app_icon.png
│   └── fonts/                # Noto Sans CJK KR 일반·굵게 및 라이선스
├── android/
│   ├── app/src/main/AndroidManifest.xml
│   └── gradle.properties
├── launcher_icons_android.yaml
├── launcher_icons_ios.yaml
├── pubspec.yaml
└── README.md
```

### 비동기 상태와 통신 관리

`CaptureBrowserController`는 날짜·이미지 선택, `StationController`는 카메라 선택·촬영 결과 조회, `ModelJobsController`는 모델 빌드·적용 작업을 담당합니다. 장비 주소나 API 기본 경로가 바뀌면 이전 요청의 응답을 화면에 반영하지 않습니다. 모델 작업을 재개할 때는 기존 작업 ID의 상태만 조회합니다.

원격 API는 `ApiHttpClient`를 통해 요청을 전송합니다. 기본 제한 시간은 연결부터 응답 본문 수신까지 10초이며, 실패한 명령을 자동 재전송하지 않습니다. 화면이나 서비스 종료 시 HTTP 클라이언트를 닫습니다. 생산 상태와 PLC 응답의 필수 필드가 없거나 형식이 잘못되면 오류를 표시하고 제어를 차단합니다.

`WebSocketFrameDecoder`는 네이티브 플레이어와 독립적으로 프레임을 조립하고 카메라 식별·데이터 크기를 검사합니다. 잘못된 묶음의 남은 데이터를 일반 카메라 이미지로 해석하지 않습니다. 연결 해제 후 늦게 완료된 WebSocket 연결은 닫습니다. RTSP를 사용할 때만 네이티브 플레이어를 생성합니다.

### 영상 확대·축소와 편집

- Viewer의 JPEG/RTSP 영상, 분할 화면과 Inspection 카메라 타일, 모니터, 카메라 설정, 카메라 위치, 기준 이미지, ROI Editor에서 확대·축소할 수 있습니다.
- `Ctrl`을 누른 상태에서 마우스 휠·트랙패드 스크롤로 포인터 위치를 중심으로 확대·축소합니다. `Ctrl` 없이 스크롤하면 영상 배율은 바뀌지 않습니다. 오른쪽 아래 `−` / `+` 버튼은 키 입력 없이 사용할 수 있습니다. 배율 버튼을 누르면 화면 맞춤으로 돌아갑니다. 화면 맞춤 기준 1~16배입니다.
- 일반 영상은 드래그로 이동하고 터치에서는 두 손가락으로 확대·축소합니다. 실시간 프레임이 바뀌어도 배율과 위치를 유지합니다.
- References와 ROI Editor는 기본이 편집 모드입니다. 확대 후 드래그하면 박스를 그리거나 ROI 꼭짓점을 이동합니다. 손바닥 버튼으로 이동 모드를 켜면 드래그로 화면을 이동하고 두 손가락으로 확대·축소할 수 있습니다. 손바닥 버튼을 다시 누르면 편집으로 돌아갑니다.
- 영상과 박스·ROI를 함께 확대하며 저장 좌표는 원본 이미지 픽셀 기준입니다. References에서 다른 이미지를 열면 화면 맞춤으로 초기화합니다.
- Images의 저장 이미지와 3D 포인트클라우드도 휠 확대·축소에는 `Ctrl`이 필요합니다. 각 화면의 전용 버튼·터치 조작과 배율 범위는 유지합니다.

### ROI 실시간 편집

Viewer에 설정한 WebSocket 스트림을 ROI 편집 배경으로 계속 표시합니다. Viewer와 ROI 편집 사이에서는 연결을 유지하며, ROI Editor에 직접 들어가도 자동 연결합니다. 카메라 프레임 해상도에 맞춰 ROI 좌표와 화면 비율을 동기화합니다. `영상: 실시간`가 표시되면 영상 위의 꼭짓점을 드래그해서 편집하고 업로드 버튼으로 장비에 저장합니다. 연결 실패는 Stream 상태에 표시하며, 정지 이미지 캡처는 사용하지 않습니다. ROI 배경 영상은 `ws://` 또는 `wss://` 연결이 필요합니다.

HSS는 `stream_name: camera`, `payload_encoding: jpeg`로 영상을 전송합니다. Studio의 뷰어, 모니터, ROI Editor는 이 카메라 영상을 표시하며, ROI 배경도 실시간으로 갱신합니다.

### 카메라별 왜곡 보정 토글

Inspection Station Viewer의 각 카메라 선택란 아래에 **왜곡 보정** 스위치가 있습니다.
`1×1`, `1×2`, `2×2` 모두 선택한 카메라별로 표시하고, 빈 슬롯에는 표시하지 않습니다.

- 상태 조회: `GET /api/cameras/<camera_id>/undistortion`
- 변경: `POST /api/cameras/<camera_id>/undistortion`, 본문 `{"enabled":true}` 또는 `{"enabled":false}`
- 이 설정은 서버의 해당 카메라 송출·검출·검사 이미지 저장·새 기준 촬영에 함께 적용됩니다.
- 검사 진행·대기, 연결 끊김, 준비 안 됨, 요청 처리 중에는 조작을 제한합니다. 보정 파일이 없으면 ON으로 바꿀 수 없습니다.
- 서버의 확인 응답을 받은 뒤 스위치를 변경합니다. 실패·시간 초과 시 오류를 표시하고 다시 조회 버튼으로 실제 상태를 확인합니다. POST는 자동 재전송하지 않습니다.
- 다른 클라이언트의 변경은 기존 Station 상태 폴링의 `cameras.<id>.undistortion_enabled`로 반영합니다.
- 설정은 서버 메모리에만 유지되고 서버 재시작 시 YAML 기본값으로 돌아갑니다. Studio 설정에는 저장하지 않습니다.

위 API를 지원하는 Inspect 서버가 필요합니다. 구버전 서버의 404도 오류로 표시하며 임의의 보정 상태를 가정하지 않습니다.
기존 저장 이미지·기준 이미지·ROI·모델은 자동 변환되지 않습니다. 보정 모드에 맞는 기준과 ROI를 사용해야 합니다.
