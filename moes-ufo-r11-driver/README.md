# MOES UFO-R11 Smart IR Remote Control SmartThings Edge Driver

MOES에서 판매하는 "Tuya ZigBee Smart IR Remote Control Universal Infrared Remote Controller" (제품 모델 **UFO-R11**) 기기를 위한 SmartThings Edge 드라이버입니다. 칩셋 자체는 manufacturer `_TZ3290_ot6ewjvmejq5ekhl` / modelID `TS1201`로 리포트되며, 같은 칩셋/프로토콜이 Aubess ZXZIR-02, Zemismart ZS06 등 다른 브랜드 제품으로도 재판매되고 있습니다.

## HOBEIAN ZG-IR01과 다른 점

`../zgir01-driver`의 ZG-IR01은 기기 자체에 물리적인 스위치 슬롯이 6개 있어서, 학습과 재생을 전부 기기가 알아서 처리합니다. UFO-R11은 슬롯이 없는 **범용 IR 블라스터**라서:

- 학습한 IR 코드의 실제 데이터(raw bytes)를 기기가 허브로 전송해줘야 하고,
- 재생할 때도 허브가 그 데이터를 다시 기기로 보내줘야 합니다.

이 데이터 왕복은 "Zosung" 프로토콜이라는 비표준 커스텀 프로토콜(JSON 제어 명령 + 청크 분할 바이너리 전송)로 이루어집니다. ZG-IR01 드라이버 README에서 "리버스 엔지니어링된 비표준 프로토콜이라 구현 범위에서 제외했다"고 언급한 것이 바로 이 프로토콜이며, 이번 드라이버가 그 프로토콜을 구현합니다.

## 지원 기능 및 앱 화면 구성

커스텀 capability `acrosswatch58328.irBlasterV4` 하나로 동작하며, 아래 5가지 항목이 "0"~"9" 10개 컴포넌트 각각에 동일하게 반복됩니다 (자세한 다중 신호 구조는 아래 "여러 개의 신호 학습하기" 참고):

| 화면 표시 | 종류 | 설명 |
|---|---|---|
| 학습 상태 | 상태 텍스트 | `대기` / `학습 중` |
| 저장된 신호 | 상태 텍스트 | `없음` / `저장됨` — 재생 가능한 코드가 있는지 한눈에 확인 |
| 새 신호 학습 | 버튼 (`learn`) | 학습 모드로 전환. 이후 몇 초 안에 기존 리모컨을 기기에 가까이 대고 버튼을 누르면 신호가 저장됩니다 |
| 학습 취소 | 버튼 (`cancelLearn`) | 신호를 저장하지 않고 학습 모드 종료 |
| 저장된 신호 재생 | 버튼 (`replayLearnedCode`) | 가장 최근 학습한 신호를 그대로 재전송 |

기기 목록(대시보드) 카드에도 "저장된 신호" 상태가 바로 보여서, 상세 화면을 열지 않아도 재생 가능 여부를 알 수 있습니다.

원시 base64 코드 값은 앱 화면에는 더 이상 노출하지 않습니다 (일반 사용자에게는 의미 없는 긴 문자열이라 화면에서 뺐습니다). 코드를 CLI로 확인/백업하려면 `capability-status`로 `learnedCode` 속성을 조회하면 됩니다. CLI 전용 고급 명령 `sendCode(code)`(임의의 저장된 코드나 직접 만든 JSON을 전송)도 그대로 남아 있습니다 — 텍스트 인자가 필요해서 앱 UI에는 노출되지 않고 CLI/Rules API로만 호출 가능합니다.

## 여러 개의 신호 학습하기 (TV 리모컨처럼, 기기 하나 안에서)

물리 기기 자체는 슬롯이 없어서 한 번에 신호 하나만 기억할 수 있는 칩입니다. 하지만 실제로 코드를 "저장"하는 건 SmartThings 쪽(이 드라이버)이고, 재생할 때마다 그 저장된 데이터를 기기로 다시 보내는 방식이라서, **여러 개의 독립적인 신호를 SmartThings 쪽에서 각각 저장**해두는 게 가능합니다.

기기를 여러 개로 쪼개는 대신(자식 기기 방식은 시도해봤지만 원하신 방식이 아니었습니다), **SmartThings의 "컴포넌트" 기능**을 사용했습니다 — 기기 하나에 여러 컴포넌트를 두면, 앱이 기기 상세 화면 안에서 컴포넌트를 탭/구간 형태로 전환할 수 있게 보여줍니다. 이 드라이버는 메인 기기 화면 안에 **"0"부터 "9"까지 10개의 컴포넌트**를 두었고, 각 컴포넌트가 완전히 독립적인 학습 상태/저장된 신호/버튼 세트를 가집니다 (마치 TV 리모컨의 숫자 버튼처럼, 0번은 "TV 전원", 3번은 "에어컨 켜기" 하는 식으로 각각 학습시켜 쓸 수 있습니다).

- 화면 위쪽의 "0" ~ "9" 중 원하는 번호를 선택하면, 그 번호 전용 학습 상태 / 저장된 신호 / 새 신호 학습 / 학습 취소 / 저장된 신호 재생이 나타납니다.
- 한 번호에서 학습한 신호는 다른 번호에 전혀 영향을 주지 않습니다 — 실제로 "3"번에서 학습을 시작해도 "0"번의 저장된 신호는 그대로 유지되는 것을 확인했습니다.
- 번호 개수는 10개로 고정입니다(늘리거나 줄이는 설정 없음). 각 번호가 무슨 기능인지는 사용자가 기억하거나, 필요하면 자동화(오토메이션) 이름 등에 메모해두는 방식을 권장합니다.

**참고**: 이전 버전에서 자식 기기 방식으로 만들었을 때 생성된 "...1 2" ~ "...1 6" 자식 기기 5개는 이제 쓰이지 않습니다. 필요 없으면 SmartThings 앱에서 직접 삭제하세요.

## 사용법

### 앱에서

1. 기기 상세 화면 위쪽에서 원하는 번호("0" ~ "9")를 선택
2. "새 신호 학습" 버튼을 누름 (학습 상태가 "학습 중"으로 바뀜)
3. 몇 초 안에 기존 리모컨을 기기에 가까이 대고 버튼을 누름 → "저장된 신호"가 "저장됨"으로 바뀌면 성공
4. 같은 번호에서 "저장된 신호 재생" 버튼을 누르면 그 번호에 학습된 신호가 재생됨

### CLI에서 (여러 코드를 따로 보관하고 싶을 때)

명령 앞에 `<번호>:`를 붙이면 해당 컴포넌트를 지정할 수 있습니다 (`main`이 "0"번, 나머지는 `num1` ~ `num9`가 "1" ~ "9"번에 대응).

```
# 1. "3"번에서 학습 시작
smartthings devices:commands <deviceId> 'num3:acrosswatch58328.irBlasterV4:learn()'

# 2. (기존 리모컨을 기기에 가까이 대고 버튼을 누름)

# 3. "3"번에 학습된 코드 확인 (따로 복사/보관)
smartthings devices:capability-status <deviceId> num3 acrosswatch58328.irBlasterV4

# 4. 보관해둔 코드를 "3"번으로 재전송(재생) — 꼭 방금 학습한 코드가 아니어도 됨
smartthings devices:commands <deviceId> 'num3:acrosswatch58328.irBlasterV4:sendCode("<코드 값>")'
```

`<deviceId>`는 `smartthings devices`로 조회할 수 있습니다.

**참고 (Windows `cmd.exe`)**: `cmd.exe`(명령 프롬프트)는 작은따옴표를 문자열 구분자로 인식하지 않아서 위 형태의 명령이 깨질 수 있습니다. PowerShell을 쓰거나, 아래처럼 JSON 파일로 전달하세요:

```json
{
  "component": "num3",
  "capability": "acrosswatch58328.irBlasterV4",
  "command": "sendCode",
  "arguments": ["<코드 값>"]
}
```
```
smartthings devices:commands <deviceId> -i sendcode.json
```

## 자동화(루틴)에서 사용하기

다른 무선 버튼(예: IKEA STYRBAR, 스마트 스위치 등)을 누르면 이 기기의 학습된 신호가 재생되도록 하려면, SmartThings 앱의 "자동화" > "루틴 추가"에서:

1. "만약(if)" 조건에 원하는 버튼 기기를 추가 (예: "STYRBAR 버튼을 눌렀을 때")
2. "그런 다음(then)" 동작에서 이 IR 기기를 선택 → 상단에서 원하는 번호("0" ~ "9") 선택 → **"IR 블라스터"** 항목에서 "새 신호 학습" / "학습 취소" / "저장된 신호 재생" 중 원하는 동작 선택 (보통 "저장된 신호 재생"을 쓰게 됩니다)

각 번호(0~9)마다 독립적으로 루틴 액션이 노출되므로, 버튼 하나로 "3"번에 학습된 에어컨 신호를, 다른 버튼으로 "0"번에 학습된 TV 신호를 재생하는 식으로 구성할 수 있습니다.

**참고**: 처음에는 이 항목이 루틴 화면에 아예 안 보였습니다 — 커스텀 capability를 만들 때 "자동화에서 쓸 수 있는 동작" 목록(`automation.actions`)을 비워뒀기 때문이었습니다. 이후 이 목록을 채워 넣었는데, 클라우드에 실제로 반영되기까지 몇 분 정도 지연이 있었습니다 (앞선 `replayLearnedCode` 이슈와 비슷한 종류의 플랫폼 쪽 전파 지연). 루틴 화면에 "IR 블라스터" 항목이 안 보이면 몇 분 후 앱을 새로고침해서 다시 확인해보세요.

## 지원하지 않는 기능 (의도적 범위 제외)

- **Raw IR timing 배열 입출력** (예: `[9000, -4500, 560, ...]` 형태의 압축/해제). zigbee-herdsman-converters는 이를 위해 자체 압축 코덱을 구현하지만, 학습한 코드를 그대로 재사용하는 핵심 시나리오에는 필요하지 않아 이번 범위에서 제외했습니다. 필요하면 알려주세요.

## 기술 배경 (참고)

- Zigbee 클러스터 `0xE004` (Zosung IR Control): 명령 `0x00`에 raw JSON payload(`{"study":0}` = 학습 시작, `{"study":1}` = 학습 종료)를 실어 보냅니다.
- Zigbee 클러스터 `0xED00` (Zosung IR Transmit): manufacturer-specific 명령 `0x00`~`0x05`로 청크 분할 전송을 수행합니다. 학습 완료 시 기기가 보낸 raw bytes를 base64로 인코딩해 `learnedCode`에 저장하고, 전송 시에는 JSON 문자열(`ir_msg`)을 같은 방식으로 기기에 청크 전송합니다.
- 두 개의 독립적인 오픈소스 구현(zigbee-herdsman-converters의 `lib/zosung.ts`, ZHA의 `zhaquirks/tuya/ts1201.py` — 이 파일은 `_TZ3290_ot6ewjvmejq5ekhl`를 명시적으로 지원 목록에 포함)을 서로 대조하며 프로토콜을 파악해서 이식했습니다.
- fingerprint는 특정 manufacturer 문자열 대신 클러스터 조합(`0xE004`+`0xED00`)으로 매칭하므로, 같은 칩셋의 다른 manufacturer 문자열 변형(`_TZ3290_j37rooaxrcdcqo5n`, `_TZ3290_7v1k4vufotpowp9z` 등)에서도 동작할 가능성이 높습니다.

## ✅ 검증 상태

실기기(정휘방 스테이션 허브 + 실제 UFO-R11)로 `learn`/`cancelLearn`/`sendCode`/`replayLearnedCode` 4개 명령 전부와 전체 청크 전송 핸드셰이크를 Live Logging으로 확인했습니다 — 리모컨 신호 학습, `learnedCode` 저장, 저장된 코드 재전송(앱의 "학습된 코드 송출" 버튼 포함)까지 에러 없이 끝까지 동작합니다.

디버깅 과정에서 발견해 수정한 버그 2건 (둘 다 SmartThings Lua SDK API를 잘못 추측해서 생긴 문제였습니다):
- `frame_ctrl:is_disable_default_response()` → 실제로는 `is_disable_default_response_set()`이 맞는 메서드명이었습니다. 이 오타 때문에 기기가 학습 데이터를 보낼 때마다 드라이버가 즉시 크래시해서 아무 응답도 못 보내고 있었습니다.
- `DefaultResponse(cmd, status)`의 `cmd` 인자는 `ZCLCommandId`가 아니라 `Uint8` 타입이어야 했습니다.

두 문제 모두 `smartthings edge:drivers:logcat`으로 실시간 로그를 보고 나서야 정확히 잡을 수 있었습니다. 학습/전송이 다시 이상하게 동작하면 같은 방법으로 로그를 확인해주세요.

**해결된 이슈 (기록용): "학습된 코드 송출" 버튼이 한동안 크래시했던 원인.** 원래 커스텀 capability(`acrosswatch58328.irBlaster`)는 `learn`/`cancelLearn`/`sendCode` 세 명령만으로 처음 만들었고, 나중에 `replayLearnedCode`(처음엔 `send`라는 이름) 명령을 **기존 capability에 추가**했습니다. 그 이후로 이 명령만:

- 클라우드가 "OO is not a valid value"로 거부하는 경우가 많았고 (요청마다 다른 백엔드로 라우팅되는 듯 거부/수락이 요청마다 뒤바뀜),
- 클라우드가 수락해서 허브로 전달해도, 허브에 도달한 메시지 자체가 깨져서 드라이버(`init.lua`)가 아니라 **SmartThings 프레임워크 자체**(`st/driver.lua`)가 `json.decode` 중 에러를 내며 죽었습니다 (`bad argument #1: error converting Lua nil to String`).
- 명령 이름을 바꿔봐도(`send` → `replayLearnedCode`) 똑같이 재현됐고, 90초 동안 6번 연속 100% 재현될 만큼 지속적이었습니다 (단순 캐시 전파 지연이 아니었음).
- 새 capability **버전**을 만들어 우회 시도 → API가 거부 (proposed 상태 capability는 이 방식으로 버전을 못 늘림). 드라이버를 허브에서 제거 후 재설치해서 캐시를 비우려는 시도 → 플랫폼이 "기기가 사용 중"이라며 차단.

**최종 해결책**: capability를 아예 새로 만들었습니다 (당시 `acrosswatch58328.irBlasterV2`) — `learn`/`cancelLearn`/`sendCode`/`replayLearnedCode` **4개 명령을 생성 시점부터 전부 포함**시켜서, "나중에 명령을 끼워넣은" 상태 자체를 만들지 않았습니다. 이후 실기기로 4개 명령 전부 에러 없이 정상 동작하는 것을 Live Logging으로 확인했습니다. 즉, 근본 원인은 "capability 생성 후 명령을 추가하는 것" 자체가 SmartThings 플랫폼(클라우드 라우팅 또는 허브 캐시 중 어느 쪽인지는 불명)에서 문제를 일으켰던 것으로 보이고, **처음부터 완성된 capability를 쓰는 것**으로 완전히 우회됐습니다.

**UI 개선 (V3)**: 이후 앱 화면을 다듬으면서 `acrosswatch58328.irBlasterV3`으로 한 번 더 새로 만들었습니다 (속성 스키마도 바뀌어서 — enum 값을 한국어로, 화면 전용 속성 `learnedCodeStatus` 추가 — 같은 "처음부터 완성된 capability" 원칙을 한 번 더 적용했습니다). 표준 `momentary` capability도 이제 커스텀 capability 자체에 화면 정의(presentation)가 있어서 더 이상 필요 없어 제거했습니다 (원래는 커스텀 capability만 있는 컴포넌트는 SmartThings가 기본 화면을 못 만들어서 임시로 넣어뒀던 것).

**다중 신호(컴포넌트) 지원**: 처음에는 자식 기기 방식으로 구현했다가, "기기 하나 안에서" 여러 기능을 쓰고 싶다는 피드백을 받고 SmartThings 컴포넌트 방식(`device:emit_component_event`, `command.component`)으로 다시 만들었습니다. 실기기로 "3"번 컴포넌트에서 `learn`/`cancelLearn`을 실행했을 때 Zigbee 무선 통신은 정상적으로 나가고, 학습 상태가 정확히 "3"번에만 기록되며 "0"번은 전혀 영향받지 않는 것을 확인했습니다. "0"번(메인)에서는 실제 리모컨으로 학습한 신호를 `replayLearnedCode`로 재생해 청크 전송이 끝까지 완료되는 것("IR code transmit completed")까지 확인했습니다.

**루틴 액션 노출 (V4)**: 루틴(자동화)에서 이 기기의 동작을 쓸 수 없다는 피드백을 받고 보니, capability의 `automation.actions`를 비워뒀던 게 원인이었습니다. `learn`/`cancelLearn`/`replayLearnedCode`를 루틴 액션으로 노출하도록 채워 넣었는데, 기존 V3 capability를 제자리에서 업데이트하는 것만으로는 실제 기기 화면에 반영되지 않았습니다 (독립적으로 새로 만든 테스트 프로필에서는 즉시 반영되는 것으로 봐서, capability를 새로 만들지 않고 기존 것을 고치면 이미 페어링된 기기에는 어떤 이유로든 잘 전파되지 않는 것으로 보입니다 — `replayLearnedCode` 때와 동일한 패턴). 그래서 이번에도 `acrosswatch58328.irBlasterV4`로 다시 만들어(이번엔 `automation.actions`까지 처음부터 포함) 전환했고, 약 2~3분의 전파 지연 후 실기기에서 10개 컴포넌트 전부에 루틴 액션이 정상적으로 노출되는 것을 확인했습니다. 예전 capability들(`irBlaster`, `irBlasterV2`, `irBlasterV3`)은 더 이상 쓰지 않지만 계정에는 남아있습니다 — 삭제 API가 없어 그대로 뒀습니다.

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
