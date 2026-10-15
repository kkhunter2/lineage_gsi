[English](README.md) | 한국어

# lineage_gsi — LineageOS 23.2 GSI

arm64 A/B Treble 기기용 비공식 LineageOS 23.2(Android 16 QPR2) GSI입니다.

2026-05-24 이후 업데이트가 멈춘 [MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)를
이어받았습니다. 패치 구성은 같고, 여기에 다음이 더해졌습니다.

- **얼굴 인식 복원.** 23.2가 RestlessOS 패치셋으로 갈아타면서 빠졌던 FaceSense(`co.aospa.sense`)를
  되살렸습니다. 전면 카메라로 인식하는 소프트웨어 방식이라 벤더의 face HAL이 필요 없습니다.
- **벤더 곡선 없이도 자동 밝기 동작.** framework-res에 lux → 밝기 기본 곡선을 넣었습니다.
  벤더 오버레이에 곡선이 있는 기기는 그쪽 값을 그대로 씁니다.
- **최신 LineageOS 23.2 소스.** 릴리즈마다 LineageOS 최신 소스로 다시 빌드하므로,
  업스트림 마지막 빌드보다 새로운 보안 패치가 들어갑니다.

## 다운로드

[Releases](https://github.com/kkhunter2/lineage_gsi/releases)에서 받으세요.

| 변형 | 의미 |
|---|---|
| `arm64_bgN4` | arm64, GApps(MindTheGapps), ext4, userdebug |

릴리즈마다 `.sha256`과, 빌드에 쓴 모든 프로젝트 리비전을 고정해둔 `manifest-snapshot.xml`이 함께 올라갑니다.

## 설치

1. 압축 해제: `xz -d lineage-23.2-*-arm64_bgN4.img.xz`
2. fastbootd로 재부팅(`adb reboot fastboot`)한 뒤 플래시:
   ```
   fastboot flash system lineage-23.2-*-arm64_bgN4.img
   fastboot reboot
   ```
   다른 LineageOS 23.x GSI에서 넘어올 때는 초기화 없이(dirty flash) 됩니다.
   그 밖의 롬에서 올 때는 데이터를 지우세요(`fastboot -w`).
3. `system`을 건드리지 않고 먼저 써보려면 [DSU Sideloader](https://github.com/VegaBobo/DSU-Sideloader)를 쓰면 됩니다.

테스트 키로 서명된 빌드입니다. 사용 책임은 본인에게 있고, GSI가 얼마나 잘 도는지는
벤더가 Treble 규격을 얼마나 지켰는지에 달려 있습니다.

### 테스트한 기기

- Lenovo Legion Y700 2022(TB-9707F, SD870, WiFi 전용). WiFi 전용 기기의 telephony 크래시 루프는
  [y700-magisk-modules](https://github.com/kkhunter2/LineageOS_gsi/releases/tag/y700-magisk-modules)의
  `notelephony-module.zip`으로 막을 수 있습니다.
- Samsung Galaxy A04(SM-A045F): 한 사용자가 이 패치셋 빌드를 DSU로 부팅해 확인했습니다.

## 빌드

빌드 방법은 [README.md](README.md#build)를 보세요.
