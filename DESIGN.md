---
version: "alpha"
name: "T3 Usage Widget"
description: "macOS desktop usage summary"
colors:
  primary: "#171717"
  secondary: "#737373"
  background: "#ffffff"
  surface: "#ffffff"
  text: "#171717"
typography:
  body:
    fontFamily: "system"
    fontSize: "14px"
    lineHeight: "1.4"
spacing:
  sm: "8px"
  md: "16px"
  lg: "24px"
rounded:
  sm: "4px"
  md: "8px"
components: {}
---

## Overview
macOS WidgetKit 上で、使用量と接続状態を簡潔に表示する。

## Visual Principles
システムの背景・文字色を用い、数値と状態を優先する。色だけで状態を伝えない。

## Accessibility
システムフォントと VoiceOver に対応し、色・ダークモードはシステム設定に従う。

## Components and Usage
SwiftUI と WidgetKit の標準コンポーネントを使う。未接続時は取得不能と表示する。

## Widget Gallery Preview
ギャラリーではサンプルであることを明記した数値を表示する。実際のウィジェットではサンプルを実データとして表示しない。

## Period Selection
ホストアプリに標準のセグメント選択を置き、ウィジェットの見出しに取得対象の期間を表示する。再取得中は前の期間の数値を現在の期間として扱わない。

## Limit Labels
小サイズでは利用上限の名前を省略しても使用率を優先して表示する。

## Widget Sizes
小サイズは上限を1件、中サイズは2件、大サイズは4件まで表示する。中・大サイズでは表示しきれない上限の件数を明記する。

## Large Widget Breakdown
大サイズは合計とプロバイダー別内訳を左、利用上限を右に配置する。長い名称が数値を隠さないよう数値を優先し、表示できない項目数を明示する。

## T3 Usage Fidelity
添付の T3 画面を視覚基準とする。明るいニュートラルな背景、黒とオレンジのプロバイダー別系列、Cost・Tokens・Limits のセグメント、日別の面グラフ、種類別の帯、Limits の残量バーとリセット表示を用いる。小さな WidgetKit サイズでは表示領域に合わせて情報を段階的に減らし、実際のデータと操作対象を明示する。

## Menu Bar
メニューバー項目からポップオーバーを開き、T3 に準じた期間・Cost・Tokens・Limits の操作と使用量の表示を行う。表示構造と色はウィジェットと共有する。

## Language Selection
メニューバーのポップオーバーに、システム追従と日本語・English・简体中文・繁體中文を選べる言語メニューを置く。添付された CCUsage の言語選択を操作の参考とし、既存の T3 可視化の構造は保つ。

## Icon Controls
Cost・Tokens・Limits、更新、言語、終了は SF Symbols を用いたアイコン操作とする。期間・数値・状態・種類別の凡例は意味を伝えるため文字を保持する。選択中の背景を区別し、各操作に翻訳済みのアクセシビリティ名とヘルプを付ける。

## App Icon
T3 本体の黒い角丸と銀色の T3 文字を踏襲し、オレンジ色の使用量グラフで本体と区別する。小さいサイズでも文字とグラフが判別できる構成とし、余白は透過する。

## 別環境の接続
ホスト画面に HTTPS 接続先と環境 ID、ペアリングコードの入力欄および接続・解除操作を設ける。コードは SecureField で表示し、接続結果と失敗を示す。

## 価格未設定
価格不明のレコードを含む推定コストには、価格未設定分を除く旨のラベルを付ける。取得エラー・スキャン不完全時の部分取得表示は維持する。

## macOS のアプリアイコン表示
Icon Composer の黒い背景と拡大した T3 Usage の図案を使い、macOS の角丸内で T3 本体に近い大きさに表示する。「このアプリについて」にも同じアイコンを使う。
