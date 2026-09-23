# Dejima

テキストを選択して ⌘C を2回。訳文がポインタの横に浮かびます。翻訳はすべて端末内で完結し、サーバーを経由しません。

[简体中文](README.md) · [English](README.en.md)

メニューバーに常駐し、Dock アイコンもメインウィンドウもありません。翻訳は macOS 標準の Translation フレームワーク経由で、言語モデルはシステム全体で共有されます。「翻訳」App でダウンロード済みのものはそのまま使えますし、その逆も同じです。

まだ習得中の言語で論文を読むとき、流れはこうなります。選択 → 翻訳アプリに切り替え → 貼り付け → 読む → 戻る。この摩擦は、分からなかった単語を調べずに飛ばす理由として十分です。Dejima はこれを、すでに手が覚えている動作ひとつに畳み込みます——⌘C ⌘C。クリップボードには未発表の原稿、他人からのメッセージ、社内文書が入り得るので、オフラインであることは譲れない条件です。

## 名前について

出島は長崎の港にあった人工の島です。日本が国を閉ざしていた二世紀のあいだ、ここが対外貿易の唯一の窓口でした。とても小さな港ですが、外のものはすべてここを通って入ってきました。

## ダウンロード

[Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest) から `Dejima-<バージョン>.dmg` を取得します。開いたら自分の macOS に合うフォルダを選び、中の `Dejima.app` を隣の Applications にドラッグしてください。

| フォルダ | 対象 |
|---|---|
| `macOS 15-25` | macOS 15 〜 25 |
| `macOS 26+` | macOS 26 以降 |

間違えても問題ありません。要件を満たさないビルドは macOS が起動を拒否し、どちらが必要かを表示します。

2つのビルドは機能が同じで、違うのは翻訳セッションをシステムからどう受け取るかだけです。macOS 26 の API は直接生成できるため、画面の隅に居座る隠しウィンドウが不要になります。その代わり、言語パックが未導入のときはシステムのダウンロードダイアログではなくエラーになります。bundle ID は共通なので、乗り換えてもアクセシビリティの許可、ログイン項目、設定はそのまま引き継がれます。

このほかに、⌘C を監視するためのアクセシビリティ権限が必要です。任意の推敲機能には Apple Intelligence と macOS 26 以降が別途必要です。

## 初回起動

**1. アクセシビリティ権限を与える。** 権限がない状態で起動すると案内ウィンドウが出ます。ボタンでアクセシビリティのパネルを開き、ウィンドウ内の Dejima アイコンを**そのままリストへドラッグ**してスイッチを入れてください。

ドラッグされるのは実行中のバンドルそのものなので、別のものを追加してしまう余地がありません。この許可は特定のバンドルに結びついており、エイリアスや Downloads に残った別のコピーを追加しても、見かけ上は登録されたのに何も起きません。まだ Applications の外にある場合は、先に移動するよう案内ウィンドウが警告します。あとから移動すると許可が無効になるためです。

スイッチを入れると案内ウィンドウは自動的に閉じ、監視がすぐ有効になります。通常は再起動不要です。もう一度開くには、メニューバーアイコン → `Grant Accessibility access…`。

**2. 言語モデルをダウンロードする。** メニューの `Check language models…` でシステム設定の「翻訳言語」パネルが開きます。使う言語をそれぞれ1つ落としておきます。1言語あたり 1〜3 GB です。

モデルがない状態で翻訳すると、初回にシステムのダウンロードダイアログが出ます。ただしホストウィンドウが不可視なので、出る位置も挙動も少し妙になりがちです。先に落としておくのをおすすめします。

**3. 試す。** 適当な外国語の一文を選んで ⌘C を2回。

## 翻訳の方向

メニューの設定は2つだけですが、日常の2場面をこれで賄えます。

| 判定された言語 | 訳先 |
|---|---|
| 日本語 / 英語 / その他すべて | 主言語（既定：簡体中国語） |
| 主言語そのもの | 副言語（既定：日本語） |
| 判定できなかった | 主言語。原文の言語はフレームワークに推測させます |

つまり日本語と英語はどちらも中国語になり、中国語は日本語になります。論文を読むときも返信を書くときも、設定に触らずに済みます。

言語判定は `NLLanguageRecognizer` です。短い文に対する推測は信用できないので、確信度が 0.4 を超えるか、文字数が 12 を超える場合にのみ判定を採用します。方向の判定上、`zh-Hans` と `zh` は同じ言語として扱います。選べる言語は `LanguageRouter.choices` にあり、現在は簡体・繁体中国語、日本語、英語、韓国語、ドイツ語、フランス語、スペイン語、ロシア語です。好みで増減してください。

パネルにはコピーボタンがあります。閉じるときはパネルの外をクリックするか Esc。

## 表示言語

システムの言語に従います。日本語、簡体中国語、英語の3つで、専用の設定項目はなく、それ以外の言語では英語になります。翻訳される内容そのものとは無関係です。そちらは上の翻訳方向で決まります。

## 通信について

**翻訳した内容がこの端末から出ることはありません。** 翻訳はローカルの Translation フレームワーク、推敲はオンデバイスの Apple Intelligence で、どちらも通信しません。

アプリ全体で通信するのは1か所だけ、更新確認です。GitHub の releases API に最新のバージョン番号を尋ねます。

- `Check for updates…` は選んだときに1回だけ送ります
- `Check for updates automatically` は**既定でオフ**。オンにすると起動時、1日1回までの確認になります
- リクエストには HTTP そのもの以外何も乗りません。識別子も、利用状況も、まして翻訳したテキストも送りません

コードは `Sources/Updater.swift`、180行足らずです。不要なら両方オフのままにするか、ファイルごと削除してください。

## ビルド

Xcode 16 以降と XcodeGen が必要です。

```bash
brew install xcodegen   # 未インストールなら
xcodegen generate
open Dejima.xcodeproj
```

スキーム選択に `Dejima` と `Dejima26` が並ぶので、どちらかを選んで ⌘R。コマンドラインなら：

```bash
xcodebuild -scheme Dejima   -configuration Release build   # macOS 15+
xcodebuild -scheme Dejima26 -configuration Release build   # macOS 26+
```

`Dejima26` の生成物が `Dejima26.app` という名前なのは、2つのターゲットが互いを上書きしないためだけです。パッケージ時に `Dejima.app` に戻されます。

`project.yml` の `DEVELOPMENT_TEAM` は作者自身の Team ID です。自分のものに差し替えるか、Signing & Capabilities で「Sign to Run Locally」に変えてください。**署名は固定の ID を使うのが楽です。** アクセシビリティの許可は bundle ID とコード署名に紐づくため、アドホック署名だとビルドし直すたびに権限が外れます。

XcodeGen なしで手動で作る場合：

1. Xcode → New Project → macOS → App、Interface は SwiftUI、名前は `Dejima`
2. 自動生成された `ContentView.swift` と `DejimaApp.swift` を削除
3. `Sources/` 直下のファイル、`Localizable.xcstrings`、`InfoPlist.xcstrings`、`Assets.xcassets` と、`TranslationLegacy/` か `Translation26/` の**どちらか一方**をドラッグで追加（それぞれ macOS 15 用と 26 用）
4. Target → Info に `Application is agent (UIElement)` = `YES` を追加
5. Target → Signing & Capabilities で **App Sandbox を削除**（サンドボックスとグローバルなキー監視は両立しません）

## 配布用のパッケージ

```bash
CODE_SIGN_IDENTITY="Developer ID Application: 名前 (TEAMID)" \
NOTARY_PROFILE=dejima \
./Scripts/release.sh
```

`dist/Dejima-<バージョン>.dmg` ができます。必要な macOS ごとにフォルダが分かれ、それぞれに `Dejima.app` と Applications のエイリアスが入っています。

```
Dejima 0.2.0
├── macOS 15-25/
│   ├── Dejima.app
│   └── Applications →
├── macOS 26+/
│   ├── Dejima.app
│   └── Applications →
└── Read Me.txt
```

どちらも `Dejima.app` という名前で、区別するのはフォルダ名です。そのため `/Applications` にバージョン番号付きの名前が残りません。

**署名は必須です。** プロジェクトが既定で使う Apple Development 証明書は自分の Mac でしか動かず、ダウンロードした人の環境では Gatekeeper に弾かれます。公開配布には Developer ID Application 証明書と公証が必要です。公証用の資格情報は一度だけ保存しておきます。

```bash
xcrun notarytool store-credentials dejima \
  --apple-id you@example.com --team-id TEAMID --password <アプリ用パスワード>
```

この2つの環境変数なしでも実行できますが、できるのは自分だけが開ける DMG です。その旨はスクリプトの最後に表示されます。

**リリースごとに** `project.yml` の `MARKETING_VERSION` を上げ（2つのターゲットは同じテンプレートを共有します）、`v0.1.0` の形式でタグを打ってください。更新確認はバンドル内のバージョンと比較します。

## コード構成

| ファイル | 役割 |
|---|---|
| `DejimaApp` | `@main` のエントリポイント、`MenuBarExtra` |
| `Controller` | `AppDelegate` と全体の配線：権限、監視の切り替え、翻訳処理の進行管理 |
| `DoubleCopyMonitor` | グローバルなキー監視、二度押し判定、クリップボード読み取り |
| `LanguageRouter` | 言語判定と翻訳方向の決定 |
| `TranslationLegacy/TranslationHub` | macOS 15 版。Apple のビュー束縛 API を素の `async` 関数に包む。隠しホストウィンドウもここ |
| `Translation26/TranslationHub` | macOS 26 版。セッションを直接生成する。対外 API は同じ、ウィンドウなし |
| `Polisher` | 任意の Apple Intelligence による推敲 |
| `PermissionGuide` | アクセシビリティ権限の案内ウィンドウ。アイコンをドラッグできる |
| `TextCleaner` | PDF からのコピーで入る強制改行の修復 |
| `LoginItem` | ログイン時の自動起動 |
| `Updater` | 更新確認。アプリ内で唯一の通信箇所 |
| `ResultPanel` | `ResultModel` とフォーカスを奪わないフローティングパネル |
| `ResultView` | パネルの中身：訳文を上、原文を下に |
| `MenuBarView` | メニューの中身 |
| `DejimaMark` | 出の字のマーク。メニューバーのアイコンでもある |

`Scripts/` にはアプリアイコン（`app-icon.swift`）、DMG のウィンドウ背景とレイアウト（`dmg-window.swift`）、パッケージ用スクリプト（`release.sh`）があります。

## 追加を検討しているもの

- 用語集。特定の語の訳を固定し、推敲の instructions に渡す
- 「Refine with Apple Intelligence」を安定させること。Apple の NMT モデルは速くてオフラインですが、技術文書や学術的な文章の調子を平板にしてしまいます。これを有効にすると、オンデバイスの LLM が原文と下訳の両方を受け取り、用語と言い回しを直します。固有名詞、遺伝子名・タンパク質名、化学名、単位、文献引用は原文どおり残すよう指示しています。依然オフラインで、1秒ほど遅くなる程度、失敗すれば黙って下訳に戻ります——ただし結果がまだ安定しないため、既定はオフです

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。

## 参考

- WWDC24「Meet the Translation API」——`translationTask` と `Configuration.invalidate()` についての公式の説明
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) —— 同じフレームワークを使ったオープンソースのスクリーンショット翻訳。モデルのダウンロード処理の作りが参考になります
