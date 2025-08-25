if ($global:LoggerIncluded) { return }
$global:LoggerIncluded = $true

$LogFile = $LOG_FILE

# === Логирование ===
function Write-Log {
    param([string]$Message)
    if ($LogEnabled) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp | $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    Write-Host $Message
}