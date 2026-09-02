# update.ps1 - Auto-deployment with version management
#Requires -Version 5.0

Write-Host "🚀 Auto-deploy started..." -ForegroundColor Yellow

# Read current version from pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" | Select-String 'version: (\d+\.\d+\.\d+)\+(\d+)'
if ($pubspec) {
    $version = $pubspec.Matches.Groups[1].Value
    $buildNumber = $pubspec.Matches.Groups[2].Value
    Write-Host "📌 Version: $version+$buildNumber" -ForegroundColor Cyan
} else {
    Write-Host "❌ Could not read version from pubspec.yaml!" -ForegroundColor Red
    exit 1
}

# Create version.json
$json = @{
    version = $version
    apk_url = "https://drive.google.com/uc?export=download&id=1dwBLzyXqU3W0YdsQZlAZeA7Xp47IYJUY"
    changelog = "Auto-deploy version $version"
} | ConvertTo-Json

# Ensure directories exist
@("public", "web") | ForEach-Object {
    if (!(Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force
        Write-Host "📁 Created $_ directory" -ForegroundColor Gray
    }
}

# Save version.json
$json | Set-Content public\version.json -Force
Copy-Item public\version.json web\ -Force -ErrorAction SilentlyContinue
Write-Host "✅ version.json created" -ForegroundColor Green

# Build APK
Write-Host "📱 Building APK..." -ForegroundColor Yellow
$apkBuild = flutter build apk --release --dart-define=BUILD_VERSION="$version"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ APK build failed!" -ForegroundColor Red
    exit 1
}

# Copy APK
$apkSource = "build/app/outputs/flutter-apk/app-release.apk"
$apkDest = "public\conquer_club.apk"
if (Test-Path $apkSource) {
    Copy-Item $apkSource $apkDest -Force
    Write-Host "✅ APK copied to public/" -ForegroundColor Green
} else {
    Write-Host "❌ APK not found at $apkSource" -ForegroundColor Red
    exit 1
}

# Build Web
Write-Host "🌐 Building web..." -ForegroundColor Yellow
$webBuild = flutter build web --release --dart-define=BUILD_VERSION="$version"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Web build failed!" -ForegroundColor Red
    exit 1
}

# Deploy to Cloudflare
Write-Host "☁️ Deploying to Cloudflare..." -ForegroundColor Yellow
$deploy = npx wrangler pages deploy build/web --project-name=conquer-club-app
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Cloudflare deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Deployment complete!" -ForegroundColor Green
Write-Host "📌 Version: $version" -ForegroundColor Cyan

# Show next steps
Write-Host ""
Write-Host "📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Upload APK to Google Drive and get new file ID" -ForegroundColor White
Write-Host "2. Update the file ID in this script" -ForegroundColor White
Write-Host "3. Run this SQL in Supabase:" -ForegroundColor White
Write-Host ""
Write-Host "DELETE FROM app_versions WHERE platform = 'android';" -ForegroundColor Cyan
Write-Host "INSERT INTO app_versions (platform, minimum_version, latest_version, download_url, created_at, updated_at)" -ForegroundColor Cyan
Write-Host "VALUES ('android', '$version', '$version', 'https://drive.google.com/uc?export=download&id=YOUR_NEW_FILE_ID', NOW(), NOW());" -ForegroundColor Cyan

# Open deployment URL
Start-Process "https://main.conquer-club-app.pages.dev"