# Dejima

텍스트를 선택하고 ⌘C를 두 번 누르면 포인터 옆에 번역문이 떠오릅니다. 번역은 모두 기기 안에서 이루어지며, 어떤 서버도 거치지 않습니다.

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

메뉴 막대에 상주하며 Dock 아이콘도, 메인 창도 없습니다. 번역은 macOS에 내장된 Translation 프레임워크를 쓰고, 언어 모델은 시스템 전체에서 공유됩니다. ‘번역’ 앱에서 내려받은 모델은 여기서 바로 쓸 수 있고, 그 반대도 마찬가지입니다.

아직 배우는 중인 언어로 논문을 읽을 때의 흐름은 이렇습니다. 선택 → 번역 앱으로 전환 → 붙여넣기 → 읽기 → 다시 돌아오기. 이 정도 번거로움이면 모르는 단어 하나쯤은 그냥 넘기게 됩니다. Dejima는 이 과정을 이미 손에 익은 동작 하나로 줄입니다. ⌘C ⌘C. 그리고 클립보드에는 발표 전 원고, 다른 사람의 메시지, 사내 문서가 들어 있을 수 있으니 오프라인으로 동작하는 것은 타협할 수 없는 조건입니다.

## 이름에 대하여

데지마(出島)는 나가사키 항구에 만든 인공 섬입니다. 일본이 바깥 세계에 문을 닫았던 두 세기 동안 이곳은 외국과 교역하는 유일한 창구였습니다. 아주 작은 항구였지만, 바깥에서 오는 모든 것이 이곳을 거쳐 들어왔습니다.

## 다운로드

[Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest)에서 `Dejima-<버전>.dmg`를 받으세요. 열어서 시스템에 맞게 ‘macOS 26 이상’ 또는 ‘macOS 15~25’ 폴더를 연 다음, 안에 있는 `Dejima.app`을 옆의 Applications 가상본으로 드래그하면 됩니다.

잘못 골라도 문제없습니다. 더 새로운 시스템이 필요한 빌드는 macOS가 실행을 거부하고, 어느 버전이 필요한지 알려 줍니다.

두 빌드는 기능이 완전히 같습니다. 차이는 시스템에 번역 세션을 요청하는 방식뿐입니다. macOS 26 API는 세션을 직접 만들 수 있어서 화면 구석에 숨겨 둔 창이 필요 없습니다. 대신 언어 팩이 없을 때 시스템 다운로드 창을 띄우지 않고 오류를 냅니다. 두 빌드는 번들 ID가 같으므로 서로 바꿔 설치해도 손쉬운 사용 권한, 로그인 항목, 설정이 그대로 유지됩니다.

⌘C를 감지하려면 손쉬운 사용 권한도 필요합니다. 선택 기능인 ‘다듬기’는 여기에 더해 Apple Intelligence와 macOS 26 이상이 필요합니다.

## 처음 실행할 때

**1. 손쉬운 사용 권한을 부여합니다.** 권한 없이 실행하면 안내 창이 열립니다. 버튼을 눌러 손쉬운 사용 설정을 연 다음, **창에 있는 Dejima 아이콘을 목록으로 바로 드래그**하고 스위치를 켜세요.

드래그하는 것은 지금 실행 중인 번들 자체이므로 엉뚱한 것을 추가할 일이 없습니다. 권한은 특정 번들에 묶입니다. 가상본이나 다운로드 폴더에 남은 또 하나의 사본을 추가하면 된 것처럼 보여도 아무 효과가 없습니다. 앱이 아직 Applications에 없다면 안내 창이 먼저 옮기라고 알려 줍니다. 권한을 준 뒤에 옮기면 권한이 무효가 됩니다.

스위치를 켜면 창이 저절로 닫히고 감지가 바로 시작됩니다. 보통은 다시 실행할 필요가 없습니다. 안내 창을 다시 열려면: 메뉴 막대 아이콘 → `손쉬운 사용 권한 부여…`.

**2. 언어 모델을 내려받습니다.** 메뉴의 `언어 모델 확인…`을 누르면 시스템 설정의 번역 언어 화면이 열립니다. 필요한 언어마다 하나씩 받으세요. 언어 팩 하나는 1~3GB입니다.

모델이 없으면 첫 번역 때 시스템 다운로드 창이 뜹니다. 하지만 이 창을 띄우는 창이 보이지 않는 창이라서 엉뚱한 위치에 나타나거나 이상하게 동작할 수 있습니다. 미리 받아 두는 편이 좋습니다.

**3. 사용해 봅니다.** 외국어 문장을 선택하고 ⌘C를 두 번 누르세요.

## 번역 방향

메뉴에 설정이 두 개 있고, 이 둘로 일상적인 두 가지 경우를 모두 처리합니다.

| 감지된 언어 | 번역 결과 |
|---|---|
| 일본어 / 영어 / 그 밖의 언어 | 주 언어 (기본값: 중국어 간체) |
| 주 언어 자체 | 보조 언어 (기본값: 일본어) |
| 판별 불가 | 주 언어. 원본 언어 추정은 프레임워크에 맡김 |

그래서 일본어와 영어는 중국어로, 중국어는 일본어로 번역됩니다. 논문을 읽을 때도, 답장을 쓸 때도 설정을 건드릴 필요가 없습니다. 한국어 사용자라면 주 언어를 한국어로 바꾸면 됩니다.

언어 감지에는 `NLLanguageRecognizer`를 씁니다. 짧은 문자열에 대한 추정은 믿기 어려워서 기준을 두었습니다. 신뢰도가 0.4를 넘거나 텍스트가 12자보다 길 때만 결과를 채택합니다. 방향을 정할 때 `zh-Hans`와 `zh`는 같은 언어로 취급합니다. 선택할 수 있는 언어는 `LanguageRouter.choices`에 있습니다. 현재는 중국어 간체·번체, 일본어, 영어, 한국어, 독일어, 프랑스어, 스페인어, 러시아어이며, 필요에 따라 빼거나 더하면 됩니다.

패널에는 복사 버튼이 있습니다. 패널 바깥을 클릭하거나 Esc를 누르면 닫힙니다.

## 인터페이스 언어

시스템 언어를 따릅니다. 중국어 간체, 일본어, 한국어, 영어를 지원하며 별도 설정은 없습니다. 그 밖의 언어에서는 영어로 표시됩니다. 무엇으로 번역할지와는 관계없습니다. 그것은 위의 언어 쌍이 정합니다.

## 네트워크에 닿는 것

**번역하는 내용은 절대 기기 밖으로 나가지 않습니다.** 번역은 로컬 Translation 프레임워크가, 다듬기는 기기 내 Apple Intelligence가 처리합니다. 어느 쪽도 외부에 연결하지 않습니다.

앱에서 네트워크 요청을 보내는 것은 딱 하나, 업데이트 확인입니다. GitHub의 releases API에 최신 버전 번호를 물어봅니다.

- `업데이트 확인…`은 선택했을 때 한 번만 실행됩니다
- `자동으로 업데이트 확인`은 **기본값이 꺼짐**입니다. 켜면 실행할 때 하루 최대 한 번 확인합니다
- 요청에는 HTTP 호출 자체 외에 아무것도 담기지 않습니다. 식별자도, 사용 기록도, 당연히 번역한 텍스트도 없습니다

코드는 `Sources/Updater.swift`에 있으며 180줄이 안 됩니다. 이마저도 원하지 않는다면 두 설정을 꺼 두거나 파일을 지우세요.

## 빌드

Xcode 16 이상과 XcodeGen이 필요합니다.

```bash
brew install xcodegen   # 없다면
xcodegen generate
open Dejima.xcodeproj
```

스킴 선택기에 `Dejima`와 `Dejima26`이 나옵니다. 하나를 고르고 ⌘R. 명령줄에서는:

```bash
xcodebuild -scheme Dejima   -configuration Release build   # macOS 15+
xcodebuild -scheme Dejima26 -configuration Release build   # macOS 26+
```

`Dejima26`이 `Dejima26.app`으로 빌드되는 것은 두 타깃이 서로 덮어쓰지 않게 하기 위해서일 뿐이며, 패키징할 때 `Dejima.app`으로 이름이 바뀝니다.

`project.yml`의 `DEVELOPMENT_TEAM`은 작성자 본인의 Team ID입니다. 자신의 것으로 바꾸거나 Signing & Capabilities에서 "Sign to Run Locally"로 바꾸세요. **고정된 서명 인증서를 쓰세요.** 손쉬운 사용 권한은 번들 ID와 코드 서명에 묶여 있어서, ad-hoc 서명이면 다시 빌드할 때마다 권한이 사라집니다.

XcodeGen 없이 직접 설정하려면:

1. Xcode → New Project → macOS → App, Interface: SwiftUI, 이름은 `Dejima`
2. 생성된 `ContentView.swift`와 `DejimaApp.swift`를 삭제
3. `Sources/` 최상위의 파일들, `Localizable.xcstrings`, `InfoPlist.xcstrings`, `Assets.xcassets`, 그리고 `TranslationLegacy/`와 `Translation26/` 중 **하나**(각각 macOS 15용, 26용)를 끌어다 넣기
4. Target → Info에 `Application is agent (UIElement)` = `YES` 추가
5. Target → Signing & Capabilities에서 **App Sandbox 제거** (샌드박스와 전역 키 감지는 함께 쓸 수 없습니다)

## 릴리스 패키징

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=dejima \
./Scripts/release.sh
```

그러면 `dist/Dejima-<버전>.dmg`가 만들어집니다. 최소 macOS 버전마다 폴더가 하나씩 있고, 각 폴더에 `Dejima.app`과 Applications 가상본이 들어 있습니다.

```
Dejima 0.2.0
├── macOS 15-25.localized/
│   ├── Dejima.app
│   └── Applications →
├── macOS 26+.localized/
│   ├── Dejima.app
│   └── Applications →
└── Read Me.txt
```

둘 다 이름이 `Dejima.app`이고 폴더로만 구분합니다. 그래서 `/Applications`에 버전 번호가 붙은 이름으로 설치될 일이 없습니다.

폴더 이름 끝에는 `.localized`가 붙어 있습니다. Finder는 이 접미사를 숨기고 시스템 언어에 맞는 폴더 이름을 보여 줍니다(중국어, 영어, 일본어, 한국어. 그 밖의 언어는 영어). 언어별 이름은 `release.sh`의 `localize_folder`에서 정합니다.

**서명은 선택 사항이 아닙니다.** 프로젝트 기본값인 Apple Development 인증서로 서명한 앱은 본인 기기에서만 실행되고, 내려받은 다른 사람에게는 Gatekeeper가 막습니다. 배포하려면 Developer ID Application 인증서와 공증(notarization)이 필요합니다. 공증 자격 증명은 한 번만 저장해 두면 됩니다.

```bash
xcrun notarytool store-credentials dejima \
  --apple-id you@example.com --team-id TEAMID --password <앱 암호>
```

두 변수 없이도 스크립트는 돌아갑니다. 다만 본인만 열 수 있는 DMG가 만들어지고, 끝날 때 그렇다고 알려 줍니다.

**릴리스할 때마다** `project.yml`의 `MARKETING_VERSION`을 올리고(두 타깃이 같은 템플릿을 공유합니다) `v0.1.0` 형식으로 태그를 다세요. 업데이트 확인은 번들 안의 버전과 비교합니다.

## 코드 구성

| 파일 | 역할 |
|---|---|
| `DejimaApp` | `@main` 진입점, `MenuBarExtra` |
| `Controller` | `AppDelegate`와 각 부분 연결: 권한, 감지 켜고 끄기, 번역 조율 |
| `DoubleCopyMonitor` | 전역 키 감지, 두 번 누르기 판정, 클립보드 읽기 |
| `LanguageRouter` | 언어 감지와 번역 방향 결정 |
| `TranslationLegacy/TranslationHub` | macOS 15 빌드: 뷰에 묶인 Apple API를 일반 `async` 함수로 감쌈. 숨겨진 호스트 창을 소유 |
| `Translation26/TranslationHub` | macOS 26 빌드: 세션을 직접 생성. API는 같고 창은 없음 |
| `Polisher` | 선택 기능인 Apple Intelligence 다듬기 |
| `PermissionGuide` | 드래그할 수 있는 앱 아이콘이 있는 손쉬운 사용 안내 창 |
| `TextCleaner` | PDF에서 복사한 텍스트의 강제 줄바꿈 복구 |
| `LoginItem` | 로그인 시 실행 |
| `Updater` | 업데이트 확인. 앱에서 유일한 네트워크 코드 |
| `ResultPanel` | `ResultModel`과 포커스를 빼앗지 않는 플로팅 패널 |
| `ResultView` | 패널 내용: 위에 번역문, 아래에 원문 |
| `MenuBarView` | 메뉴 내용 |
| `DejimaMark` | 출(出) 마크. 메뉴 막대 아이콘이기도 함 |

`Scripts/`에는 앱 아이콘(`app-icon.swift`), DMG 창 배경과 배치(`dmg-window.swift`), 패키징 스크립트(`release.sh`)가 있습니다.

## 앞으로 더할 만한 것

- 정해 둔 용어를 고정된 번역으로 묶어 두는 용어집. 다듬기 지시문에 함께 넘김
- ‘Apple Intelligence로 다듬기’를 믿고 쓸 수 있게 만들기. Apple의 NMT 모델은 빠르고 오프라인으로 동작하지만, 기술·학술 문장은 밋밋하게 만들어 버립니다. 이 기능을 켜면 기기 내 LLM이 원문과 초벌 번역을 받아 용어와 표현을 고치고, 고유 명사, 유전자·단백질 이름, 화학명, 단위, 인용은 그대로 두도록 지시받습니다. 여전히 오프라인이고 1초쯤 느려지며, 문제가 생기면 조용히 초벌 번역으로 돌아갑니다. 다만 결과가 아직 고르지 않아서 기본값은 꺼짐입니다

## 라이선스

MIT. [LICENSE](LICENSE)를 보세요.

## 참고 자료

- WWDC24 "Meet the Translation API" — `translationTask`와 `Configuration.invalidate()`에 관한 공식 설명
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) — 같은 프레임워크를 쓰는 오픈 소스 스크린숏 번역기. 모델 다운로드를 어떻게 처리하는지 비교해 볼 만합니다
