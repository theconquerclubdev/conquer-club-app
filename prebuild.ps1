# prebuild.ps1 - Auto-generates version
$timestamp = Get-Date -Format "yyyy.MM.dd.HHmm"
$version = $timestamp

# Create version.json
$json = @{
    version = $version
    apk_url = "https://drive.google.com/uc?export=download&id=1dwBLzyXqU3W0YdsQZlAZeA7Xp47IYJUY"
    changelog = "Auto-build $version"
} | ConvertTo-Json

$json | Set-Content public\version.json -Force
Copy-Item public\version.json web\ -Force

Write-Host "✅ Version set to: $version" -ForegroundColor Green