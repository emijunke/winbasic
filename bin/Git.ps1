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


            if ($Name -eq "Git" -or $Name.StartsWith("Git version ")) {

                if ([string]::IsNullOrWhiteSpace([string]$Entry.DisplayVersion)) {

                    return $Name
                }


                return [string]$Entry.DisplayVersion
            }
        }
    }


    return ""
}



function Get-GitInstallerUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    if ($Architecture -eq "x64") {

        $Pattern = '^Git-.+-64-bit\.exe$'
    }
    elseif ($Architecture -eq "ARM64") {

        $Pattern = '^Git-.+-arm64\.exe$'
    }
    else {

        throw "No hay instalador oficial de Git para $Architecture."
    }


    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
        -Headers @{ "User-Agent" = "Install-Win-Basic" }


    $Asset = $Release.assets |
        Where-Object { $_.name -match $Pattern } |
        Select-Object -First 1


    if (-not $Asset) {

        throw "No se encontro el instalador de Git para $Architecture."
    }


    $Url = [string]$Asset.browser_download_url


    if ($Url -notlike "https://github.com/git-for-windows/git/releases/download/*/*.exe") {

        throw "La URL del instalador de Git no es la oficial."
    }


    return $Url
}



function Install-GitForWindows {

    if (-not (Test-GitAdministrator)) {

        throw "PowerShell no esta ejecutandose como Administrador."
    }


    $Installed = Get-GitInstalledVersion


    if (-not [string]::IsNullOrWhiteSpace($Installed)) {

        Write-GitLog "Git ya esta instalado ($Installed). Se omite." "OK"

        return
    }


    $Architecture = Get-GitArchitecture

    Write-GitLog "Arquitectura para Git: $Architecture"


    $Url = Get-GitInstallerUrl -Architecture $Architecture

    $WorkDir = $env:TEMP


    if (-not [string]::IsNullOrWhiteSpace([string]$TempDir)) {

        $WorkDir = [string]$TempDir
    }


    if (-not (Test-Path -LiteralPath $WorkDir)) {

        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }


    $Destination = Join-Path $WorkDir "git-setup.exe"

    Write-GitLog "Descargando Git..."

    Write-GitLog "Origen: $Url"


    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $Destination `
        -UseBasicParsing


    if (-not (Test-Path -LiteralPath $Destination)) {

        throw "No se encontro el archivo descargado."
    }


    $Size = (Get-Item -LiteralPath $Destination).Length


    if ($Size -lt 400KB) {

        throw "El archivo descargado parece invalido. Tamano: $Size bytes."
    }


    Write-GitLog ("Descarga de Git completada. Tamano: {0:N1} MB" -f ($Size / 1MB)) "OK"


    $Signature = Get-AuthenticodeSignature -FilePath $Destination


    if ($Signature.Status -ne "Valid") {

        throw "Firma digital de Git no valida. Estado: $($Signature.Status)"
    }


    Write-GitLog "Integridad de Git: $($Signature.SignerCertificate.Subject)" "OK"

    Unblock-File -LiteralPath $Destination -ErrorAction SilentlyContinue


    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = $Destination

    $StartInfo.Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"

    $StartInfo.UseShellExecute = $false

    $StartInfo.CreateNoWindow = $true


    $Process = New-Object System.Diagnostics.Process

    $Process.StartInfo = $StartInfo


    if (-not $Process.Start()) {

        throw "No se pudo iniciar el instalador de Git."
    }


    if (-not $Process.WaitForExit(900000)) {

        try {

            $Process.Kill()
        }
        catch {
        }


        throw "El instalador de Git excedio los 900 segundos."
    }


    $ExitCode = $Process.ExitCode


    if ($ExitCode -notin @(0, 3010, 1641, $null)) {

        throw "Git devolvio el codigo $ExitCode."
    }


    $InstalledPath = Get-GitInstallPath


    if ([string]::IsNullOrWhiteSpace($InstalledPath)) {

        throw "El instalador de Git termino, pero no se encontro git.exe."
    }


    Write-GitLog "Git instalado. Codigo: $ExitCode" "OK"
}



Install-GitForWindows

# Fin del script.
