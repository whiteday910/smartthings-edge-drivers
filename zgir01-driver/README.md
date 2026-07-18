# HOBEIAN ZG-IR01 SmartThings Edge Driver

HOBEIAN ZG-IR01 ("Smart IR remote switch") 지그비 IR 리모컨 기기를 위한 SmartThings Edge 드라이버입니다.

## 지원 기능

- IR 스위치 1~6 (각각 켜짐/꺼짐에 서로 다른 IR 코드를 매핑해서 전송)
  - 스위치 1은 메인 기기에, 스위치 2~6은 자식(child) 기기 5개로 자동 생성되어 각각 앱에서 개별 스위치로 표시됩니다.
- 온도 / 습도 / 배터리 센서
- 온도 표시 단위(섭씨/화씨), 온도 보정값, 습도 보정값 (기기 설정에서 변경)
- 스위치별 IR 코드 학습 (기기 설정에서 시작)

## 지원하지 않는 기능 (의도적 범위 제외)

이 기기는 두 가지 방식으로 IR 코드를 다룰 수 있습니다.

1. **슬롯 학습 방식** (이 드라이버가 구현하는 방식): 스위치 1~6의 ON/OFF 슬롯에 실제 리모컨을 대고 학습시켜서, 이후 스위치를 켜고 끌 때 그 코드를 재생. 이 드라이버는 이 방식만 구현합니다.
2. **임의 IR 코드 학습/전송 방식** (Zosung 프로토콜, `ir_code_to_send`/SmartIR 라이브러리 코드 등): base64로 인코딩된 임의의 IR 타이밍 코드를 학습하거나 전송하는 고급 기능. 이 프로토콜은 리버스 엔지니어링된 비표준 프로토콜(청크 분할 전송 + 체크섬)이라 구현 난이도와 실기기 미검증 리스크가 커서, 이번 개발 범위에서는 제외했습니다. Home Assistant ZHA 커뮤니티의 이 기기용 quirk도 동일한 이유로 이 기능은 구현하지 않았습니다 (`therealdigitalkiwi/zha-zg-ir01` 참고).

나중에 이 기능이 꼭 필요하면 알려주세요 — 별도로 설계/구현을 진행할 수 있습니다.

## 기술 배경 (참고)

- Zigbee `modelID`가 `"ZG-IR01"`로 리포트되는 Tuya 기반 기기 (zigbee-herdsman-converters, manufacturer 문자열 예: `_TZE200_33rdmvgw`).
- 표준 Tuya EF00(0xEF00) 클러스터의 datapoint(DP) 프로토콜을 사용:

  | DP | 용도 | 타입 |
  |----|------|------|
  | 1-6 | 스위치 1~6 on/off | bool |
  | 107 | 온도 보정값 (x10) | value |
  | 108 | 습도 보정값 | value |
  | 109 | 온도 (x10) | value |
  | 110 | 습도 | value |
  | 111 | 온도 단위 (0=섭씨,1=화씨) | enum |
  | 112 | 배터리 잔량 % | value |
  | 120-131 | 스위치별 on/off 코드 학습 상태 (study/registered/unregistered) | enum |

- 이 기기는 추가로 Zosung 커스텀 클러스터(0xE004, 0xED00)도 갖고 있어 fingerprint 매칭에 사용했습니다 (`fingerprints.yml`의 `zigbeeGeneric` 항목이 이 세 클러스터가 모두 존재하는 기기를 매칭). 특정 manufacturer 문자열 대신 클러스터 조합으로 매칭하기 때문에, 다른 manufacturer 문자열 변형이 있어도 동작할 가능성이 높습니다.

## 설치 방법

이 드라이버 코드는 준비되어 있지만, SmartThings 개발자 계정/허브가 없으면 저는 패키징·배포·페어링을 대신 해드릴 수 없습니다. 아래 절차를 직접 진행해주세요.

### 1. SmartThings CLI 설치 및 로그인

```
npm install -g @smartthings/cli
smartthings login
```

### 2. 드라이버 패키징

이 폴더(`zgir01-driver`)에서:

```
smartthings edge:drivers:package .
```

처음 실행하면 대화형으로 채널(channel) 생성 여부를 물어봅니다. 개인용 채널이 없다면 새로 만들어주세요.

### 3. 허브를 채널에 등록하고 드라이버 설치

```
smartthings edge:channels:enroll
smartthings edge:drivers:install
```

허브를 선택하고, 방금 패키징한 드라이버를 설치합니다.

### 4. 기기 재검색(다시 페어링)

이미 기기가 SmartThings에 "지원되지 않는 기기"로 추가되어 있다면, Zigbee 기기는 보통 fingerprint를 다시 인식시키기 위해 **기기를 제외(remove)한 뒤 다시 페어링**해야 합니다.

1. SmartThings 앱에서 기존 ZG-IR01 기기 삭제
2. 기기 뒷면 리셋 버튼 등으로 페어링 모드 진입 (제품 설명서 참고)
3. SmartThings 앱 > 기기 추가 > 검색 → 정상적으로 이 드라이버가 매칭되면 "HOBEIAN ZG-IR01 IR Remote"로 표시됨
4. 페어링 완료 시 자동으로 스위치 2~6 자식 기기 5개가 함께 생성됩니다.

### 5. IR 코드 학습시키기

기존에 쓰던 리모컨(에어컨, TV 등)의 코드를 각 스위치에 매핑하려면:

1. SmartThings 앱에서 메인 기기(스위치 1이 있는 기기) 열기 → 설정(톱니바퀴 아이콘) → "스위치 N IR 코드 학습"
2. "켜짐(ON) 코드 학습 시작" 또는 "꺼짐(OFF) 코드 학습 시작" 선택 후 저장
3. 몇 초 안에 기존 리모컨을 ZG-IR01에 가까이 대고 원하는 버튼을 누름
4. 기기가 코드를 저장하면 학습 완료. 이후 스위치 N을 켜거나 끄면 그 코드가 전송됩니다.
5. 재학습하려면 설정을 "대기"로 바꿨다가 다시 "학습 시작"을 선택하세요.

## 문제가 있다면

- 페어링이 전혀 안 되거나 다른 드라이버로 인식된다면, 실제 기기가 리포트하는 manufacturer 문자열이 다를 수 있습니다. `smartthings devices` 또는 IDE에서 raw description을 확인해 manufacturer 값을 알려주시면 `fingerprints.yml`에 정확한 `zigbeeManufacturer` 항목을 추가해드릴 수 있습니다.
- 스위치는 켜지는데 온도/습도/배터리가 안 뜨거나, 학습이 반영되지 않는 등 실제 기기와 다르게 동작하는 부분이 있으면 SmartThings 앱의 "Live Logging" (CLI: `smartthings edge:drivers:logcat`)으로 로그를 확인해서 알려주세요. DP 번호나 데이터 타입이 실제 기기와 다를 가능성을 배제할 수 없습니다 (zigbee-herdsman-converters와 ZHA quirk 소스를 근거로 만들었지만 실기기로 직접 검증하지는 못했습니다).
