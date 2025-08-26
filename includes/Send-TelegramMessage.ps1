. .\Write-Log.ps1

# === Telegram ===
function Send-TelegramMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [bool]$IsTelegramEnabled,

        [Parameter(Mandatory=$true)]
        [string]$BotToken,

        [Parameter(Mandatory=$true)]
        [string]$ChannelId
    )

    if (-not $IsTelegramEnabled) {
        return $true
    }

    $Uri = "https://api.telegram.org/bot$BotToken/sendMessage"
    $Body = @{
        chat_id    = $ChannelId
        text       = $Message
        parse_mode = "HTML"
    }

    $retries = 3
    for ($i = 1; $i -le $retries; $i++) {
        try {
            Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -TimeoutSec 10 | Out-Null
            return $true
        }
        catch {
            if ($i -eq $retries) {
                Write-Log "❌ Не удалось отправить сообщение в Telegram после $retries попыток: $_"
                return $false
            }
            else {
                Start-Sleep -Seconds (2 * $i)
            }
        }
    }
    return $false
}
