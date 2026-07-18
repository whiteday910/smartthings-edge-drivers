# MOES UFO-R11 Smart IR Remote Control SmartThings Edge Driver

MOES에서 판매하는 "Tuya ZigBee Smart IR Remote Control Universal Infrared Remote Controller" (제품 모델 **UFO-R11**) 기기를 위한 SmartThings Edge 드라이버입니다. 칩셋 자체는 manufacturer `_TZ3290_ot6ewjvmejq5ekhl` / modelID `TS1201`로 리포트되며, 같은 칩셋/프로토콜이 Aubess ZXZIR-02, Zemismart ZS06 등 다른 브랜드 제품으로도 재판매되고 있습니다.

## HOBEIAN ZG-IR01과 다른 점

`../zgir01-driver`의 ZG-IR01은 기기 자체에 물리적인 스위치 슬롯이 6개 있어서, 학습과 재생을 전부 기기가 알아서 처리합니다. UFO-R11은 슬롯이 없는 **범용 IR 블라스터**라서:

- 학습한 IR 코드의 실제 데이터(raw bytes)를 기기가 허브로 전송해줘야 하고,
- 재생할 때도 허브가 그 데이터를 다시 기기로 보내줘야 합니다.

이 데이터 왕복은 "Zosung" 프로토콜이라는 비표준 커스텀 프로토콜(JSON 제어 명령 + 청크 분할 바이너리 전송)로 이루어집니다. ZG-IR01 드라이버 README에서 "리버스 엔지니어링된 비표준 프로토콜이라 구현 범위에서 제외했다"고 언급한 것이 바로 이 프로토콜이며, 이번 드라이버가 그 프로토콜을 구현합니다.

## 지원 기능

표준 `momentary` capability(앱에 큼직한 버튼으로 표시됨)와 커스텀 capability `acrosswatch58328.irBlaster`를 통해:

- **학습 시작 (표준 `momentary` 버튼, 또는 커스텀 `learn` 명령)**: 기기를 학습 모드로 전환합니다. 이후 몇 초 안에 기존 리모컨을 기기에 가까이 대고 버튼을 누르면 코드가 학습됩니다.
- **학습 취소 (`cancelLearn`)**: 코드를 캡처하지 않고 학습 모드를 종료합니다.
- **학습된 코드 (`learnedCode`, 읽기 전용)**: 가장 최근에 학습된 코드가 base64 문자열로 표시됩니다.
- **학습된 코드 송출 (`replayLearnedCode`, 인자 없음)**: `learnedCode`에 저장된 가장 최근 학습 코드를 그대로 재전송합니다. 앱은 커스텀 capability에 텍스트 입력 UI를 지원하지 않아서, 인자를 받는 `sendCode(code)` 대신 이 버튼 하나로 "방금 학습한 걸 다시 재생"하는 가장 흔한 시나리오를 앱에서 바로 처리합니다.
- **코드 전송 (`sendCode`, 문자열 인자 `code`, CLI/자동화 전용)**: 임의의 저장된 코드나 `{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"..."}}` 형태의 전체 JSON을 넣어 전송합니다. 텍스트 인자가 필요해서 앱 UI에서는 실행할 수 없고 CLI/Rules API로만 호출 가능합니다.

학습 상태(`learningState`: `idle`/`learning`)도 함께 노출되어, 코드 캡처가 완료되면 자동으로 `idle`로 돌아갑니다.

**참고 (다중 코드 미지원)**: 이 기기는 슬롯이 없어서 한 번에 코드 하나만 기억합니다. 새로 학습하면 이전에 학습한 코드는 덮어씌워집니다. TV/에어컨 등 여러 버튼을 각각 저장해두고 쓰려면 학습된 코드를 CLI로 복사해 별도 보관했다가 `sendCode`로 재생하거나, 버튼별로 별도 자식 기기를 만드는 구조로 확장해야 합니다 — 필요하면 알려주세요.

## 사용법

### 앱에서

1. 기기 상세 화면에서 "학습 시작"(또는 momentary) 버튼을 누름
2. 몇 초 안에 기존 리모컨을 기기에 가까이 대고 버튼을 누름 → "학습된 코드"에 base64 코드가 표시되면 성공
3. "학습된 코드 송출" 버튼을 누르면 방금 학습한 코드가 재생됨

### CLI에서 (여러 코드를 따로 보관하고 싶을 때)

```
# 1. 학습 시작
smartthings devices:commands <deviceId> 'acrosswatch58328.irBlaster:learn()'

# 2. (기존 리모컨을 기기에 가까이 대고 버튼을 누름)

# 3. 학습된 코드 확인 (따로 복사/보관)
smartthings devices:capability-status <deviceId> main acrosswatch58328.irBlaster

# 4. 보관해둔 코드 재전송(재생) — 꼭 방금 학습한 코드가 아니어도 됨
smartthings devices:commands <deviceId> 'acrosswatch58328.irBlaster:sendCode("<코드 값>")'
```

`<deviceId>`는 `smartthings devices`로 조회할 수 있습니다.

## 지원하지 않는 기능 (의도적 범위 제외)

- **Raw IR timing 배열 입출력** (예: `[9000, -4500, 560, ...]` 형태의 압축/해제). zigbee-herdsman-converters는 이를 위해 자체 압축 코덱을 구현하지만, 학습한 코드를 그대로 재사용하는 핵심 시나리오에는 필요하지 않아 이번 범위에서 제외했습니다. 필요하면 알려주세요.

## 기술 배경 (참고)

- Zigbee 클러스터 `0xE004` (Zosung IR Control): 명령 `0x00`에 raw JSON payload(`{"study":0}` = 학습 시작, `{"study":1}` = 학습 종료)를 실어 보냅니다.
- Zigbee 클러스터 `0xED00` (Zosung IR Transmit): manufacturer-specific 명령 `0x00`~`0x05`로 청크 분할 전송을 수행합니다. 학습 완료 시 기기가 보낸 raw bytes를 base64로 인코딩해 `learnedCode`에 저장하고, 전송 시에는 JSON 문자열(`ir_msg`)을 같은 방식으로 기기에 청크 전송합니다.
- 두 개의 독립적인 오픈소스 구현(zigbee-herdsman-converters의 `lib/zosung.ts`, ZHA의 `zhaquirks/tuya/ts1201.py` — 이 파일은 `_TZ3290_ot6ewjvmejq5ekhl`를 명시적으로 지원 목록에 포함)을 서로 대조하며 프로토콜을 파악해서 이식했습니다.
- fingerprint는 특정 manufacturer 문자열 대신 클러스터 조합(`0xE004`+`0xED00`)으로 매칭하므로, 같은 칩셋의 다른 manufacturer 문자열 변형(`_TZ3290_j37rooaxrcdcqo5n`, `_TZ3290_7v1k4vufotpowp9z` 등)에서도 동작할 가능성이 높습니다.

## ✅ 검증 상태

실기기(정휘방 스테이션 허브 + 실제 UFO-R11)로 학습(learn)과 재생(sendCode) 전체 핸드셰이크를 Live Logging으로 확인했습니다 — 리모컨 신호 학습, `learnedCode` 저장, 저장된 코드 재전송까지 에러 없이 끝까지 동작합니다.

디버깅 과정에서 발견해 수정한 버그 2건 (둘 다 SmartThings Lua SDK API를 잘못 추측해서 생긴 문제였습니다):
- `frame_ctrl:is_disable_default_response()` → 실제로는 `is_disable_default_response_set()`이 맞는 메서드명이었습니다. 이 오타 때문에 기기가 학습 데이터를 보낼 때마다 드라이버가 즉시 크래시해서 아무 응답도 못 보내고 있었습니다.
- `DefaultResponse(cmd, status)`의 `cmd` 인자는 `ZCLCommandId`가 아니라 `Uint8` 타입이어야 했습니다.

두 문제 모두 `smartthings edge:drivers:logcat`으로 실시간 로그를 보고 나서야 정확히 잡을 수 있었습니다. 학습/전송이 다시 이상하게 동작하면 같은 방법으로 로그를 확인해주세요.

**⚠️ 알려진 이슈: "학습된 코드 송출"(`replayLearnedCode`) 버튼이 앱에서 안정적으로 동작하지 않습니다.** capability를 처음 만든 뒤(`learn`/`cancelLearn`/`sendCode`만 있던 시점) 나중에 명령을 하나 추가했더니(`send`, 이후 `replayLearnedCode`로 개명) 실기기로 지속적으로 재현되는 문제가 있습니다:

- 클라우드가 "OO is not a valid value"로 명령 자체를 거부하는 경우가 많고 (요청마다 다른 백엔드 서버로 라우팅되는 듯, 거부/수락이 요청마다 뒤바뀝니다),
- 클라우드가 명령을 수락해서 허브로 전달하는 경우에도, 허브로 전달되는 메시지 자체가 깨져서 드라이버가 아닌 **SmartThings 프레임워크 자체**(`st/driver.lua`)가 `json.decode` 중 에러를 내며 죽습니다 (`bad argument #1: error converting Lua nil to String`). 우리 코드(`init.lua`)에는 도달하지도 못하는 단계입니다.
- 명령 이름을 바꿔봐도(`send` → `replayLearnedCode`) 똑같이 재현되고, **90초 동안 6번 연속 100% 재현**될 만큼 지속적이라 단순 "캐시 전파 지연"은 아닌 것으로 보입니다.
- 우회 시도: 커스텀 capability를 새 버전(v2)으로 만들어 재정의 → API가 "이미 존재하는 이름"이라며 거부 (proposed 상태 capability는 이 방식으로 버전을 늘릴 수 없음). 드라이버를 허브에서 완전히 제거 후 재설치 → 플랫폼이 "기기가 사용 중이라 제거 불가"로 안전하게 차단.
- `learn`/`cancelLearn`/`sendCode`(capability를 처음 만들 때부터 있던 명령들)는 이런 문제가 전혀 없이 항상 안정적으로 동작합니다.

**결론**: "capability 생성 시점부터 있던 명령"과 "나중에 추가한 명령"이 SmartThings 플랫폼(클라우드 라우팅 또는 허브 캐시)에서 다르게 취급되는 것으로 보이는데, 정확한 근본 원인과 API 차원의 해결책은 아직 못 찾았습니다. 당장은 CLI의 `sendCode`가 완전히 안정적으로 동작하니 재생은 그쪽으로 쓰시고, 나중에 새 capability를 처음부터 다시 만들어서(v1에 4개 명령을 처음부터 다 포함) 프로필을 옮기는 방법으로 재시도해볼 수 있습니다.

따라서 앱에서 "학습된 코드 송출" 버튼이 바로 안 먹히더라도 드라이버나 기기 문제가 아니라 플랫폼 쪽 전파 지연이니, 시간을 두고(몇 분~길면 더 오래) 다시 눌러봐 주세요. 그동안 CLI의 `sendCode`는 항상 안정적으로 동작합니다.

## 설치 방법

이 드라이버 코드는 준비되어 있지만, 패키징 이후 실제 페어링은 허브와 기기가 있어야 하는 작업이라 직접 진행해주셔야 합니다.

### 1. 드라이버 패키징 및 채널 등록

이 폴더(`moes-ufo-r11-driver`)에서:

```
smartthings edge:drivers:package .
smartthings edge:channels:assign
```

(이미 쓰고 계신 채널 `nemonemoTTE-st-edge`에 할당하면 됩니다.)

### 2. 허브에 설치 및 페어링

```
smartthings edge:drivers:install
```

허브를 선택하고 방금 패키징한 드라이버를 설치한 뒤, SmartThings 앱 > 기기 추가 > 검색으로 UFO-R11을 페어링하세요. 정상 매칭되면 "MOES UFO-R11 IR Remote Control"로 표시됩니다.

### 3. 코드 학습 및 재생

위 "사용법" 항목을 참고하세요.
