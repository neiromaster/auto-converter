# === Логирование ===
function Write-Log {
    param(
        [string]$Message,
        [switch]$Pale
    )
    if ($LogFile) {
        $logDirectory = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp | $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    if ($Pale) {
        Write-Host $Message -ForegroundColor DarkGray
    } else {
        Write-Host $Message
    }
}