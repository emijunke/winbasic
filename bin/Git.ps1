# Instalacion desatendida de Git para Windows.
# CustomWin lo ejecuta cuando se tilda Git.
# Tambien puede correrse solo:
#   irm "https://raw.githubusercontent.com/emijunke/winbasic/main/bin/Git.ps1" | iex
# No lleva directiva de version ni parametros de script: tiene que funcionar con irm | iex.
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Write-GitLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
        return
    }
    Write-Host "[$Level] $Message"
}
function Test-GitAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}
function Get-GitArchitecture {
    if (
        $env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or
        $env:PROCESSOR_ARCHITEW6432 -eq "ARM64"
    ) {
        return "ARM64"
    }
    if ([Environment]::Is64BitOperatingSystem) {
        return "x64"
    }
    return "x86"
}
function Get-GitInstallPath {
    $Roots = @(
        [string]$env:ProgramFiles,
        [string]${env:ProgramFiles(x86)},
        [string]$env:ProgramW6432
    )
    foreach ($Root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($Root)) {
            continue
        }
        $Candidate = Join-Path $Root "Git\cmd\git.exe"
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }
    return ""
}
function Get-GitInstalledVersion {
    $Path = Get-GitInstallPath
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $Version = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
        if ([string]::IsNullOrWhiteSpace($Version)) {
            return $Path
        }
        return $Version
    }
    $UninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($Root in $UninstallRoots) {
        $Entries = @(
            Get-ItemProperty -Path $Root -ErrorAction SilentlyContinue
        )
        foreach ($Entry in $Entries) {
            $Name = [string]$Entry.DisplayName
            if ($Name -match '^Git($| version )') {
