APP_NAME     = VibePaper
BUNDLE_ID    = com.vibepaper.app
VERSION      = 1.0.0
BUILD_DIR    = .build/release
APP_BUNDLE   = $(APP_NAME).app
DMG_NAME     = $(APP_NAME)-$(VERSION).dmg
SIGN_IDENTITY ?= -   # 替换为 "Developer ID Application: Your Name (TEAMID)" 进行正式签名

.PHONY: all build bundle sign dmg clean

## 完整发布流程
all: build bundle sign dmg

## Release 构建
build:
	swift build -c release

## 打包 .app bundle
bundle: build
	@echo "→ 打包 $(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@cp Resources/VibePaper.entitlements $(APP_BUNDLE)/Contents/Resources/
	@echo "✓ $(APP_BUNDLE) 创建完成"

## 代码签名（需设置 SIGN_IDENTITY）
sign: bundle
	@echo "→ 代码签名 ($(SIGN_IDENTITY))"
	codesign --force --deep --options runtime \
	  --entitlements Resources/VibePaper.entitlements \
	  --sign "$(SIGN_IDENTITY)" \
	  $(APP_BUNDLE)
	@echo "✓ 签名完成"

## 创建 DMG
dmg: bundle
	@echo "→ 创建 $(DMG_NAME)"
	@rm -f $(DMG_NAME)
	hdiutil create -volname "$(APP_NAME)" \
	  -srcfolder $(APP_BUNDLE) \
	  -ov -format UDZO \
	  $(DMG_NAME)
	@echo "✓ $(DMG_NAME) 创建完成"

## 公证（需已签名，替换 APPLE_ID 和 TEAM_ID）
notarize: dmg
	xcrun notarytool submit $(DMG_NAME) \
	  --apple-id "$(APPLE_ID)" \
	  --team-id "$(TEAM_ID)" \
	  --password "$(APP_PASSWORD)" \
	  --wait
	xcrun stapler staple $(DMG_NAME)

## 快速本地测试运行（无需打包）
run:
	swift run

clean:
	@rm -rf $(APP_BUNDLE) $(DMG_NAME) .build
	@echo "✓ 清理完成"
