# === Логирование ===
function Initialize-LogConsolePump {
    if ($global:LogConsoleQueue) { return $true }

    try {
        $global:LogConsoleQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        $pump = [powershell]::Create()
        $pump.Runspace = $runspace
        [void]$pump.AddScript({
            param($queue)
            $item = $null
            while ($true) {
                while ($queue.TryDequeue([ref]$item)) {
                    if ($item.Pale) { Write-Host $item.Message -ForegroundColor DarkGray }
                    else { Write-Host $item.Message }
                }
                Start-Sleep -Milliseconds 100
            }
        }).AddArgument($global:LogConsoleQueue)
        $global:LogConsolePump = $pump
        [void]$pump.BeginInvoke()
        return $true
    }
    catch {
        return $false
    }
}

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
    if (Initialize-LogConsolePump) {
        $global:LogConsoleQueue.Enqueue([pscustomobject]@{ Message = $Message; Pale = [bool]$Pale })
    }
    else {
        if ($Pale) { Write-Host $Message -ForegroundColor DarkGray }
        else { Write-Host $Message }
    }
}
