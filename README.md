# SmartThings Edge Drivers

여러 SmartThings Edge 드라이버 소스코드를 모아놓은 모노레포입니다. 각 하위 폴더는 독립적으로 패키징/배포 가능한 하나의 드라이버입니다.

## 드라이버 목록

| 드라이버 | 기기 | 설명 |
|---|---|---|
| [zgir01-driver](./zgir01-driver) | HOBEIAN ZG-IR01 | Zigbee IR 리모컨 스위치 |

## 폴더 구조

```
smartthings-edge-drivers/
├── README.md              # 이 파일
└── <driver-name>/         # 드라이버별 폴더 (SmartThings CLI 패키징 단위)
    ├── config.yml
    ├── fingerprints.yml
    ├── profiles/
    ├── src/
    └── README.md
```

새 드라이버를 추가할 때는 이 구조를 그대로 따라 새 폴더를 만들면 됩니다.

## 공통 준비 사항

```
npm install -g @smartthings/cli
smartthings login
```

## 드라이버 패키징/배포

각 드라이버 폴더 안에서:

```
smartthings edge:drivers:package .
```

자세한 설치/페어링 방법은 각 드라이버 폴더의 README.md를 참고하세요.
