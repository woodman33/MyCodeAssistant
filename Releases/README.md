# Release Distribution

This directory is intended for signed and notarized release builds of MyCodeAssistant.

## Current Status

**No signed releases available yet** - Developer ID certificates required.

## Release Process (When Certificates Available)

### Prerequisites
- Apple Developer Program membership
- Developer ID Application certificate installed in Keychain
- App-specific password for notarization
- Xcode command line tools

### Build Steps

1. **Archive the application**
   ```bash
   xcodebuild archive \
     -scheme MyCodeAssistantHost \
     -archivePath ./build/MyCodeAssistant.xcarchive \
     CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME" \
     DEVELOPMENT_TEAM="YOUR_TEAM_ID"
   ```

2. **Export for distribution**
   ```bash
   xcodebuild -exportArchive \
     -archivePath ./build/MyCodeAssistant.xcarchive \
     -exportPath ./Releases/v1.1.0 \
     -exportOptionsPlist ExportOptions.plist
   ```

3. **Notarize the app**
   ```bash
   xcrun notarytool submit ./Releases/v1.1.0/MyCodeAssistantHost.app \
     --apple-id "your-apple-id@example.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password" \
     --wait
   ```

4. **Staple the notarization**
   ```bash
   xcrun stapler staple ./Releases/v1.1.0/MyCodeAssistantHost.app
   ```

5. **Create DMG installer**
   ```bash
   hdiutil create -volname "MyCodeAssistant" \
     -srcfolder ./Releases/v1.1.0/MyCodeAssistantHost.app \
     -ov -format UDZO ./Releases/MyCodeAssistant-v1.1.0.dmg
   ```

6. **Sign the DMG**
   ```bash
   codesign --force --sign "Developer ID Application: YOUR_NAME" \
     ./Releases/MyCodeAssistant-v1.1.0.dmg
   ```

7. **Notarize the DMG**
   ```bash
   xcrun notarytool submit ./Releases/MyCodeAssistant-v1.1.0.dmg \
     --apple-id "your-apple-id@example.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password" \
     --wait
   ```

8. **Staple the DMG**
   ```bash
   xcrun stapler staple ./Releases/MyCodeAssistant-v1.1.0.dmg
   ```

## Release Checklist

- [ ] Update version number in project settings
- [ ] Update CHANGELOG.md
- [ ] Create git tag for release
- [ ] Build and archive with proper signing
- [ ] Export for Developer ID distribution
- [ ] Notarize the application
- [ ] Create DMG installer
- [ ] Sign and notarize DMG
- [ ] Upload to GitHub Releases
- [ ] Update README with download links

## Directory Structure

```
Releases/
├── README.md (this file)
├── v1.1.0/
│   ├── MyCodeAssistantHost.app (signed & notarized)
│   └── ReleaseNotes.md
└── MyCodeAssistant-v1.1.0.dmg (signed & notarized)
```

## Download Links

Once releases are available, they will be published to:
https://github.com/woodman33/MyCodeAssistant/releases

## Verification

Users can verify the notarization status:
```bash
spctl -a -vvv -t install MyCodeAssistantHost.app
# Should output: MyCodeAssistantHost.app: accepted
```

## Support

For issues with signed releases, please open an issue on GitHub.