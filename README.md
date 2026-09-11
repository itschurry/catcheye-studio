# CatchEye Studio

## Inspect 제품 레시피와 PLC 진단

Inspect 뷰어의 **제품 레시피 · 생산 검사 · PLC 진단** 버튼에서 다음 기능을 사용해.

- 제품 5종의 이름·촬영 순서·검사 항목·기대 개수 편집
- 포인트 추가·복제·삭제·위/아래 이동, 카메라 실시간 확인
- 미정 값은 초안 저장, 필수 기준 검증 후 운영 적용
- 제품 검사 시작·순차 촬영·결과 수신 확인·종료와 회차별 이미지·판정 사유 조회
- PLC 연결·실제 송수신 워드·요청 접수/거부·결과 송신·PLC 수신 확인 진단

레시피는 연결된 Inspect의 `state/production`에 저장돼. 진행 중인 제품의 레시피는 고정돼.
PLC 제어 회차를 Studio에서 촬영·종료하지 않고, 오류 회차의 명시적 중단만 지원해.
상태 조회 실패 시 제어 버튼을 막고 응답이 불확실한 명령을 자동 반복하지 않아.

Inspect의 `/api/production/*` v1과 독립 촬영 `capture_api_version: 2`가 필요해.
fastener의 기존 두 그룹 버튼은 볼트 머리·스터드·너트·너트 홀 네 개별 버튼으로 바뀌었어.
구버전 그룹 경로로 전환하지 않아. 서버와 Studio를 함께 업데이트해야 해.

새 파일은 `lib/screens/production_screen.dart`, `lib/services/remote_production_api_service.dart`야.
화면 테스트와 API 테스트는 `test/production_screen_test.dart`, `test/production_api_test.dart`에 있어.

```bash
flutter analyze --no-pub
flutter test --no-pub
```

이번 작업에서는 앱 빌드와 배포를 수행하지 않아. Inspect의 C++ Docker 빌드는 서버에서 수행해.
현장 PLC의 IP·포트·워드 길이·신호 위치는 별도 확정이 필요하며, Wi-Fi 자체가 PLC 프로토콜은 아니야.
Inspect 저장소의 `docs/PRODUCTION_RECIPES.md`가 TCP 신호 규약과 서버 검증 절차의 기준이야.


CatchEye 장비의 영상 스트림을 확인하고 원격 설정을 조정하는 Flutter 데스크톱 앱.

현재 버전: `v1.4.0`

Studio는 연결 시 `GET /api/device-info`를 호출해서 HSS/Pick/Capture/Inspection을 구분하고, 대상에 맞는 화면만 보여준다.
Inspect의 운영 통합 프로파일은 `fastener`이고 캡처 그룹은 `bolt_stud`와 `nut`이야. Studio는 `/api/capture/status`의 `set_id`로 촬영 버튼을 결정해. 이전 그룹·개별 검사 선택 드롭다운과 구버전 API 호환 처리는 없어.
HSS 연결에서 `person_roi_alert_disabled`가 `true`면 뷰어 툴바와 영상 영역 위에 깜빡이는 `ROI 경고 꺼짐` 경고를 표시한다.
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

Visual Studio Installer에서 C++ 데스크톱 빌드 도구와 설치된 MSVC 버전에 맞는 C++ ATL(x86 및 x64) 구성 요소를 설치한다. `flutter_secure_storage_windows` 빌드에 ATL이 필요하며, 누락되면 `atlstr.h`를 찾을 수 없다는 오류가 발생한다.

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
| 뷰어 | HSS / Pick / Capture / Inspection | RTSP 또는 WebSocket 영상 표시, HSS/Capture 녹화, Capture/Inspection 수동 캡처 |
| 저장 이미지 | Capture | 저장장치 용량/사용률, Capture JPEG 합계, 저장된 JPEG 날짜/목록 조회, 큰 이미지 preview, 확대/축소 |
| 모니터 | HSS / Capture | 여러 카메라 stream 동시 보기, 영상 더블클릭으로 해당 뷰어 이동 |
| ROI 편집 | HSS / Pick | Person 또는 Pallet ROI 편집 |
| 카메라 설정 | HSS / Capture | 카메라 runtime property 조절 |
| 카메라 위치 | Pick | 카메라 intrinsic과 로봇 base 기준 extrinsic 위치 관계 조회 |
| 검사 결과 | Inspection | 날짜별 저장 결과·용량, 검사 이미지, 검사별 판정·점검 안내, 측정값과 원본 JSON 조회 |
| 기준 이미지 | Inspection | 원본 예시 촬영·박스 편집·리비전 저장, 모델 빌드·검증·명시적 적용·이전 모델 복구 |

Pick 연결에서는 `뷰어`, `ROI 편집`, `카메라 위치`만 보여준다.
Capture 연결에서는 데스크톱에서 `뷰어`, `저장 이미지`, `모니터`, `카메라 설정`만 보여주고, 폰에서는 `뷰어`, `저장 이미지`, `모니터`만 보여준다. Capture 뷰어에서는 `촬영` 버튼으로 `/api/capture/request`를 호출하고, `녹화` 버튼으로 `/api/recording/*`를 호출한다. 저장 이미지 화면은 `/api/captures/*`로 저장된 JPEG와 `capture_dir`가 올라간 저장장치 용량을 조회한다.

## 모니터에서 뷰어 열기

- 카메라의 영상 영역을 더블클릭하면 Viewer로 이동하고 해당 스트림에 자동 연결한다. 모바일에서는 두 번 탭한다.
- 연결/해제 및 삭제 버튼은 기존 동작을 유지한다. Monitor를 나가면 모니터 스트림 연결은 해제되고, 다시 들어오면 저장된 카메라 목록에 재연결한다.
- 다른 호스트의 카메라를 열면 API Base URL의 호스트도 해당 카메라로 변경한다. 기존 API 프로토콜, 포트, API Base Path는 유지한다. 예: `ws://192.168.0.125:8080` → `http://192.168.0.125:8090`.
- 현재 Viewer와 같은 호스트의 카메라는 기존 API Base URL을 그대로 사용한다. 카메라마다 API 포트가 다르거나 별도 API 서버를 사용하면 Viewer의 `연결 주소 변경`에서 직접 지정한다.
- 기존 연결 절차대로 `/api/device-info`와 녹화 상태를 확인한 뒤 연결한다. API 조회 실패 시 오류를 표시하며 다른 카메라로 대신 연결하지 않는다.

## Pick 뷰어 스트림

Pick Viewer는 WebSocket `viewer_frame` multi-stream을 받으면 우측 `영상 목록` 패널에 RGB와 Depth를 나눠 보여준다.

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

## Inspection Station 뷰어

Inspect는 `--station`으로 실행해. YAML의 `set_id`에 따라 아래 촬영 버튼을 보여줘. 데스크톱·모바일 모두 스테이션 패널의 대상별 버튼으로 촬영하고, 상단 툴바의 일반 `촬영` 버튼은 표시하지 않아.

| 실행 프로파일 | 촬영 버튼 | POST 경로 | 검사 대상 |
| --- | --- | --- | --- |
| `fastener` | `Stud + Bolt Head` | `/api/capture/bolt-stud` | 스터드 `.101` + 볼트 머리 `.102` |
| `fastener` | `Nut + Nut Hole` | `/api/capture/nut` | 너트 `.103` + 너트 홀 `.104` |
| `fastener` | `전체 카메라 (4)` | `/api/capture/all` | 설정된 네 카메라 |
| `bolt_stud` | `전체 카메라 (2)`만 표시 | `/api/capture/all` | 설정된 스터드·볼트 머리 |
| `nut` | `전체 카메라 (2)`만 표시 | `/api/capture/all` | 설정된 너트·너트 홀 |

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

미리보기는 카메라의 보정 ON/OFF 설정이 적용된 영상이며 Capture 결과와 연결하지 않는다. Capture 결과는
cycle ID로 별도 폴링하여 뷰어 상단 결과 행에 표시한다.

### 날짜별 저장 결과 조회

`검사 결과` 화면은 런타임의 최근 결과 목록 대신 디스크의 저장 이력을 사용해.
`output_dir/{bolt_stud,nut,all}/YYYY-MM-DD/<cycle_id>/result.json`이 게시된 완료·취소 기록을 조회하므로,
장비 재시작이나 메모리 이력 제한과 관계없이 파일이 보존된 결과를 볼 수 있어.
날짜는 장비의 현지 접수일 폴더를 그대로 사용하고, `archive/`·기준 이미지·임시 촬영 폴더는 제외해.

| 메서드·경로 | 응답·용도 |
| --- | --- |
| `GET /api/capture/archive/dates` | 날짜 내림차순 `dates: [{date, count}]`와 `storage` |
| `GET /api/capture/archive?date=YYYY-MM-DD&limit=100&cursor=...` | 해당 날짜의 `results`, `date`, `next_cursor` |
| `GET /api/capture/archive/<분류>/<날짜>/<cycle_id>/image?inspection_id=<id>&kind=raw\|overlay` | 선택한 저장 결과의 PNG |

`storage`는 저장장치의 `path`, `total_bytes`, `available_bytes`, `used_bytes`, `used_percent`와
검사 데이터의 `capture_bytes`(결과 JSON+PNG 합계), `capture_count`(PNG 개수), `result_count`(검사 건수)를 반환해.
장치 사용률은 전체 파일시스템 기준이고, 검사 데이터 합계는 위 저장 이력만 포함해.
각 결과에는 해당 사이클의 JSON+PNG 용량인 `size_bytes`가 추가돼.

목록은 접수 시각·cycle ID 내림차순이며 `limit`은 1~100, 기본 100이야.
`next_cursor`는 불투명한 문자열이고 `null`이면 마지막 페이지야. 다음 요청에 그대로 전달해.
잘못된 날짜·커서는 400, 비활성화된 저장은 409, 없는 저장 폴더·삭제된 이미지는 404,
손상된 결과·안전하게 읽을 수 없는 파일은 오류로 반환해. 심볼릭 링크는 따라가지 않아.
이미지는 카메라를 다시 촬영하지 않고 `storage_path`와 `inspection_id`·`kind`로 명시한 저장 파일만 읽어.

Studio는 최초 진입·날짜 선택·새로고침·최신 결과·더 보기에서 조회해. 매초 저장 폴더를 스캔하지 않아.
삭제된 기록을 클라이언트에 누적 보관하지 않으며 새로고침 때 서버 목록으로 교체해.
구버전 서버의 API 미지원은 오류로 표시하고 최근 결과 API로 자동 전환하지 않아.
뷰어의 진행 중 촬영 폴링은 기존 `/api/capture/results/<cycle_id>`를 계속 사용해.

저장 이력 조회 예시:

```bash
curl --fail http://127.0.0.1:8090/api/capture/archive/dates
curl --fail --get http://127.0.0.1:8090/api/capture/archive \
  --data-urlencode 'date=2026-09-10' --data-urlencode 'limit=100'
```


`검사 결과`는 Capture의 저장 이미지 화면과 같은 용량 카드·날짜 선택·결과 목록을 사용해.
각 날짜의 건수와 사이클별 용량을 표시하고, `최신 결과`로 최신 날짜의 첫 결과를 열어.
부위 버튼과 `검출 결과` / `원본`으로 저장된 PNG를 비교하고 휠·+/− 확대와 드래그 이동을 지원해.
판정 이유·점검 항목·형상 측정값은 이미지 아래에서 확인하고 전체 ID·JSON은 상세에서 펼쳐.
모바일에서는 용량·날짜·목록을 위에, 이미지를 아래에 배치해. 다른 날짜·장비로 전환하면 이전 응답을 버려.
이 기능을 사용하려면 Studio와 Inspect 서버를 함께 업데이트해야 해.
Inspect는 빌드 서버에서 빌드·검증한 `install/arm64/release/` 폴더를 실행 장비로 복사해서 적용해.
실행 장비에서는 Inspect 소스나 개발 Docker 환경을 빌드하지 않아. 기존 설정과 저장된 결과는 보존해.

예시 관리 옵션이 설치된 장비는 Viewer의 방패 아이콘에서 전달받은 관리
토큰을 등록한다. Studio는 인증된 `GET /api/reference/status` 기능 플래그를
확인한다. 상태 API의 404나 비활성 기능 플래그만 미지원으로 처리하고, 인증
실패나 일시적인 연결 실패는 관리 화면을 유지한 채 오류로 표시한다. 같은 연결
설정으로 다시 연결해도 기능을 다시 조회한다. 진행 중인 촬영·모델 빌드·적용
상태와 요청 ID는 다른 탭으로 이동해도 유지하고 폴링을 계속한다. 모델 빌드와 적용은 검사를 잠시
중단하므로 각각 별도 확인을 요구하며, 기술 검증 통과를 생산 품질 승인으로
표시하지 않는다. HTTP 자체에는 TLS가 없으므로 원격 관리에는 SSH 터널이나
TLS 프록시를 사용한다.

모델과 리비전은 별도 ID를 사용해 같은 리비전의 여러 빌드를 구분한다.
기준 이미지에서는 `모델 a0736e17`, `개정본 d446ad82`처럼 ID 앞 8자리만 표시한다.
모델 목록·상세의 `Source`와 활성 모델 표시에서 원본 리비전을 확인하고,
`Build source`에서 빌드 대상 리비전을 확인한다. 전체 ID는 모델 상세의
`Full identifiers`를 펼쳐 선택·복사할 수 있다. API와 저장 데이터는 전체 ID를 사용한다.

Models는 빌드 상태, 기술 검증 통과 여부, 원본 리비전과 모델 적용·복구를 표시한다.
이미지 검증 영역은 제공하지 않는다. 실제 검사 이미지와 판정은 모델 적용 후 새로 촬영해
`검사 결과`에서 확인한다. 기술 검증 통과는 생산 품질 승인을 의미하지 않는다.

모바일 `기준 이미지` 도구 모음은 상태와 작업 전환 버튼을 여러 줄로 배치해서
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

## 언어와 글꼴

UI 기본 언어는 한국어야. 메뉴·버튼·도움말·상태·앱 오류 안내와 Flutter 기본 대화상자 문구에 적용해.
`Bolt Head`, `Stud`, `Nut`, `Nut Hole`, `Plain Hole` 등 부품명과 제품명은 영어로 유지해.
API 경로·JSON 키·카메라 및 모델 ID·서버가 전달한 원본 진단 정보는 번역하지 않아.

- `assets/fonts/NotoSansCJKkr-Regular.otf` / `NotoSansCJKkr-Bold.otf`: Noto Sans CJK KR 2.004, 일반 400 / 굵게 700
- 앱 글꼴 이름: `NotoSansKR`. 기본 테마와 이미지 위 표시 글씨에 사용해.
- 두 글꼴 모두 한글 완성형 11,172자를 포함해. 두 글꼴 파일의 합계는 약 32 MiB야. 시스템 한글 폰트 설치나 실행 중 다운로드가 필요 없어.
- 출처: [Noto CJK](https://github.com/notofonts/noto-cjk). 원본 TTC의 한국어 글꼴을 개별 OTF로 추출했으며 글리프를 축소하지 않았어.
- SIL Open Font License 1.1 고지를 `assets/fonts/LICENSE.txt`에 포함하고 Flutter 라이선스 목록에도 등록해.
- 기본 위젯 번역에는 Flutter SDK의 `flutter_localizations`를 사용해. `flutter pub get` 후 기존 빌드 명령을 실행하면 글꼴과 라이선스가 함께 패키징돼.

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

### 영상 확대·축소와 편집

- Viewer의 JPEG/RTSP 영상, 분할 화면과 Inspection 카메라 타일, 모니터, 카메라 설정, 카메라 위치, 기준 이미지, ROI Editor에서 확대·축소할 수 있어.
- 마우스 휠·트랙패드 스크롤로 포인터 위치를 중심으로 확대하고, 오른쪽 아래 `−` / `+` 버튼으로도 조절해. 배율 버튼을 누르면 화면 맞춤으로 돌아가. 화면 맞춤 기준 1~16배야.
- 일반 영상은 드래그로 이동하고 터치에서는 두 손가락으로 확대·축소해. 실시간 프레임이 바뀌어도 배율과 위치를 유지해.
- References와 ROI Editor는 기본이 편집 모드야. 확대 후 드래그하면 박스를 그리거나 ROI 꼭짓점을 이동해. 손바닥 버튼으로 이동 모드를 켜면 드래그로 화면을 이동하고 두 손가락으로 확대·축소할 수 있어. 손바닥 버튼을 다시 누르면 편집으로 돌아가.
- 영상과 박스·ROI를 함께 확대하며 저장 좌표는 원본 이미지 픽셀 기준이야. References에서 다른 이미지를 열면 화면 맞춤으로 초기화해.
- Images의 저장 이미지와 3D 포인트클라우드는 기존 전용 확대·축소 조작을 사용해.

### ROI 실시간 편집

Viewer에 설정한 WebSocket 스트림을 ROI 편집 배경으로 계속 표시한다. Viewer와 ROI 편집 사이에서는 연결을 유지하며, ROI Editor에 직접 들어가도 자동 연결한다. 카메라 프레임 해상도에 맞춰 ROI 좌표와 화면 비율을 동기화한다. `영상: 실시간`가 표시되면 영상 위의 꼭짓점을 드래그해서 편집하고 업로드 버튼으로 장비에 저장한다. 연결 실패는 Stream 상태에 표시하며, 정지 이미지 캡처는 사용하지 않는다. ROI 배경 영상은 `ws://` 또는 `wss://` 연결이 필요하다.

HSS는 `stream_name: camera`, `payload_encoding: jpeg`로 영상을 전송한다. Studio의 뷰어, 모니터, ROI Editor는 이 카메라 영상을 표시하며, ROI 배경도 실시간으로 갱신한다.

### 카메라별 왜곡 보정 토글

Inspection Station Viewer의 각 카메라 선택란 아래에 **왜곡 보정** 스위치가 있어.
`1×1`, `1×2`, `2×2` 모두 선택한 카메라별로 표시하고, 빈 슬롯에는 표시하지 않아.

- 상태 조회: `GET /api/cameras/<camera_id>/undistortion`
- 변경: `POST /api/cameras/<camera_id>/undistortion`, 본문 `{"enabled":true}` 또는 `{"enabled":false}`
- 이 설정은 서버의 해당 카메라 송출·검출·검사 이미지 저장·새 기준 촬영에 함께 적용돼.
- 검사 진행·대기, 연결 끊김, 준비 안 됨, 요청 처리 중에는 조작을 막아. 보정 파일이 없으면 ON으로 바꿀 수 없어.
- 서버의 확인 응답을 받은 뒤 스위치를 변경해. 실패·시간 초과 시 오류를 표시하고 다시 조회 버튼으로 실제 상태를 확인해. POST는 자동 재전송하지 않아.
- 다른 클라이언트의 변경은 기존 Station 상태 폴링의 `cameras.<id>.undistortion_enabled`로 반영해.
- 설정은 서버 메모리에만 유지되고 서버 재시작 시 YAML 기본값으로 돌아가. Studio 설정에는 저장하지 않아.

위 API를 지원하는 Inspect 서버가 필요해. 구버전 서버의 404도 오류로 표시하며 임의의 보정 상태를 가정하지 않아.
기존 저장 이미지·기준 이미지·ROI·모델은 자동 변환되지 않아. 보정 모드에 맞는 기준과 ROI를 사용해야 해.
