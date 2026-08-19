# update.ps1 - Complete auto-deployment

Write-Host "🚀 Auto-deploy started..." -ForegroundColor Yellow

# Auto-generate version
$timestamp = Get-Date -Format "yyyy.MM.dd.HHmm"
$version = $timestamp

Write-Host "📌 Version: $version" -ForegroundColor Cyan

# Create version.json
$json = @{
    version = $version
    apk_url = "https://drive.google.com/uc?export=download&id=1dwBLzyXqU3W0YdsQZlAZeA7Xp47IYJUY"
    changelog = "Auto-build $version"
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
    cp build/app/outputs/flutter-apk/app-release.apk public\conquer_club.apk -Force
    Write-Host "✅ APK copied successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ APK build failed or file not found!" -ForegroundColor Red
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

Write-Host "✅ Deployed version: $version" -ForegroundColor Green
Write-Host "📱 Remember to upload APK to Google Drive!" -ForegroundColor Cyan
