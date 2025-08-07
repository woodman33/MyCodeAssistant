#!/bin/bash

# Notarization Script for MyCodeAssistant
# This script handles the notarization process for macOS apps
# Run as Xcode Archive post-action or in CI/CD pipeline

set -euo pipefail

# Configuration
BUNDLE_ID="${BUNDLE_ID:-com.mycodeassistant.app}"
TEAM_ID="${TEAM_ID:-XXXXXXXXXX}"
APP_PATH="${1:-}"
OUTPUT_PATH="${2:-./Releases}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check required environment variables
check_environment() {
    if [ -z "${NOTARIZATION_APPLE_ID:-}" ]; then
        log_error "NOTARIZATION_APPLE_ID environment variable is not set"
        exit 1
    fi
    
    if [ -z "${NOTARIZATION_PASSWORD:-}" ]; then
        log_error "NOTARIZATION_PASSWORD environment variable is not set"
        exit 1
    fi
    
    if [ -z "$APP_PATH" ]; then
        log_error "App path not provided"
        echo "Usage: $0 <app-path> [output-path]"
        exit 1
    fi
    
    if [ ! -d "$APP_PATH" ]; then
        log_error "App not found at: $APP_PATH"
        exit 1
    fi
}

# Create ZIP for notarization
create_zip() {
    local app_name=$(basename "$APP_PATH" .app)
    local zip_path="$OUTPUT_PATH/${app_name}.zip"
    
    log_info "Creating ZIP archive for notarization..."
    mkdir -p "$OUTPUT_PATH"
    
    # Use ditto to preserve permissions and extended attributes
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$zip_path"
    
    if [ $? -eq 0 ]; then
        log_info "ZIP created: $zip_path"
        echo "$zip_path"
    else
        log_error "Failed to create ZIP"
        exit 1
    fi
}

# Submit for notarization
submit_for_notarization() {
    local zip_path="$1"
    local request_uuid=""
    
    log_info "Submitting app for notarization..."
    
    # Submit using notarytool (Xcode 13+)
    result=$(xcrun notarytool submit "$zip_path" \
        --apple-id "$NOTARIZATION_APPLE_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1)
    
    # Extract submission ID
    request_uuid=$(echo "$result" | grep -E "id: [a-f0-9-]+" | head -1 | awk '{print $2}')
    
    if [ -z "$request_uuid" ]; then
        log_error "Failed to get submission ID"
        echo "$result"
        exit 1
    fi
    
    log_info "Submission ID: $request_uuid"
    
    # Check if notarization was successful
    if echo "$result" | grep -q "status: Accepted"; then
        log_info "Notarization successful!"
        echo "$request_uuid"
    else
        log_error "Notarization failed or is still in progress"
        echo "$result"
        
        # Try to get the log for debugging
        log_info "Fetching notarization log..."
        xcrun notarytool log "$request_uuid" \
            --apple-id "$NOTARIZATION_APPLE_ID" \
            --password "$NOTARIZATION_PASSWORD" \
            --team-id "$TEAM_ID"
        
        exit 1
    fi
}

# Staple the notarization ticket
staple_app() {
    local app_path="$1"
    
    log_info "Stapling notarization ticket to app..."
    
    xcrun stapler staple "$app_path"
    
    if [ $? -eq 0 ]; then
        log_info "Successfully stapled ticket to: $app_path"
    else
        log_error "Failed to staple ticket"
        exit 1
    fi
}

# Create installer package
create_installer_package() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local pkg_path="$OUTPUT_PATH/${app_name}.pkg"
    local temp_pkg="$OUTPUT_PATH/${app_name}-unsigned.pkg"
    
    log_info "Creating installer package..."
    
    # Build the package
    pkgbuild --component "$app_path" \
        --install-location "/Applications" \
        --identifier "$BUNDLE_ID" \
        --version "1.0.0" \
        "$temp_pkg"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create package"
        exit 1
    fi
    
    # Sign the package with Developer ID Installer certificate
    if [ -n "${INSTALLER_CERT_NAME:-}" ]; then
        log_info "Signing installer package..."
        productsign --sign "$INSTALLER_CERT_NAME" \
            --timestamp \
            "$temp_pkg" \
            "$pkg_path"
        
        if [ $? -eq 0 ]; then
            rm "$temp_pkg"
            log_info "Package signed: $pkg_path"
        else
            log_error "Failed to sign package"
            exit 1
        fi
    else
        mv "$temp_pkg" "$pkg_path"
        log_warning "INSTALLER_CERT_NAME not set, package will not be signed"
    fi
    
    echo "$pkg_path"
}

# Notarize installer package
notarize_package() {
    local pkg_path="$1"
    
    log_info "Submitting package for notarization..."
    
    result=$(xcrun notarytool submit "$pkg_path" \
        --apple-id "$NOTARIZATION_APPLE_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1)
    
    if echo "$result" | grep -q "status: Accepted"; then
        log_info "Package notarization successful!"
        
        # Staple the package
        log_info "Stapling ticket to package..."
        xcrun stapler staple "$pkg_path"
        
        if [ $? -eq 0 ]; then
            log_info "Successfully stapled ticket to package"
        else
            log_warning "Failed to staple ticket to package (non-critical)"
        fi
    else
        log_error "Package notarization failed"
        echo "$result"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting notarization process..."
    
    # Check environment
    check_environment
    
    # Create ZIP and submit for notarization
    zip_path=$(create_zip)
    submission_id=$(submit_for_notarization "$zip_path")
    
    # Staple the original app
    staple_app "$APP_PATH"
    
    # Create and notarize installer package if certificate is available
    if [ -n "${CREATE_INSTALLER:-}" ] && [ "$CREATE_INSTALLER" = "true" ]; then
        pkg_path=$(create_installer_package "$APP_PATH")
        notarize_package "$pkg_path"
        log_info "Installer package ready: $pkg_path"
    fi
    
    # Clean up ZIP file
    rm -f "$zip_path"
    
    log_info "✅ Notarization process completed successfully!"
    log_info "App: $APP_PATH"
    
    if [ -n "${pkg_path:-}" ]; then
        log_info "Package: $pkg_path"
    fi
}

# Run main function
main