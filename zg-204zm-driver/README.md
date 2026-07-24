# HOBEIAN ZG-204ZM SmartThings Edge Driver

HOBEIAN ZG-204ZM ("PIR + 24GHz 레이더 재실/모션 센서") 지그비 기기를 위한 SmartThings Edge 드라이버입니다.

## 현재 배포 상태

이 드라이버는 이미 패키징되어 채널 `nemonemoTTE-st-edge`(`007193fb-5de8-45cb-bb24-c405c226906c`)에 업로드되었고, 허브 "공용화장실 스테이션"(`b8da18b7-4a79-400f-9694-c700aa83d9e8`)에 설치되어 있으며, "공용화장실 문 앞 재실센서" 기기(`9d9ed388-8c46-4908-a69d-5b11bb2816dd`)가 이 드라이버로 전환 완료된 상태입니다. 아래 "설치 방법"은 다른 기기/허브에 동일하게 적용하고 싶을 때를 위한 참고용입니다.

## 지원 기능

- 재실/모션 감지 (`motionSensor` - active/inactive)
- 모션 세부 상태 (`없음`/`큰 동작`/`미세 동작`/`정지(재실)`) - 커스텀 capability `acrosswatch58328.motionState`
- 조도 (`illuminanceMeasurement`) - Tuya datapoint와 표준 Zigbee Illuminance Measurement 클러스터(0x0400) 둘 다 처리
- 배터리 잔량 (`battery`)
- 새로고침 (`refresh`) - 앱에서 당겨서 새로고침하면 기기에 현재 모든 설정값을 다시 보고하도록 요청 (Tuya `dataQuery`)
- 기기 설정 (기기 Settings에서 변경) - zigbee-herdsman-converters의 ZG-204ZM 정의에 있는 설정 가능한 datapoint를 전부 반영했습니다:
  - 재실 유지 시간 (fading time, 0~28800초)
  - 정지 감지 거리 (0~6m)
  - 정지 감지 민감도 (0~10)
  - 동작 감지 모드 (PIR만 / PIR+레이더 / 레이더만) — 펌웨어 `0122052017` 이상 필요
  - 동작 감지 민감도 (0~10) — 펌웨어 `0122052017` 이상 필요
  - LED 표시등 켜짐/꺼짐

설정을 처음 변경할 때만 해당 값이 기기로 전송됩니다 (드라이버를 처음 적용하거나 다른 드라이버에서 전환할 때는 전송되지 않음 - 실기기로 확인함). 위 항목들의 "기본값"은 실제 페어링된 기기에 `refresh`(Tuya `dataQuery`)를 보내 읽어온 현재 값으로 맞춰뒀습니다.

## 기술 배경

- Zigbee가 `manufacturer` = `"HOBEIAN"`, `model` = `"ZG-204ZM"`으로 리포트하는 것을 실제 페어링된 기기에서 직접 확인했습니다 (zigbee-herdsman-converters의 `AY205Z`/`AOYAN` 화이트라벨과 같은 패턴 — 일반 Tuya `_TZE200_xxx` 대신 자체 브랜드 문자열 사용). `fingerprints.yml`에는 혹시 다른 개체가 `_TZE200_2aaelwxk` / `_TZE200_kb5noeto` / `_TZE200_tyffvoij` / `_TZE200_yflzeeqj` (모델 `TS0601`)로 리포트하는 경우를 대비한 예비 항목도 추가해 두었습니다.
- Tuya EF00(0xEF00) 클러스터의 datapoint(DP) 프로토콜 (zigbee-herdsman-converters `ZG-204ZM` 정의 기준):

  | DP | 용도 | 타입 |
  |----|------|------|
  | 1 | 재실 감지 (bool) | bool |
  | 2 | 정지 감지 민감도 (0~10) | value |
  | 4 | 정지 감지 거리 (cm, 100배) | value |
  | 101 | 모션 상태 (0=없음,1=큰 동작,2=미세 동작,3=정지) | enum |
  | 102 | 재실 유지 시간 (초) | value |
  | 106 | 조도 (lux) | value |
  | 107 | LED 표시등 | bool |
  | 121 | 배터리 잔량 (%) | value |
  | 122 | 동작 감지 모드 (0=PIR만,1=PIR+레이더,2=레이더만) | enum |
  | 123 | 동작 감지 민감도 (0~10) | value |

  zigbee2mqtt가 이 기기에 대해 노출하는 설정 가능한 datapoint(DP2, 4, 102, 107, 122, 123)는 이 6개가 전부이며, 드라이버에 전부 반영되어 있습니다.

- 이 기기는 Tuya DP 106(조도)과는 별개로 표준 Zigbee Illuminance Measurement 클러스터(0x0400)도 구현하고 있어(zigbee-herdsman-converters가 `m.illuminance({reporting: false})`로 별도 처리하는 것과 같은 이유), `st.zigbee.defaults`를 통해 표준 클러스터 리포트도 함께 처리하도록 했습니다. DP 106은 `refresh`(dataQuery)에 응답하지 않지만 표준 클러스터는 즉시 값을 읽어올 수 있어서, 두 경로를 함께 두는 게 의미가 있었습니다.
- 배터리는 표준 Power Configuration 클러스터(0x0001)도 자발적으로 리포트하지만, `BatteryVoltage`를 `BatteryPercentageRemaining`과 함께 보내는 바람에 `st.zigbee.defaults`가 리포트마다 `"The device reported a voltage, but the driver was not configured to handle it"` 경고를 남기는 걸 실기기 테스트로 발견했습니다. DP 121이 이미 동일한 값을 보고하고 `refresh`에도 응답하므로, 배터리는 DP 121 하나만 처리하도록 정리해서 이 경고를 없앴습니다.
- **미문서 datapoint 124**: 실기기에서 `refresh`를 보내 확인하는 과정에서, zigbee-herdsman-converters에는 없는 datapoint 124(값=10, value 타입)를 추가로 발견했습니다. DP122(동작 감지 모드)·DP123(동작 감지 민감도) 바로 다음 번호라 정지 감지 거리(DP4)의 짝인 "움직임 감지 거리"일 가능성이 있으나, 단위/범위를 확인할 방법이 없어 설정 항목으로는 추가하지 않았습니다. Live Logging에는 `ZG-204ZM: unhandled datapoint 124 (len 4): ...`로 계속 표시됩니다.

## 설치 방법

이 저장소의 다른 드라이버들과 동일한 절차입니다.

### 1. SmartThings CLI 설치 및 로그인

```
npm install -g @smartthings/cli
smartthings login
```

### 2. 커스텀 capability 생성 (최초 1회만)

모션 세부 상태(`motion_state`) 표시를 위한 커스텀 capability가 필요합니다. 이미 `acrosswatch58328.motionState`로 생성되어 있다면 이 단계는 건너뛰어도 됩니다.

### 3. 드라이버 패키징 및 설치

이 폴더(`zg-204zm-driver`)에서:

```
smartthings edge:drivers:package . --install
```

채널/허브를 프롬프트에서 선택하면 빌드 → 업로드 → 채널 할당 → 허브 설치까지 한 번에 진행됩니다.

### 4. 기기를 이 드라이버로 전환

이미 "지원되지 않는 기기"(제네릭 Zigbee 센서)로 페어링되어 있다면, 재페어링 없이 드라이버만 전환할 수 있습니다:

```
smartthings edge:drivers:switch <deviceId>
```

허브/드라이버를 프롬프트에서 선택합니다. Fingerprint가 일치해야 목록에 나타나므로, 나타나지 않는다면 `fingerprints.yml`의 `manufacturer`/`model` 값이 실제 기기와 다른 것입니다.

아직 SmartThings에 전혀 페어링되지 않은 새 기기라면, 페어링 모드로 진입 후 앱에서 기기 추가 → 검색을 진행하면 이 드라이버가 매칭됩니다.

## 문제가 있다면

- 모션/재실 감지가 반영되지 않으면 `smartthings edge:drivers:logcat`으로 Live Logging을 확인해주세요. Tuya DP 번호나 데이터 타입이 실제 기기와 다를 가능성을 배제할 수 없습니다.
- 동작 감지 모드/민감도 설정이 반영되지 않으면 기기 펌웨어가 `0122052017`보다 낮을 수 있습니다 (zigbee2mqtt 문서 기준).
