---
title: ASCでiOSビルドをアップロードする方法
aliases:
  - ASC運用手順
tags:
  - app-store-connect
  - ios
  - release
---

# ASCでiOSビルドをアップロードする方法

このプロジェクトの App Store Connect 操作は `asc` CLI で行う。対象アプリの表示名は **起きなはれ**。ブラウザでの操作は、`asc` が対応していない場合に限る。

> [!warning] 変更操作の原則
> アップロード、テスター配布、メタデータ更新、提出などの変更前には、対象と値をユーザーに示して明示的な承認を得る。破壊的なコマンドには `--confirm` を付ける。

## 1. 操作前の確認

1. 未確認のコマンドは必ず `asc --help` と対象サブコマンドの `--help` で確認する。コマンド体系や API フィールドが不明なら `asc search` または `asc schema` を使う。
2. 認証状態を確認する。

   ```sh
   asc auth status --verbose
   asc auth status --validate
   ```

   Keychain のプロファイル列挙が `-50` で失敗するときは、設定ファイルを明示して確認する。ただし、認証情報を画面・ログ・リポジトリへ出力しない。

   ```sh
   ASC_BYPASS_KEYCHAIN=1 asc auth status --validate --output json --pretty
   ```

3. `asc auth login` を使った Keychain 保存を優先する。API キー、秘密鍵、JWT、`.p8` ファイルの内容は絶対にコミットしない。
4. アプリ ID は名前から推測せず、必ず解決する。

   ```sh
   asc apps list --name "起きなはれ" --output table
   ```

   出力された ID を以後の `--app` に使う。`ASC_APP_ID` に設定する場合も、解決済みの ID に限る。

## 認証プロファイルと切り替え

この環境では Keychain がエラー `-50` で利用できないため、認証プロファイルは `~/.asc/config.json` に保存している。`ASC_BYPASS_KEYCHAIN=1` を付けて操作する。

同じシェルで続けて操作する場合は、最初に次を実行する。以降の本書の `asc` コマンドは、この設定を前提とする。

```sh
export ASC_BYPASS_KEYCHAIN=1
```

| プロファイル名 | キー ID | 用途・役割 | 使用上の注意 |
| --- | --- | --- | --- |
| `ASC API KEY(Admin)` | `43YJ5784BN` | App Store Connect の管理操作用。ビルド、TestFlight、メタデータ、リリースなど、管理権限が必要な操作に使う。 | 既定プロファイル。変更操作は必ず事前承認を得る。 |
| `ASC API KEY(Sales and Reports)` | `6B3GZHRQ8Z` | 売上・財務レポートの取得と確認用。 | アプリ設定の変更やリリース作業には使用しない。 |
| `ASC API KEY` | `G4LKFBCTTH` | App Manager。アプリ情報、ビルド、TestFlight、メタデータ、リリース運用に使う。 | 変更操作は必ず事前承認を得る。Account Holder／Admin 専用の操作には使用しない。 |

> [!warning] 権限の扱い
> API キー名は用途の目安であり、実際に許可される操作は App Store Connect で割り当てられたロールに依存する。Account Holder／Admin 専用操作が必要な場合は `ASC API KEY(Admin)` を使う。

### 既定プロファイルを切り替える

通常は Admin を既定にしておく。別のキーを使うときだけ、明示的に切り替え、完了後に Admin へ戻す。

```sh
# Sales and Reports を既定にする
ASC_BYPASS_KEYCHAIN=1 asc auth switch --name "ASC API KEY(Sales and Reports)"

# 汎用 API キーを既定にする
ASC_BYPASS_KEYCHAIN=1 asc auth switch --name "ASC API KEY"

# 作業後は Admin に戻す
ASC_BYPASS_KEYCHAIN=1 asc auth switch --name "ASC API KEY(Admin)"
```

一回のコマンドだけ別プロファイルを使う場合は、既定を変更せず `--profile` を指定する。

```sh
ASC_BYPASS_KEYCHAIN=1 asc --profile "ASC API KEY(Sales and Reports)" finance reports --help
```

現在の既定と登録済みプロファイルは次で確認する。

```sh
ASC_BYPASS_KEYCHAIN=1 asc auth status --output table
```

## ローカル実行ランナーからアップロードする

ローカル LLM や自動化プロセスからアップロードを依頼するときは、プロジェクトの `scripts/asc-upload-local.sh` を使う。ランナーは現在の既定プロファイルを信用せず、指定した `--profile` を **認証確認、アーカイブ、書き出し、アップロード、完了確認の全コマンド**へ渡す。そのため、別の API キーが既定で選択されていても、アップロード先の認証が混ざらない。

App Manager でアップロードする例:

```sh
scripts/asc-upload-local.sh \
  --profile "ASC API KEY" \
  --app-id "APP_ID" \
  --export-options "ExportOptions.plist" \
  --confirm-upload
```

実アップロード前の検証には `--dry-run` を使う。Sales and Reports はアップロード用途ではなく、レポート取得時だけ明示的に指定する。

既に IPA がある場合は `--existing-ipa` を指定すると、アーカイブと書き出しを省略して認証・アップロード準備・検証だけを確認できる。

```sh
scripts/asc-upload-local.sh \
  --profile "ASC API KEY" \
  --app-id "6736607524" \
  --existing-ipa ".asc/artifacts/locationwake-1.53-5.ipa" \
  --dry-run
```

> [!warning] ローカル LLM からの依頼
> ローカル LLM には API キー、issuer ID、秘密鍵、JWT を渡さない。LLM はプロファイル名、アプリ ID、成果物パス、`--dry-run`／`--confirm-upload` の指定だけをランナーへ渡す。実アップロードはユーザーが `--confirm-upload` を承認した場合に限る。

## 2. ビルド番号を決める

現在のマーケティングバージョンと App Store Connect 上の次のビルド番号を確認する。

```sh
asc xcode version view
asc builds next-build-number --app "APP_ID" --version "VERSION" --platform IOS --output table
```

決定したバージョンとビルド番号を確認してから、必要に応じて更新する。

```sh
asc xcode version edit --version "VERSION" --build-number "BUILD_NUMBER"
```

## 3. アーカイブと IPA 書き出し

このリポジトリでは CocoaPods ワークスペースを使う。スキーム名と `ExportOptions.plist` の内容を事前に確認し、成果物パスを固定して作成する。

```sh
asc xcode archive \
  --workspace locationwake.xcworkspace \
  --scheme locationwake \
  --configuration Release \
  --archive-path .asc/artifacts/locationwake.xcarchive \
  --output json

asc xcode export \
  --archive-path .asc/artifacts/locationwake.xcarchive \
  --export-options ExportOptions.plist \
  --ipa-path .asc/artifacts/locationwake.ipa \
  --output json
```

> [!note]
> このプロジェクトは App Store 用 provisioning profile `起きなはれ App Store 2026-07-16` と Distribution 証明書を使う。`scripts/asc-upload-local.sh` は Manual Signing と profile UUID を指定する。実際の scheme、署名設定、`ExportOptions.plist` が異なる場合は、その値に置き換える。既存の成果物を置換する必要がある場合のみ `--overwrite` を付ける。

署名時に `errSecInternalComponent` が出る場合は、login Keychain を Keychain Access でロック解除してから再実行する。秘密鍵のパスワードはチャットやログへ入力しない。

## 4. アップロードと検証

対象アプリ ID と IPA のパスを再確認し、承認後にアップロードする。

```sh
asc builds upload \
  --app "APP_ID" \
  --ipa .asc/artifacts/locationwake.ipa \
  --verify-timeout 10m \
  --wait \
  --output table
```

完了後、ビルドが処理済みであることを確認する。

```sh
asc builds info --app "APP_ID" --latest --version "VERSION" --platform IOS --output table
```

失敗時は、出力から原因を報告し、秘密情報を除外してから次の操作を提案する。承認なしに再アップロード、TestFlight 配布、審査提出は行わない。

## 5. 日常の読み取り操作

読み取りには `view` を優先し、人が確認する結果は `--output table` または `--output markdown` で表示する。全ページが必要な一覧には `--paginate` を付ける。

```sh
asc apps view --id "APP_ID" --output table
asc builds list --app "APP_ID" --paginate --output table
```
