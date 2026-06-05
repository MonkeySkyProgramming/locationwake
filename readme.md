# locationwake

`locationwake` は、指定した場所に到着したときに通知・サウンド・バイブレーションで知らせる iOS アプリです。アプリ表示名は `起きなはれ` です。

## 目的

電車やバスでの移動中など、目的地付近に着いたタイミングでユーザーを起こす、または気づかせることを目的とします。時間ではなく位置情報を基準にアラームを発火します。

## 対象ユーザー

- 公共交通機関で移動中に目的地で起きたいユーザー
- 移動中に特定地点への到着を忘れたくないユーザー
- 通知音だけでなく、バイブレーションでも気づきたいユーザー

## 要件定義

### 機能要件

#### アラーム一覧

- 保存済みの位置アラームを一覧表示できること。
- 各アラームの名称、有効状態、サウンド、バイブレーション、繰り返し曜日を確認できること。
- アラームごとに有効・無効を切り替えられること。
- アラームを削除できること。
- 初回データがない場合はサンプルアラームを作成できること。

#### 位置選択

- 場所名で検索できること。
- 検索結果を地図とリストで表示できること。
- 検索結果からアラーム対象地点を選択できること。

#### アラーム設定

- アラーム名を設定できること。
- 対象地点の緯度・経度を保持できること。
- 通知半径を設定できること。
- アラーム音を選択できること。
- アラーム音のオン・オフを切り替えられること。
- バイブレーションのオン・オフを切り替えられること。
- 繰り返し曜日を設定できること。
- 保存したアラームは永続化されること。

#### 位置監視

- アプリは保存済みアラームの地点をジオフェンスとして監視できること。
- ユーザーが監視範囲に入った場合、対象アラームを発火できること。
- 繰り返し曜日が設定されている場合、当日の曜日が対象外なら発火しないこと。
- 一度発火したアラームは、ユーザーが範囲外に出るまで再発火しないこと。
- 単発アラームは発火後に無効化されること。
- 範囲外に出た場合、再入室時に再発火できる状態へ戻せること。

#### 通知・音・バイブレーション

- 位置到着時にローカル通知を表示できること。
- アラーム音が有効な場合、選択した mp3 ファイルを再生できること。
- バイブレーションが有効な場合、繰り返し振動できること。
- アプリがアクティブになったとき、音とバイブレーションを停止できること。

#### 設定

- デフォルト半径を設定できること。
- アラーム音の既定オン・オフを設定できること。
- ヘルプを再表示できること。
- 通知設定、位置情報設定へ遷移できること。
- アラーム音とバイブレーションをテストできること。
- 問い合わせメールを開けること。

#### オンボーディング

- 初回起動時に使い方を表示できること。
- ヘルプから再表示できること。

#### 広告

- 画面下部に AdMob バナー広告を表示できること。
- ATT 許可リクエストを行えること。

### 非機能要件

- iOS 18.0 以降を対象とすること。
- iPhone を主対象とすること。
- バックグラウンドでも位置監視が継続できること。
- 位置情報は「常に許可」を前提にすること。
- 通知許可が必要な場合はユーザーに案内すること。
- アラーム情報は端末内に保存し、外部サーバーへ送信しないこと。
- 位置監視、通知、音声、バイブレーションの副作用はテスト時に抑制できる設計にすること。
- 主要な判定ロジックは単体テストで検証できること。

## データ要件

### Alarm

| 項目 | 型 | 説明 |
| --- | --- | --- |
| `id` | `String` | アラーム識別子 |
| `name` | `String` | 表示名、通知識別にも利用 |
| `repeatWeekdays` | `[Int]?` | 繰り返し曜日。日曜 0、土曜 6 |
| `sound` | `String` | mp3 ファイル名 |
| `isAlarmEnabled` | `Bool` | アラームの有効状態 |
| `isSoundEnabled` | `Bool` | 音の有効状態 |
| `isVibrationEnabled` | `Bool` | バイブレーションの有効状態 |
| `location` | `Location?` | 対象地点 |
| `radius` | `Double?` | 監視半径 |
| `hasTriggered` | `Bool` | 発火済み状態 |
| `hasTriggeredUntilExit` | `Bool` | 範囲外に出るまで再発火を禁止する状態 |

### Location

| 項目 | 型 | 説明 |
| --- | --- | --- |
| `latitude` | `Double` | 緯度 |
| `longitude` | `Double` | 経度 |

### 永続化

- `UserDefaults` の `SavedAlarms` に JSON エンコードした `[Alarm]` を保存します。
- 初回起動フラグは `hasSeenOnboarding` を使用します。
- 保存直後の即時発火抑制には `SkipTrigger_*` と `SkipTriggerAt_*` を使用します。

## 画面構成

- `AlarmListSwiftUIView`: アラーム一覧
- `LocationSelectionView`: 目的地検索・選択
- `AlarmDetailView`: アラーム作成・編集
- `SoundSelectionView`: サウンド選択
- `RepeatWeekdaySelectionView`: 繰り返し曜日選択
- `SettingView`: 設定
- `OnboardingView`: 使い方表示
- `BaseContainerView`: 共通コンテナ、広告、ヘルプ導線

## 技術構成

- Swift
- SwiftUI
- UIKit lifecycle
- CoreLocation
- MapKit
- UserNotifications
- AVFoundation
- AudioToolbox
- Google Mobile Ads SDK
- XCTest

## セットアップ

1. Xcode で `locationwake.xcworkspace` を開きます。
2. 依存関係が解決されていない場合は、Xcode の package resolution または CocoaPods の `pod install` を実行します。
3. Scheme は `locationwake` を選択します。
4. iOS Simulator または実機でビルドします。

## テスト

unit test target は iOS 18.0 以降を対象にしています。

```sh
xcodebuild test \
  -workspace locationwake.xcworkspace \
  -scheme locationwake \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:locationwakeTests
```

現在追加されている単体テストは以下を検証します。

- `Alarm` の旧データ互換デコード
- `Alarm` の JSON round-trip
- trigger 状態と vibration 状態の保持
- `NavigationRoute` の id ベース等価判定

## 既知の課題

- `AlarmScheduler.scheduleAlarm` は通知リクエストを登録していません。
- `AlarmScheduler.cancelAlarm` はランダム UUID を指定しているため、既存通知を正しく削除できません。
- `LocationManager` の初期化時に権限要求、通知許可、位置更新、タイマー開始が走るため、テストと UI test が重く不安定になりやすいです。
- `LocationManager.addGeofences` は現状 `isAlarmEnabled` を見ずに監視登録します。
- `triggerAlarm` が通知、音声、バイブレーション、永続化、監視再登録をまとめて持っており、単体テストしづらいです。
- `HapticManager.triggerRepeated` に非常に大きい回数を渡すと、停止漏れ時に振動が続きます。
- `AppDelegate` と `SceneDelegate` の両方で root UI を構築しており、起動経路が分かりづらいです。
- UIKit 版の旧 Controller/View ファイルは全行コメントアウトされており、削除または復活方針の決定が必要です。
- SwiftUI の Map API と `onChange` に iOS 17 以降の非推奨警告があります。
- `AdMobID` が広告ユニット ID をランダム選択しており、再現性がありません。

## 今後の改善方針

1. テスト時に位置情報・通知・広告・音声の副作用を止められる起動オプションを追加する。
2. `AlarmScheduler` を alarm ID ベースで実装し、通知登録・削除をテストする。
3. 無効アラームを geofence 登録しないようにする。
4. 発火判定を `AlarmTriggerPolicy` として切り出し、曜日、発火済み、保存直後スキップを単体テストする。
5. `LocationManager` から永続化、通知、音声、バイブレーションの責務を段階的に分離する。
6. 旧 UIKit ファイル、警告、AdMob ID 選択ロジックを別作業で整理する。
