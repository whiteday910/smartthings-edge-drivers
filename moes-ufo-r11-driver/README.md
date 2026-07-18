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
- **학습된 코드 (`learnedCode`, 읽기 전용)**: 가장 최근에 학습된 코드가 base64 문자열로 표시됩니다. 복사해서 자동화(오토메이션)나 다른 곳에 저장해두고 재사용할 수 있습니다.
- **코드 전송 (`sendCode`, 문자열 인자 `code`)**: `learnedCode`에서 복사한 base64 문자열을 그대로 붙여넣으면 그 코드를 재전송합니다. 필요하면 `{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"..."}}` 형태의 전체 JSON을 직접 넣어 `freq`/`delay` 등을 조정할 수도 있습니다.

학습 상태(`learningState`: `idle`/`learning`)도 함께 노출되어, 코드 캡처가 완료되면 자동으로 `idle`로 돌아갑니다.

커스텀 capability 화면 표시(presentation)도 만들어져 있어서, 기기 상세 화면에 학습 상태/학습된 코드 텍스트와 학습 시작/취소 버튼이 표시됩니다. 단, `sendCode`처럼 텍스트를 직접 입력해야 하는 명령은 SmartThings 앱 자체가 커스텀 capability에 텍스트 입력 UI를 지원하지 않아서, 앱에서 직접 실행할 수 없습니다 — 아래 "사용법" 항목의 CLI 방법을 사용하세요.

## 사용법

### 앱에서

기기 상세 화면의 "학습 시작" 버튼(또는 momentary 버튼)을 누르고, 몇 초 안에 기존 리모컨을 기기에 가까이 대고 버튼을 누르세요. "학습된 코드" 텍스트에 base64 코드가 표시되면 성공입니다.

### CLI에서 (코드 전송까지 하려면 필요)

```
# 1. 학습 시작
smartthings devices:commands <deviceId> 'acrosswatch58328.irBlaster:learn()'

# 2. (기존 리모컨을 기기에 가까이 대고 버튼을 누름)

# 3. 학습된 코드 확인
smartthings devices:capability-status <deviceId> main acrosswatch58328.irBlaster

# 4. 학습된 코드 재전송(재생)
smartthings devices:commands <deviceId> 'acrosswatch58328.irBlaster:sendCode("<learnedCode 값>")'
```

`<deviceId>`는 `smartthings devices`로 조회할 수 있습니다.

## 지원하지 않는 기능 (의도적 범위 제외)

- **Raw IR timing 배열 입출력** (예: `[9000, -4500, 560, ...]` 형태의 압축/해제). zigbee-herdsman-converters는 이를 위해 자체 압축 코덱을 구현하지만, 학습한 코드를 그대로 재사용하는 핵심 시나리오에는 필요하지 않아 이번 범위에서 제외했습니다. 필요하면 알려주세요.

## 기술 배경 (참고)

- Zigbee 클러스터 `0xE004` (Zosung IR Control): 명령 `0x00`에 raw JSON payload(`{"study":0}` = 학습 시작, `{"study":1}` = 학습 종료)를 실어 보냅니다.
- Zigbee 클러스터 `0xED00` (Zosung IR Transmit): manufacturer-specific 명령 `0x00`~`0x05`로 청크 분할 전송을 수행합니다. 학습 완료 시 기기가 보낸 raw bytes를 base64로 인코딩해 `learnedCode`에 저장하고, 전송 시에는 JSON 문자열(`ir_msg`)을 같은 방식으로 기기에 청크 전송합니다.
- 두 개의 독립적인 오픈소스 구현(zigbee-herdsman-converters의 `lib/zosung.ts`, ZHA의 `zhaquirks/tuya/ts1201.py` — 이 파일은 `_TZ3290_ot6ewjvmejq5ekhl`를 명시적으로 지원 목록에 포함)을 서로 대조하며 프로토콜을 파악해서 이식했습니다.
- fingerprint는 특정 manufacturer 문자열 대신 클러스터 조합(`0xE004`+`0xED00`)으로 매칭하므로, 같은 칩셋의 다른 manufacturer 문자열 변형(`_TZ3290_j37rooaxrcdcqo5n`, `_TZ3290_7v1k4vufotpowp9z` 등)에서도 동작할 가능성이 높습니다.

## ⚠️ 검증 상태

페어링(fingerprint 매칭)과 capability 명령/상태 읽기까지는 실기기로 확인했습니다. 다만 실제 리모컨 신호를 학습해서 청크 전송 핸드셰이크 전체가 끝까지 정상 동작하는지는 아직 실사용으로 확인 전입니다. 특히:

- 청크 전송 핸드셰이크(체크섬, 시퀀스 번호, Default Response 응답)의 세부 바이트 레이아웃
- `learnedCode`로 노출되는 base64 데이터가 다른 통합(HA 등)과 100% 동일한 포맷인지 여부

학습/전송이 예상과 다르게 동작하면 SmartThings 앱의 Live Logging(CLI: `smartthings edge:drivers:logcat`) 로그를 캡처해서 알려주세요. 로그를 보고 바이트 레이아웃을 수정할 수 있습니다.

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
