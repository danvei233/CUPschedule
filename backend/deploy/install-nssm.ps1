param(
    [string]$ApiKey = '',
    [Parameter(Mandatory=$true)][string]$AudioKey,
    [string]$BackendDir = (Split-Path $PSScriptRoot -Parent),
    [string]$DataDir = 'D:\blackbook-data',
    [string]$Listen = '0.0.0.0:8090',
    [string]$HuggingFaceToken = '',
    [string]$Nssm = 'nssm.exe'
)
$ErrorActionPreference = 'Stop'
function Invoke-Nssm {
    & $Nssm @args
    if ($LASTEXITCODE -ne 0) { throw "NSSM failed: $($args[0]) $($args[1])" }
}
$BackendDir = (Resolve-Path -LiteralPath $BackendDir).Path
$serverExe = Join-Path $BackendDir 'server.exe'
$pythonExe = Join-Path $BackendDir 'audio_service\.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $serverExe) -or !(Test-Path -LiteralPath $pythonExe)) {
    throw 'Build server.exe and create audio_service/.venv first; see README.md.'
}
if (($ApiKey.Length -gt 0 -and $ApiKey.Length -lt 16) -or $AudioKey.Length -lt 16) { throw 'Use keys of at least 16 characters (API key may be omitted for automatic generation).' }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$logDir = Join-Path $DataDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Invoke-Nssm install BlackbookApi $serverExe
Invoke-Nssm set BlackbookApi AppDirectory $BackendDir
Invoke-Nssm set BlackbookApi AppEnvironmentExtra "BLACKBOOK_API_KEY=$ApiKey" "BLACKBOOK_DATA_DIR=$DataDir" "BLACKBOOK_LISTEN=$Listen" 'GIN_MODE=release'
Invoke-Nssm set BlackbookApi AppStdout (Join-Path $logDir 'api.log')
Invoke-Nssm set BlackbookApi AppStderr (Join-Path $logDir 'api-error.log')
Invoke-Nssm install BlackbookAudio $pythonExe
Invoke-Nssm set BlackbookAudio AppDirectory (Join-Path $BackendDir 'audio_service')
Invoke-Nssm set BlackbookAudio AppParameters '-m uvicorn service:app --host 127.0.0.1 --port 8091 --workers 1'
Invoke-Nssm set BlackbookAudio AppEnvironmentExtra "BLACKBOOK_AUDIO_KEY=$AudioKey" "HF_TOKEN=$HuggingFaceToken" 'BLACKBOOK_AUDIO_AUTOLOAD=0' 'PYTHONUNBUFFERED=1'
Invoke-Nssm set BlackbookAudio AppStdout (Join-Path $logDir 'audio.log')
Invoke-Nssm set BlackbookAudio AppStderr (Join-Path $logDir 'audio-error.log')
foreach ($service in @('BlackbookApi','BlackbookAudio')) {
    Invoke-Nssm set $service Start SERVICE_AUTO_START
    Invoke-Nssm set $service AppExit Default Restart
    Invoke-Nssm set $service AppRestartDelay 5000
    Invoke-Nssm set $service AppRotateFiles 1
    Invoke-Nssm set $service AppRotateBytes 10485760
}
Write-Host 'Services installed, not started. Set audio_key in App server settings to match AudioKey, then start both services.'
