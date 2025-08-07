# Release Engineering Documentation

## Overview

This document describes the release pipeline setup for MyCodeAssistant, including code signing, notarization, and TestFlight distribution.

## Components

### 1. Code Signing Configuration

- **AppStoreRelease.xcconfig**: Configuration file for App Store distribution
  - Production bundle IDs
  - Code signing settings
  - Developer ID certificates

### 2. Notarization Script

- **Scripts/notarize.sh**: Handles Apple notarization process
  - Creates ZIP for notarization
  - Submits to Apple for notarization
  - Staples ticket to app
  - Creates signed installer package (.pkg)

### 3. CI/CD Pipeline

- **Nightly Release Workflow** (.github/workflows/nightly-release.yml)
  - Runs daily at 2 AM UTC
  - Archives and signs the application
  - Notarizes the build
  - Uploads to TestFlight
  - Creates GitHub releases

## Setup Requirements

### Required Secrets in GitHub

Configure these secrets in your GitHub repository settings:

1. **BUILD_CERTIFICATE_BASE64**: Base64-encoded p12 certificate for code signing
2. **P12_PASSWORD**: Password for the p12 certificate
3. **BUILD_PROVISION_PROFILE_BASE64**: Base64-encoded provisioning profile
4. **KEYCHAIN_PASSWORD**: Password for temporary keychain
5. **TEAM_ID**: Apple Developer Team ID
6. **NOTARIZATION_APPLE_ID**: Apple ID for notarization
7. **NOTARIZATION_PASSWORD**: App-specific password for notarization
8. **INSTALLER_CERT_NAME**: Developer ID Installer certificate name
9. **APP_STORE_CONNECT_API_KEY_ID**: App Store Connect API Key ID
10. **APP_STORE_CONNECT_ISSUER_ID**: App Store Connect Issuer ID
11. **APP_STORE_CONNECT_API_KEY_BASE64**: Base64-encoded API key

### Local Setup

1. Install Xcode 15.0 or later
2. Install required certificates in Keychain
3. Download provisioning profiles from Apple Developer Portal

## Manual Release Process

### Building for Distribution

```bash
# 1. Archive the application
xcodebuild -project MyCodeAssistant.xcodeproj \
  -scheme MyCodeAssistantHost \
  -configuration AppStore \
  -archivePath ./MyCodeAssistant.xcarchive \
  archive

# 2. Export the archive
xcodebuild -exportArchive \
  -archivePath ./MyCodeAssistant.xcarchive \
  -exportPath ./export \
  -exportOptionsPlist Scripts/ExportOptions.plist
```

### Notarization

```bash
# Set environment variables
export NOTARIZATION_APPLE_ID="your-apple-id@example.com"
export NOTARIZATION_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="XXXXXXXXXX"
export CREATE_INSTALLER="true"
export INSTALLER_CERT_NAME="Developer ID Installer: Your Name (XXXXXXXXXX)"

# Run notarization script
./Scripts/notarize.sh ./export/MyCodeAssistantHost.app ./Releases
```

### TestFlight Upload

```bash
# Using altool
xcrun altool --upload-app \
  --type macos \
  --file ./Releases/MyCodeAssistantHost.pkg \
  --apiKey "YOUR_API_KEY_ID" \
  --apiIssuer "YOUR_ISSUER_ID"
```

## Automated Release Process

The CI/CD pipeline automatically:

1. **Nightly Builds**: Runs every night at 2 AM UTC
2. **On-Demand**: Can be triggered manually via GitHub Actions
3. **Process**:
   - Increments build number
   - Archives application
   - Signs with distribution certificates
   - Notarizes with Apple
   - Creates installer package
   - Uploads to TestFlight
   - Creates GitHub release

## Troubleshooting

### Common Issues

1. **Notarization Failures**
   - Check Apple ID credentials
   - Verify app-specific password is valid
   - Ensure hardened runtime is enabled

2. **Code Signing Issues**
   - Verify certificates are not expired
   - Check provisioning profiles match bundle IDs
   - Ensure Team ID is correct

3. **TestFlight Upload Failures**
   - Verify App Store Connect API credentials
   - Check bundle version hasn't been used
   - Ensure app passes validation

### Debug Commands

```bash
# Check code signing
codesign -dv --verbose=4 MyCodeAssistantHost.app

# Verify notarization
xcrun stapler validate MyCodeAssistantHost.app

# Test installer package
sudo installer -pkg MyCodeAssistantHost.pkg -target /
```

## Release Checklist

- [ ] Update version number in Info.plist
- [ ] Update CHANGELOG.md
- [ ] Run full test suite
- [ ] Verify code signing certificates
- [ ] Check provisioning profiles
- [ ] Test notarization locally
- [ ] Trigger CI/CD pipeline
- [ ] Verify TestFlight build
- [ ] Test installation on clean system
- [ ] Submit for App Store review (if applicable)

## Security Notes

- Never commit certificates or passwords to repository
- Use GitHub secrets for sensitive information
- Rotate app-specific passwords regularly
- Keep certificates and profiles up to date

## Support

For issues with the release pipeline:
1. Check GitHub Actions logs
2. Review notarization logs in Apple Developer portal
3. Verify all secrets are correctly configured
4. Ensure certificates haven't expired

## Version History

- v1.0.0 - Initial release pipeline setup