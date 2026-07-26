# Design QA — 初回オンボーディング

## 比較対象

- Visual source of truth: `/Users/inoueharuto/.codex/generated_images/019f8e69-180d-7d72-8142-e54cd82f1037/exec-19a6b4fc-aee4-40f0-a6aa-e5780d3b3c42.png`
- Final implementation capture: `/var/folders/mz/4fhw_zq956j6_j96pxrbf3880000gn/T/screenshot_optimized_b40a86cf-8a5c-4ce4-baea-eb2f10432fb2.jpg`
- Full comparison: `/private/tmp/locationwake-onboarding-comparison-final.jpg`
- Focused comparison: `/private/tmp/locationwake-onboarding-focused-final.jpg`
- Normalized reference: `/private/tmp/locationwake-onboarding-reference-normalized.jpg`
- Normalized implementation: `/private/tmp/locationwake-onboarding-implementation-final.jpg`

## 比較条件

- Device / OS: iPhone 17 Simulator / iOS 26.5
- App state: 初回オンボーディングの導入画面、権限ダイアログ未表示、ライトモード、文字サイズ Large
- 参照画像: 852 × 1786 px。実装と同じ縦横比に中央トリミングして 822 × 1786 px とし、Lanczos で 368 × 800 px へ縮小
- 実装画像: 368 × 800 px のまま使用
- Full comparison output: 756 × 834 px
- SwiftUI ネイティブ画面のため CSS pixel は該当せず、同一の最終ピクセル寸法と同一画面状態で比較

## 最終判定

- P0: なし
- P1: なし
- P2: なし
- P3: 修正必須の項目なし

許容した差分:

- 参照画像の副操作「まず使ってみる」は、ユーザー指定により削除し、最初の操作を「準備を始める」だけにした。
- Dynamic Island とステータスバーは Simulator / iOS のシステム表示をそのまま使用した。
- ピンは独自描画ではなく SF Symbols、CTA は semantic tint を使用し、Apple 純正らしさとアクセシビリティを優先した。

## Fidelity checklist

- Typography: SF Pro の system font、ウェイト、行数、見出し階層を確認。標準文字サイズでは主見出しが1行に収まる。
- Spacing / layout: ヒーロー、見出し、説明、3要素フロー、準備カード、CTA の上下関係と余白を参照画像に合わせた。
- Color: 背景、secondary text、semantic tint、カード面、コントラストをライト・ダーク・高コントラストで確認した。
- Icon / image fidelity: すべて SF Symbols を使用し、ぼやけ・引き伸ばし・代替テキスト記号はない。
- Copy: ユーザー指定で削除した副操作以外は、導入目的と権限前説明を維持した。
- Interaction: 「準備を始める」から説明付きの位置情報ステップへ遷移し、遷移後は先頭へスクロールして見出しへフォーカスする。
- Accessibility: 最大 Dynamic Type では3要素フローを縦配置へ切り替え、ヒーローを上限サイズに抑制。CTA と全説明へスクロールで到達できる。

## 比較履歴

1. Pass 1
   - Findings: ヒーローと各アイコンが小さい、主見出しが不自然に折り返す、説明カードの視覚階層が弱い。
   - Fixes: ヒーローを106ptへ拡大、標準サイズで見出しを1行に調整、アイコンフレームとカード表現を強化。
   - Evidence: `/private/tmp/locationwake-onboarding-comparison-pass1.jpg`
2. Pass 2
   - Findings: ヒーロー右上のチェックバッジが小さく、中央のピンが濃すぎる。
   - Fixes: バッジをヒーロー比40%へ調整し、ピンを secondary color に変更。
   - Evidence: `/private/tmp/locationwake-onboarding-comparison-pass2.jpg`
3. Pass 3
   - Findings: 中央ピンの線が細く、他の要素より視認性が低い。
   - Fixes: `mappin.circle.fill` に戻し、semantic secondary color を維持。
   - Evidence: `/private/tmp/locationwake-onboarding-comparison-pass3.jpg`
4. Final
   - Full comparison と focused comparison の双方で、修正が必要な可視差分なし。
   - Evidence: `/private/tmp/locationwake-onboarding-comparison-final.jpg`, `/private/tmp/locationwake-onboarding-focused-final.jpg`

## 追加状態の確認

- ダークモード・最大 Dynamic Type・コントラストを上げる設定で、導入画面の最上部と最下部を確認。
- 「準備を始める」実行後の位置情報説明画面を同じ設定で確認。
- 大きな文字で説明カードを縦配置にし、次ステップが先頭から表示されるよう修正済み。
- 標準設定へ戻した後に再ビルド・再撮影し、最終比較を実施済み。

## Implementation checklist

- [x] 初回画面の CTA は「準備を始める」のみ
- [x] システム権限ダイアログの前に理由を説明
- [x] ライト / ダーク / 高コントラストに対応
- [x] Dynamic Type と VoiceOver フォーカス遷移に対応
- [x] 主要操作は44pt以上
- [x] 参照画像と同一状態・同一ピクセル寸法で反復比較
- [x] P0〜P2の未解決項目なし

final result: passed
