$LogFile = $LOG_FILE

# === Логирование ===
function Write-Log {
    param(
        [string]$Message,
        [switch]$Pale
    )
    if ($LogEnabled) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp | $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    if ($Pale) {
        Write-Host $Message -ForegroundColor DarkGray
    } else {
        Write-Host $Message
    }
}