.PHONY: help build lint test check app install-local
help: ## 使用可能なコマンドを表示
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "%-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
build: ## Swift パッケージをビルド
	swift build
lint: ## Swift の書式とシェルの構文を検査
	swift format lint --strict --recursive Sources App WidgetExtension Tests
	bash -n scripts/install-local.sh
test: ## 自動テストを実行
	swift test
check: lint build test ## 標準検証を実行
app: ## ローカル実行用のアドホック署名済みアプリを作成
	xcodegen generate
	xcodebuild -project T3UsageWidget.xcodeproj -scheme T3Usage -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO -quiet
	codesign --force --sign - --entitlements Config/Widget.entitlements build/Build/Products/Release/T3Usage.app/Contents/PlugIns/T3UsageWidgetExtension.appex
	codesign --force --sign - --entitlements Config/App.entitlements build/Build/Products/Release/T3Usage.app
	codesign --verify --deep --strict build/Build/Products/Release/T3Usage.app
install-local: ## 起動中でないことを確認し、以前のアプリを退避して配置
	./scripts/install-local.sh
