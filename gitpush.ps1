# ============================
# Git Auto Push Script
# ============================

# Ask for commit message
$commitMessage = Read-Host "Enter commit message"

if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    Write-Host "❌ Commit message cannot be empty." -ForegroundColor Red
    exit
}

Write-Host "`n📥 Pulling latest changes..." -ForegroundColor Cyan
git pull origin main

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Pull failed. Resolve conflicts first." -ForegroundColor Red
    exit
}

Write-Host "`n📦 Staging files..." -ForegroundColor Cyan
git add .

Write-Host "`n📝 Committing..." -ForegroundColor Cyan
git commit -m "$commitMessage"

# If nothing to commit, continue to push anyway
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ Nothing to commit (or commit failed)." -ForegroundColor Yellow
}

Write-Host "`n🚀 Pushing to main..." -ForegroundColor Cyan
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Successfully pushed to main!" -ForegroundColor Green
}
else {
    Write-Host "`n❌ Push failed." -ForegroundColor Red
}
