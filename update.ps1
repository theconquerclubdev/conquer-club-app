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

$json | Set-Content public\version.json -Force
Copy-Item public\version.json web\ -Force

# Build APK with version
Write-Host "📱 Building APK..." -ForegroundColor Yellow
flutter build apk --release --dart-define=BUILD_VERSION="$version"
cp build/app/outputs/flutter-apk/app-release.apk public\conquer_club.apk -Force

# Build web
Write-Host "🌐 Building web..." -ForegroundColor Yellow
flutter build web --release --dart-define=BUILD_VERSION="$version"

# Deploy
Write-Host "☁️ Deploying to Cloudflare..." -ForegroundColor Yellow
npx wrangler pages deploy build/web --project-name=conquer-club-app

Write-Host "✅ Deployed version: $version" -ForegroundColor Green
Write-Host "📱 Remember to upload APK to Google Drive!" -ForegroundColor Cyan
