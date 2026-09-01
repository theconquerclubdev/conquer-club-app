# update.ps1 - Simplified auto-deployment
#Requires -Version 5.0

Write-Host "🚀 Auto-deploy started..." -ForegroundColor Yellow

# Fixed version
$version = "2.0.1"

Write-Host "📌 Version: $version" -ForegroundColor Cyan

# Create version.json with YOUR Google Drive link
$json = @{
    version = $version
    apk_url = "https://drive.google.com/uc?export=download&id=1dwBLzyXqU3W0YdsQZlAZeA7Xp47IYJUY"
    changelog = "Fixed streak logic, version $version"
} | ConvertTo-Json

# Ensure directories exist
if (!(Test-Path "public")) {
    New-Item -ItemType Directory -Path "public" -Force
}
if (!(Test-Path "web")) {
    New-Item -ItemType Directory -Path "web" -Force
}

$json | Set-Content public\version.json -Force
Copy-Item public\version.json web\ -Force -ErrorAction SilentlyContinue

# Build APK with version
Write-Host "📱 Building APK..." -ForegroundColor Yellow
flutter build apk --release --dart-define=BUILD_VERSION="$version"

# Ensure public directory exists before copying
if (!(Test-Path "public")) {
    New-Item -ItemType Directory -Path "public" -Force
}

# Check if APK was built successfully
if (Test-Path "build/app/outputs/flutter-apk/app-release.apk") {
    Copy-Item build/app/outputs/flutter-apk/app-release.apk public\conquer_club.apk -Force
    Write-Host "✅ APK copied successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ APK build failed or file not found!" -ForegroundColor Red
    exit 1
}

# Build web
Write-Host "🌐 Building web..." -ForegroundColor Yellow
flutter build web --release --dart-define=BUILD_VERSION="$version"

# Check if web build succeeded
if (!(Test-Path "build/web")) {
    Write-Host "❌ Web build failed!" -ForegroundColor Red
    exit 1
}

# Deploy
Write-Host "☁️ Deploying to Cloudflare..." -ForegroundColor Yellow
npx wrangler pages deploy build/web --project-name=conquer-club-app

Write-Host ""
Write-Host "✅ Deployed version: $version" -ForegroundColor Green
Write-Host ""
Write-Host "📋 MANUAL STEP REQUIRED:" -ForegroundColor Yellow
Write-Host "Run this SQL in Supabase:" -ForegroundColor Cyan
Write-Host ""
Write-Host "DELETE FROM app_versions WHERE platform = 'android';" -ForegroundColor White
Write-Host "INSERT INTO app_versions (platform, minimum_version, latest_version, download_url, created_at, updated_at)" -ForegroundColor White
Write-Host "VALUES ('android', '$version', '$version', 'https://drive.google.com/uc?export=download&id=1dwBLzyXqU3W0YdsQZlAZeA7Xp47IYJUY', NOW(), NOW());" -ForegroundColor White