<#
.SYNOPSIS
    Menu para elegir que personalizar en Windows.

.DESCRIPTION
    - Requiere PowerShell ejecutado como Administrador.
    - Al ejecutarse muestra una lista para tildar que se quiere aplicar.
    - Puede instalar Notepad++, 7-Zip, Firefox, Chrome, PuTTY, WinSCP,
      VMware Tools y Office 2024 LTSC Professional Plus en espanol.
      Si alguno ya esta instalado, no lo vuelve a descargar.
      7-Zip no firma su instalador: se comprueba el SHA-256 de la
      release oficial.
    - Puede instalar AnyDesk oculto, con password de acceso desatendido.
      Si $UnattendedPassword ya existe, no la vuelve a pedir.
      Una copia portable en uso no se cierra.
    - Puede deshabilitar el Firewall, habilitar Escritorio remoto sin
      autenticacion de nivel de red y deshabilitar IPv6.
    - Puede ocultar la busqueda de la barra de tareas y alinearla
      a la izquierda.
    - Correr Powershell baja y ejecuta
      https://raw.githubusercontent.com/emijunke/winbasic/main/ps.ps1
    - El menu y la invocacion de cada opcion estan en bin/popup.ps1.
      Los nombres de la ventana estan al principio de ese archivo.
    - Git, MobaXterm, Calculadora y lo que se agregue despues tambien
      estan en bin, un ps1 por instalacion.
    - Lo que no se tilda no se modifica.
    - Genera log en C:\ProgramData\CustomWin.

.EXAMPLE
    .\CustomWin.ps1

.EXAMPLE
    irm "https://raw.githubusercontent.com/emijunke/winbasic/main/CustomWin.ps1" | iex

.EXAMPLE
    $UnattendedPassword = 'PASSWORD'
    irm "https://raw.githubusercontent.com/emijunke/winbasic/main/CustomWin.ps1" | iex
#>

# El menu, los nombres de la ventana y la invocacion de cada opcion
# estan en bin/popup.ps1. Este archivo los llama.


# Windows PowerShell 5.1 rechaza #requires y param() cuando el script
# se ejecuta con Invoke-Expression (irm | iex).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"


if ($PSVersionTable.PSVersion -lt [Version] "5.1") {

    Write-Host "Se requiere PowerShell 5.1 o superior."

    if ($PSCommandPath) {

        exit 12
    }

    return
}


$LogDir = "C:\ProgramData\CustomWin"

$LogFile = Join-Path $LogDir "CustomWin.log"

$TempDir = Join-Path $env:TEMP "CustomWin"

$Script:HideSearch = $false

$Script:AlignLeft = $false

$Script:Failures = New-Object System.Collections.Generic.List[string]


function Write-Log {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[{0}] [{1}] {2}" -f $Timestamp, $Level, $Message


    switch ($Level) {

        "OK" {

            Write-Host $Line -ForegroundColor Green
        }

        "WARN" {

            Write-Host $Line -ForegroundColor Yellow
        }

        "ERROR" {

            Write-Host $Line -ForegroundColor Red
        }

        default {

            Write-Host $Line
        }
    }


    if ($script:LogFile) {

        Add-Content -Path $script:LogFile -Value $Line -Encoding UTF8
    }
}



function Stop-CustomWin {

    param (
        [int]$Code
    )


    if ([string]::IsNullOrEmpty($PSCommandPath)) {

        throw "CustomWinExit:$Code"
    }


    exit $Code
}



function Add-DeployFailure {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )


    $Script:Failures.Add($Message)

    Write-Log $Message "ERROR"
}



function Test-Administrator {

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}



function Get-OsArchitecture {

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



function Set-RegistryDword {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Value
    )


    if (-not (Test-Path -LiteralPath $Path)) {

        New-Item -Path $Path -Force | Out-Null
    }


    New-ItemProperty `
        -LiteralPath $Path `
        -Name $Name `
        -Value $Value `
        -PropertyType DWord `
        -Force |
        Out-Null
}



function Save-WebFile {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )


    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


    Invoke-WebRequest `
        -Uri $Uri `
        -OutFile $Destination `
        -UseBasicParsing
}



function Test-InstallerTrust {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Sha256
    )


    $Signature = Get-AuthenticodeSignature -FilePath $Path


    if ($Signature.Status -eq "Valid") {

        return [string]$Signature.SignerCertificate.Subject
    }


    $Expected = ""

    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {

        $Expected = $Sha256.Trim().ToLowerInvariant()
    }


    if ($Expected -match '^[0-9a-f]{64}$') {

        $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

        if ($Actual.ToLowerInvariant() -eq $Expected) {

            return "instalador oficial sin firma Authenticode, SHA-256 verificado"
        }


        throw "El SHA-256 no coincide con el publicado por el fabricante."
    }


    throw "Firma digital no valida. Estado: $($Signature.Status)"
}



function Invoke-InstallerProcess {

    param (

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [int]$TimeoutSeconds = 900,

        [string]$WorkingDirectory
    )


    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = $FilePath

    $StartInfo.Arguments = $Arguments

    $StartInfo.UseShellExecute = $false

    $StartInfo.CreateNoWindow = $true


    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {

        $StartInfo.WorkingDirectory = $WorkingDirectory
    }


    $Process = New-Object System.Diagnostics.Process

    $Process.StartInfo = $StartInfo


    if (-not $Process.Start()) {

        throw "No se pudo iniciar $FilePath"
    }


    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {

        try {

            $Process.Kill()
        }
        catch {
        }


        throw "El instalador excedio los $TimeoutSeconds segundos."
    }


    return $Process.ExitCode
}



function Install-SetupPackage {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [ValidateSet("NSIS", "MSI")]
        [string]$Kind,

        [string]$Sha256,

        [string]$Arguments
    )


    $Destination = Join-Path $TempDir $FileName


    Write-Log "Descargando $Name..."

    Write-Log "Origen: $Uri"


    Save-WebFile -Uri $Uri -Destination $Destination


    if (-not (Test-Path -LiteralPath $Destination)) {

        throw "No se encontro el archivo descargado."
    }


    $Size = (Get-Item -LiteralPath $Destination).Length


    if ($Size -lt 400KB) {

        throw "El archivo descargado parece invalido. Tamano: $Size bytes."
    }


    Write-Log ("Descarga de {0} completada. Tamano: {1:N1} MB" -f $Name, ($Size / 1MB)) "OK"


    $Trust = Test-InstallerTrust -Path $Destination -Sha256 $Sha256

    Write-Log "Integridad de ${Name}: $Trust" "OK"


    Unblock-File -LiteralPath $Destination -ErrorAction SilentlyContinue


    if ($Kind -eq "MSI") {

        $Msiexec = "$env:SystemRoot\System32\msiexec.exe"


        if (
            [Environment]::Is64BitOperatingSystem -and
            -not [Environment]::Is64BitProcess
        ) {

            $Msiexec = "$env:SystemRoot\Sysnative\msiexec.exe"
        }


        $Arguments = "/i `"$Destination`" /qn /norestart"

        $ExitCode = Invoke-InstallerProcess `
            -FilePath $Msiexec `
            -Arguments $Arguments

    }
    else {

        $SetupArgs = "/S"


        if (-not [string]::IsNullOrWhiteSpace($Arguments)) {

            $SetupArgs = $Arguments
        }


        $ExitCode = Invoke-InstallerProcess `
            -FilePath $Destination `
            -Arguments $SetupArgs
    }


    if ($ExitCode -in @(0, 3010, 1641, $null)) {

        Write-Log "$Name instalado. Codigo: $ExitCode" "OK"

        return
    }


    throw "$Name devolvio el codigo $ExitCode."
}



function Get-NotepadPlusPlusUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest" `
        -Headers @{ "User-Agent" = "Install-Win-Basic" }


    $Asset = $null


    if ($Architecture -eq "ARM64") {

        $Asset = $Release.assets |
            Where-Object { $_.name -like "npp.*.Installer.arm64.exe" } |
            Select-Object -First 1
    }
    elseif ($Architecture -eq "x64") {

        $Asset = $Release.assets |
            Where-Object { $_.name -like "npp.*.Installer.x64.exe" } |
            Select-Object -First 1
    }
    else {

        $Asset = $Release.assets |
            Where-Object {
                $_.name -like "npp.*.Installer.exe" -and
                $_.name -notlike "*.Installer.x64.exe" -and
                $_.name -notlike "*.Installer.arm64.exe"
            } |
            Select-Object -First 1
    }


    if (-not $Asset) {

        throw "No se encontro el instalador de Notepad++ para $Architecture."
    }


    return $Asset.browser_download_url
}



function Get-SevenZipPackage {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/ip7z/7zip/releases/latest" `
        -Headers @{ "User-Agent" = "Install-Win-Basic" }


    $Asset = $Release.assets |
        Where-Object {
            $_.name -like "7z*.exe" -and
            $_.name -ne "7zr.exe" -and
            (
                ($Architecture -eq "x64" -and $_.name -like "*-x64.exe") -or
                ($Architecture -eq "ARM64" -and $_.name -like "*-arm64.exe") -or
                (
                    $Architecture -eq "x86" -and
                    $_.name -notlike "*-x64.exe" -and
                    $_.name -notlike "*-arm64.exe" -and
                    $_.name -notlike "*-arm.exe"
                )
            )
        } |
        Select-Object -First 1


    if (-not $Asset) {

        throw "No se encontro el instalador de 7-Zip para $Architecture."
    }


    $Url = [string]$Asset.browser_download_url

    if ($Url -notlike "https://github.com/ip7z/7zip/releases/download/*/*.exe") {

        throw "La URL del instalador de 7-Zip no es la oficial."
    }


    $Digest = ([string]$Asset.digest).Trim().ToLowerInvariant()

    if ($Digest -notmatch '^sha256:([0-9a-f]{64})$') {

        throw "7-Zip no publico el SHA-256 del instalador."
    }


    return [pscustomobject]@{
        Url    = $Url
        Sha256 = $Matches[1]
    }
}



function Get-FirefoxUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    $Language = "es-ES"

    try {

        $Culture = [string](Get-Culture).Name

        if ($Culture -eq "es-AR" -or $Culture -eq "es-ES" -or $Culture -eq "es-MX") {

            $Language = $Culture

        }
        elseif ($Culture -like "en-*") {

            $Language = "en-US"
        }

    }
    catch {
    }


    $Os = "win64"


    if ($Architecture -eq "ARM64") {

        $Os = "win64-aarch64"

    }
    elseif ($Architecture -eq "x86") {

        $Os = "win"
    }


    return "https://download.mozilla.org/?product=firefox-latest-ssl&os=$Os&lang=$Language"
}



function Get-ChromeUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    if ($Architecture -eq "x86") {

        return "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise.msi"
    }


    return "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
}



function Get-PuttyUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    $Page = Invoke-WebRequest `
        -Uri "https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html" `
        -UseBasicParsing


    $Pattern = switch ($Architecture) {

        "ARM64" { 'https://the\.earth\.li/~sgtatham/putty/latest/wa64/putty-arm64-[0-9.]+-installer\.msi' }

        "x64" { 'https://the\.earth\.li/~sgtatham/putty/latest/w64/putty-64bit-[0-9.]+-installer\.msi' }

        default { 'https://the\.earth\.li/~sgtatham/putty/latest/w32/putty-[0-9.]+-installer\.msi' }
    }


    $Match = [regex]::Match($Page.Content, $Pattern)


    if (-not $Match.Success) {

        throw "No se encontro el instalador de PuTTY para $Architecture."
    }


    return $Match.Value
}



function Get-WinScpPackage {

    $Page = Invoke-WebRequest `
        -Uri "https://winscp.net/eng/downloads.php" `
        -UseBasicParsing


    $Listed = [regex]::Match(
        $Page.Content,
        '/download/WinSCP-[0-9.]+\.msi/download'
    )


    if (-not $Listed.Success) {

        throw "No se encontro el instalador MSI de WinSCP."
    }


    $Details = Invoke-WebRequest `
        -Uri ("https://winscp.net" + $Listed.Value) `
        -UseBasicParsing


    $File = [regex]::Match(
        $Details.Content,
        'https://cdn\.winscp\.net/files/WinSCP-[0-9.]+\.msi\?secure=[A-Za-z0-9_/=+-]+,[0-9]+'
    )


    if (-not $File.Success) {

        throw "No se encontro el enlace oficial del MSI de WinSCP."
    }


    $Digest = [regex]::Match($Details.Content, 'SHA-256:\s*([0-9a-fA-F]{64})')


    if (-not $Digest.Success) {

        throw "WinSCP no publico el SHA-256 del instalador."
    }


    return [pscustomobject]@{
        Url    = $File.Value
        Sha256 = $Digest.Groups[1].Value.ToLowerInvariant()
    }
}



function Get-VMwareToolsUrl {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    $Folder = switch ($Architecture) {

        "ARM64" { "arm" }

        "x64" { "x64" }

        default { "" }
    }


    if ([string]::IsNullOrWhiteSpace($Folder)) {

        throw "No hay instalador de VMware Tools para $Architecture."
    }


    $Page = Invoke-WebRequest `
        -Uri "https://packages.vmware.com/tools/releases/latest/windows/$Folder/" `
        -UseBasicParsing


    $Pattern = "VMware-tools-[0-9.]+-[0-9]+-x64\.exe"


    if ($Architecture -eq "ARM64") {

        $Pattern = "VMware-tools-[0-9.]+-[0-9]+-arm\.exe"
    }


    $Match = [regex]::Match($Page.Content, $Pattern)


    if (-not $Match.Success -or $Match.Value -match '[\\/]') {

        throw "No se encontro el instalador de VMware Tools para $Architecture."
    }


    return "https://packages.vmware.com/tools/releases/latest/windows/$Folder/$($Match.Value)"
}



function Get-CandidatePaths {

    param (
        [string[]]$RelativePaths,
        [string[]]$ExtraPaths
    )


    $Roots = @(
        [string]$env:ProgramFiles,
        [string]${env:ProgramFiles(x86)},
        [string]$env:ProgramW6432
    )

    $Paths = @()


    foreach ($Root in $Roots) {

        if ([string]::IsNullOrWhiteSpace($Root)) {

            continue
        }


        foreach ($RelativePath in @($RelativePaths)) {

            $Relative = [string]$RelativePath

            if ([string]::IsNullOrWhiteSpace($Relative)) {

                continue
            }


            $FullPath = Join-Path -Path $Root -ChildPath $Relative

            if ($Paths -notcontains $FullPath) {

                $Paths += $FullPath
            }
        }
    }


    foreach ($ExtraPath in @($ExtraPaths)) {

        $Extra = [string]$ExtraPath

        if ([string]::IsNullOrWhiteSpace($Extra)) {

            continue
        }


        if ($Paths -notcontains $Extra) {

            $Paths += $Extra
        }
    }


    return ,$Paths
}



function Get-UninstallEntries {

    # No usar List[object]. En Windows PowerShell 5.1, @() sobre esa
    # lista creada con New-Object lanza "Los tipos de argumentos no coinciden".
    $Entries = @()

    $Hives = @(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryHive]::CurrentUser
    )

    $Views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )


    foreach ($Hive in $Hives) {

        foreach ($View in $Views) {

            $Base = $null


            try {

                $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)

                $Uninstall = $Base.OpenSubKey(
                    "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
                )


                if (-not $Uninstall) {

                    continue
                }


                foreach ($SubKeyName in $Uninstall.GetSubKeyNames()) {

                    $Key = $Uninstall.OpenSubKey($SubKeyName)

                    if (-not $Key) {

                        continue
                    }


                    $DisplayName = [string]$Key.GetValue("DisplayName")

                    $DisplayVersion = [string]$Key.GetValue("DisplayVersion")

                    $Key.Close()


                    if ([string]::IsNullOrWhiteSpace($DisplayName)) {

                        continue
                    }


                    $Entries += [pscustomobject]@{
                        DisplayName    = $DisplayName.Trim()
                        DisplayVersion = $DisplayVersion.Trim()
                    }
                }


                $Uninstall.Close()
            }
            catch {
            }
            finally {

                if ($Base) {

                    $Base.Close()
                }
            }
        }
    }


    return ,$Entries
}



function Get-FileVersionText {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )


    try {

        $Info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)


        if (-not [string]::IsNullOrWhiteSpace($Info.ProductVersion)) {

            return $Info.ProductVersion.Trim()
        }


        if (-not [string]::IsNullOrWhiteSpace($Info.FileVersion)) {

            return $Info.FileVersion.Trim()
        }
    }
    catch {
    }


    return ""
}



function Find-InstalledApplication {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [string[]]$RelativePaths,

        [string[]]$ExtraPaths
    )


    $Candidates = Get-CandidatePaths `
        -RelativePaths $RelativePaths `
        -ExtraPaths $ExtraPaths


    foreach ($Candidate in @($Candidates)) {

        if ([string]::IsNullOrWhiteSpace([string]$Candidate)) {

            continue
        }


        if (Test-Path -LiteralPath ([string]$Candidate)) {

            return [pscustomobject]@{
                Version  = Get-FileVersionText -Path ([string]$Candidate)
                Location = [string]$Candidate
            }
        }
    }


    $UninstallEntries = Get-UninstallEntries


    foreach ($Entry in $UninstallEntries) {

        if ([string]::IsNullOrWhiteSpace([string]$Entry.DisplayName)) {

            continue
        }


        if ($Entry.DisplayName -match $Pattern) {

            return [pscustomobject]@{
                Version  = [string]$Entry.DisplayVersion
                Location = [string]$Entry.DisplayName
            }
        }
    }


    return $null
}



function Get-LocalAppPath {

    param (
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )


    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {

        return ""
    }


    return (Join-Path $env:LOCALAPPDATA $RelativePath)
}



function Install-BasicApplications {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Architecture,

        [string[]]$Names
    )


    $Packages = @(
        @{
            Name = "Notepad++"
            File = "npp-setup.exe"
            Kind = "NSIS"
            Pattern = '^Notepad\+\+'
            RelativePaths = @("Notepad++\notepad++.exe")
            ExtraPaths = @()
        },
        @{
            Name = "7-Zip"
            File = "7zip-setup.exe"
            Kind = "NSIS"
            Pattern = '^7-Zip($| )'
            RelativePaths = @("7-Zip\7z.exe", "7-Zip\7zFM.exe")
            ExtraPaths = @()
        },
        @{
            Name = "Firefox"
            File = "firefox-setup.exe"
            Kind = "NSIS"
            Pattern = '^Mozilla Firefox'
            RelativePaths = @("Mozilla Firefox\firefox.exe")
            ExtraPaths = @(
                (Get-LocalAppPath "Mozilla Firefox\firefox.exe")
            )
        },
        @{
            Name = "Google Chrome"
            File = "chrome-setup.msi"
            Kind = "MSI"
            Pattern = '^Google Chrome($| \d)'
            RelativePaths = @("Google\Chrome\Application\chrome.exe")
            ExtraPaths = @(
                (Get-LocalAppPath "Google\Chrome\Application\chrome.exe")
            )
        },
        @{
            Name = "PuTTY"
            File = "putty-setup.msi"
            Kind = "MSI"
            Pattern = '^PuTTY($| )'
            RelativePaths = @("PuTTY\putty.exe")
            ExtraPaths = @()
        },
        @{
            Name = "WinSCP"
            File = "winscp-setup.msi"
            Kind = "MSI"
            Pattern = '^WinSCP($| )'
            RelativePaths = @("WinSCP\WinSCP.exe")
            ExtraPaths = @()
        },
        @{
            Name = "VMware Tools"
            File = "vmware-tools-setup.exe"
            Kind = "NSIS"
            Arguments = '/S /v "/qn REBOOT=R"'
            Pattern = '^VMware Tools'
            RelativePaths = @("VMware\VMware Tools\vmtoolsd.exe")
            ExtraPaths = @()
        }
    )


    foreach ($Package in $Packages) {

        if ($Names -and $Names -notcontains $Package.Name) {

            continue
        }


        try {

            $Installed = Find-InstalledApplication `
                -Pattern $Package.Pattern `
                -RelativePaths $Package.RelativePaths `
                -ExtraPaths $Package.ExtraPaths


            if ($Installed) {

                $Detail = $Installed.Version

                if ([string]::IsNullOrWhiteSpace($Detail)) {

                    $Detail = $Installed.Location
                }


                Write-Log "$($Package.Name) ya esta instalado ($Detail). Se omite." "OK"

                continue
            }


            $Url = $null

            $Sha256 = ""


            switch ($Package.Name) {

                "Notepad++" {

                    $Url = Get-NotepadPlusPlusUrl -Architecture $Architecture
                }

                "7-Zip" {

                    $SevenZip = Get-SevenZipPackage -Architecture $Architecture

                    $Url = $SevenZip.Url

                    $Sha256 = $SevenZip.Sha256
                }

                "Firefox" {

                    $Url = Get-FirefoxUrl -Architecture $Architecture
                }

                "Google Chrome" {

                    $Url = Get-ChromeUrl -Architecture $Architecture
                }

                "PuTTY" {

                    $Url = Get-PuttyUrl -Architecture $Architecture
                }

                "WinSCP" {

                    $WinScp = Get-WinScpPackage

                    $Url = $WinScp.Url

                    $Sha256 = $WinScp.Sha256
                }

                "VMware Tools" {

                    $Url = Get-VMwareToolsUrl -Architecture $Architecture
                }
            }


            $SetupArguments = ""

            if ($Package["Arguments"]) {

                $SetupArguments = [string]$Package["Arguments"]
            }


            Install-SetupPackage `
                -Name ([string]$Package.Name) `
                -Uri ([string]$Url) `
                -FileName ([string]$Package.File) `
                -Kind ([string]$Package.Kind) `
                -Sha256 ([string]$Sha256) `
                -Arguments $SetupArguments

        }
        catch {

            $FailLine = $_.InvocationInfo.ScriptLineNumber

            Add-DeployFailure "$($Package.Name) (linea ${FailLine}): $($_.Exception.Message)"
        }
    }
}



function Invoke-BinScript {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )


    $FileName = "$Name.ps1"

    $Code = $null

    $LocalPath = ""


    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {

        $LocalPath = Join-Path $PSScriptRoot "bin\$FileName"
    }


    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath)) {

        Write-Log "Ejecutando bin\$FileName local."

        $Code = [System.IO.File]::ReadAllText($LocalPath)
    }
    else {

        $Uri = "https://raw.githubusercontent.com/emijunke/winbasic/main/bin/$FileName"

        Write-Log "Ejecutando $Uri"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $Code = Invoke-RestMethod `
            -Uri $Uri `
            -UseBasicParsing
    }


    if ($Code -is [System.Array]) {

        $Code = $Code -join "`n"
    }
    elseif ($Code -isnot [string]) {

        $Code = [string]$Code
    }


    if ([string]::IsNullOrWhiteSpace($Code)) {

        throw "$FileName llego vacio."
    }


    if ($Code -match '\[\d+ lines collapsed\]') {

        throw "$FileName no se puede ejecutar: el archivo subido esta colapsado."
    }


    if (-not $Code.Contains("Fin del script.")) {

        Write-Log "$FileName no tiene la marca de fin. Se ejecuta igual." "WARN"


        try {

            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

            [void][System.Windows.Forms.MessageBox]::Show(
                "$FileName no incluye la marca de fin. Se va a ejecutar igual.",
                "CustomWin",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        catch {
        }
    }


    $SavedErrorAction = $ErrorActionPreference


    try {

        Invoke-Expression $Code
    }
    finally {

        $ErrorActionPreference = $SavedErrorAction
    }
}



function Get-PopupFallbackCode {

    $Packed = @'
IyBNZW51IGRlIEN1c3RvbVdpbi4NCiMgTG8gbGxhbWEgQ3VzdG9tV2luLnBzMS4gTm8gaGFjZSBmYWx0YSBlamVjdXRhcmxvIHNv
bG8uDQojIEFjYSBlc3RhbiBsb3Mgbm9tYnJlcywgbGEgdmVudGFuYSB5IGxhIGludm9jYWNpb24gZGUgY2FkYSBvcGNpb24uDQoj
IE5vIGxsZXZhIGRpcmVjdGl2YSBkZSB2ZXJzaW9uIG5pIHBhcmFtZXRyb3MgZGUgc2NyaXB0OiB0aWVuZSBxdWUNCiMgZnVuY2lv
bmFyIGN1YW5kbyBDdXN0b21XaW4gbG8gZWplY3V0YSBjb24gaXJtIHwgaWV4Lg0KDQojID09PT09PT09PT09PT09PT09PT09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQ0KIyBOb21icmVzIHF1ZSBhcGFyZWNlbiBlbiBsYSB2ZW50YW5h
Lg0KIyBDYW1iaWUgc29sbyBlbCB0ZXh0byBlbnRyZSBjb21pbGxhcy4NCiMgTm8gYm9ycmUgbmkgcmVub21icmUgbGFzIHZhcmlh
Ymxlcy4NCiMgUGFyYSBhZ3JlZ2FyIHVuYSBvcGNpb246IHN1bWUgdW5hIHZhcmlhYmxlIGFjYSwgdW4gSWQgZW4NCiMgR2V0LUN1
c3RvbVdpbkNob2ljZXMgeSwgbWFzIGFiYWpvLCBlbCBibG9xdWUgcXVlIGxhIGludm9jYS4NCiMgPT09PT09PT09PT09PT09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09DQokU2NyaXB0Okl0ZW1fTm90ZXBhZCA9ICJOb3RlcGFk
KysgKHVsdGltYSB2ZXJzaW9uLCBzZSBvbWl0ZSBzaSB5YSBlc3RhKSINCiRTY3JpcHQ6SXRlbV83WmlwID0gIjctWmlwICh1bHRp
bWEgdmVyc2lvbiwgc2Ugb21pdGUgc2kgeWEgZXN0YSkiDQokU2NyaXB0Okl0ZW1fRmlyZWZveCA9ICJGaXJlZm94ICh1bHRpbWEg
dmVyc2lvbiwgc2Ugb21pdGUgc2kgeWEgZXN0YSkiDQokU2NyaXB0Okl0ZW1fQ2hyb21lID0gIkdvb2dsZSBDaHJvbWUgKHVsdGlt
YSB2ZXJzaW9uLCBzZSBvbWl0ZSBzaSB5YSBlc3RhKSINCiRTY3JpcHQ6SXRlbV9QdVRUWSA9ICJQdVRUWSAodWx0aW1hIHZlcnNp
b24sIHNlIG9taXRlIHNpIHlhIGVzdGEpIg0KJFNjcmlwdDpJdGVtX1dpblNDUCA9ICJXaW5TQ1AgKHVsdGltYSB2ZXJzaW9uLCBz
ZSBvbWl0ZSBzaSB5YSBlc3RhKSINCiRTY3JpcHQ6SXRlbV9WTXdhcmUgPSAiVk13YXJlIFRvb2xzICh1bHRpbWEgdmVyc2lvbiwg
c2Ugb21pdGUgc2kgeWEgZXN0YSkiDQokU2NyaXB0Okl0ZW1fR2l0ID0gIkdpdCAodWx0aW1hIHZlcnNpb24sIHNlIG9taXRlIHNp
IHlhIGVzdGEpIg0KJFNjcmlwdDpJdGVtX01vYmFYdGVybSA9ICJNb2JhWHRlcm0iDQokU2NyaXB0Okl0ZW1fQ2FsYyA9ICJDYWxj
dWxhZG9yYSINCiRTY3JpcHQ6SXRlbV9PZmZpY2UgPSAiT2ZmaWNlIDIwMjQgTFRTQyBQcm9mZXNzaW9uYWwgUGx1cywgZXNwYW5v
bCwgc2luIFNreXBlIEVtcHJlc2FyaWFsIG5pIE9uZURyaXZlIg0KJFNjcmlwdDpJdGVtX1Bvd2Vyc2hlbGwgPSAiT2ZmaWNlIDIw
MjQgTFRTQyBQcm9mZXNzaW9uYWwgUGx1cyAoQWN0aXZhY2lvbikiDQokU2NyaXB0Okl0ZW1fQW55RGVzayA9ICJBbnlEZXNrIG9j
dWx0bywgY29uIHBhc3N3b3JkIGRlIGFjY2VzbyBkZXNhdGVuZGlkbyINCiRTY3JpcHQ6SXRlbV9GaXJld2FsbCA9ICJEZXNoYWJp
bGl0YXIgZWwgRmlyZXdhbGwgZGUgV2luZG93cyBlbiB0b2RhcyBsYXMgcmVkZXMiDQokU2NyaXB0Okl0ZW1fRXNjcml0b3Jpb1Jl
bW90byA9ICJIYWJpbGl0YXIgRXNjcml0b3JpbyByZW1vdG8gc2luIGF1dGVudGljYWNpb24gZGUgbml2ZWwgZGUgcmVkIg0KJFNj
cmlwdDpJdGVtX0lQdjYgPSAiRGVzaGFiaWxpdGFyIElQdjYgZW4gdG9kbyBlbCBzaXN0ZW1hIg0KJFNjcmlwdDpJdGVtX0J1c3F1
ZWRhID0gIk9jdWx0YXIgZWwgY2FtcG8gZGUgYnVzcXVlZGEgZGUgbGEgYmFycmEgZGUgdGFyZWFzIg0KJFNjcmlwdDpJdGVtX0Jh
cnJhVGFyZWFzID0gIkFsaW5lYXIgbG9zIGljb25vcyBkZSBsYSBiYXJyYSBkZSB0YXJlYXMgYSBsYSBpenF1aWVyZGEiDQoNCmZ1
bmN0aW9uIEdldC1DdXN0b21XaW5DaG9pY2VzIHsNCg0KICAgIHJldHVybiBAKA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQg
PSAiTm90ZXBhZCsrIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9Ob3RlcGFkDQogICAgICAgIH0sDQogICAgICAg
IEB7DQogICAgICAgICAgICBJZCA9ICI3LVppcCINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fN1ppcA0KICAgICAg
ICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiRmlyZWZveCINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0
ZW1fRmlyZWZveA0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiR29vZ2xlIENocm9tZSINCiAgICAg
ICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fQ2hyb21lDQogICAgICAgIH0sDQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9
ICJQdVRUWSINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fUHVUVFkNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAg
ICAgICAgICAgIElkID0gIldpblNDUCINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fV2luU0NQDQogICAgICAgIH0s
DQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJWTXdhcmUgVG9vbHMiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJ
dGVtX1ZNd2FyZQ0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiR2l0Ig0KICAgICAgICAgICAgVGV4
dCA9ICRTY3JpcHQ6SXRlbV9HaXQNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIk1vYmFYdGVybSIN
CiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fTW9iYVh0ZXJtDQogICAgICAgIH0sDQogICAgICAgIEB7DQogICAgICAg
ICAgICBJZCA9ICJDYWxjIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9DYWxjDQogICAgICAgIH0sDQogICAgICAg
IEB7DQogICAgICAgICAgICBJZCA9ICJPZmZpY2UiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX09mZmljZQ0KICAg
ICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiUG93ZXJTaGVsbCINCiAgICAgICAgICAgIFRleHQgPSAkU2Ny
aXB0Okl0ZW1fUG93ZXJzaGVsbA0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiQW55RGVzayINCiAg
ICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fQW55RGVzaw0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAg
SWQgPSAiRmlyZXdhbGwiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX0ZpcmV3YWxsDQogICAgICAgIH0sDQogICAg
ICAgIEB7DQogICAgICAgICAgICBJZCA9ICJSZHAiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX0VzY3JpdG9yaW9S
ZW1vdG8NCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIklQdjYiDQogICAgICAgICAgICBUZXh0ID0g
JFNjcmlwdDpJdGVtX0lQdjYNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIlNlYXJjaCINCiAgICAg
ICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fQnVzcXVlZGENCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElk
ID0gIlRhc2tiYXIiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX0JhcnJhVGFyZWFzDQogICAgICAgIH0NCiAgICAp
DQp9DQoNCg0KDQpmdW5jdGlvbiBTaG93LUN1c3RvbVdpbkNvbnNvbGUgew0KDQogICAgJENob2ljZXMgPSBAKEdldC1DdXN0b21X
aW5DaG9pY2VzKQ0KDQogICAgJENoZWNrZWQgPSBAe30NCg0KDQogICAgZm9yZWFjaCAoJENob2ljZSBpbiAkQ2hvaWNlcykgew0K
DQogICAgICAgICRDaGVja2VkWyRDaG9pY2UuSWRdID0gJGZhbHNlDQogICAgfQ0KDQoNCiAgICB3aGlsZSAoJHRydWUpIHsNCg0K
ICAgICAgICBXcml0ZS1Ib3N0ICIiDQogICAgICAgIFdyaXRlLUhvc3QgIk51bWVybzogdGlsZGEgbyBkZXN0aWxkYS4gQTogdG9k
YXMuIE46IG5pbmd1bmEuIEVudGVyOiBhcGxpY2FyLiBROiBjYW5jZWxhci4iDQogICAgICAgIFdyaXRlLUhvc3QgIiINCg0KDQog
ICAgICAgIGZvciAoJEluZGV4ID0gMDsgJEluZGV4IC1sdCAkQ2hvaWNlcy5Db3VudDsgJEluZGV4KyspIHsNCg0KICAgICAgICAg
ICAgJE1hcmsgPSAiICINCg0KICAgICAgICAgICAgaWYgKCRDaGVja2VkWyRDaG9pY2VzWyRJbmRleF0uSWRdKSB7DQoNCiAgICAg
ICAgICAgICAgICAkTWFyayA9ICJYIg0KICAgICAgICAgICAgfQ0KDQoNCiAgICAgICAgICAgIFdyaXRlLUhvc3QgKCJbezB9XSB7
MX0uIHsyfSIgLWYgJE1hcmssICgkSW5kZXggKyAxKSwgJENob2ljZXNbJEluZGV4XS5UZXh0KQ0KICAgICAgICB9DQoNCg0KICAg
ICAgICAkQW5zd2VyID0gUmVhZC1Ib3N0ICJPcGNpb24iDQoNCg0KICAgICAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVT
cGFjZSgkQW5zd2VyKSkgew0KDQogICAgICAgICAgICAkUGlja2VkID0gQCgNCiAgICAgICAgICAgICAgICAkQ2hvaWNlcyB8DQog
ICAgICAgICAgICAgICAgICAgIFdoZXJlLU9iamVjdCB7ICRDaGVja2VkWyRfLklkXSB9IHwNCiAgICAgICAgICAgICAgICAgICAg
Rm9yRWFjaC1PYmplY3QgeyAkXy5JZCB9DQogICAgICAgICAgICApDQoNCg0KICAgICAgICAgICAgaWYgKCRQaWNrZWQuQ291bnQg
LWVxIDApIHsNCg0KICAgICAgICAgICAgICAgIFdyaXRlLUhvc3QgIlRpbGRhIGFsIG1lbm9zIHVuYSBvcGNpb24uIg0KDQogICAg
ICAgICAgICAgICAgY29udGludWUNCiAgICAgICAgICAgIH0NCg0KDQogICAgICAgICAgICByZXR1cm4gLCRQaWNrZWQNCiAgICAg
ICAgfQ0KDQoNCiAgICAgICAgaWYgKCRBbnN3ZXIgLWVxICJRIiAtb3IgJEFuc3dlciAtZXEgInEiKSB7DQoNCiAgICAgICAgICAg
IHJldHVybiAkbnVsbA0KICAgICAgICB9DQoNCg0KICAgICAgICBpZiAoJEFuc3dlciAtZXEgIkEiIC1vciAkQW5zd2VyIC1lcSAi
YSIpIHsNCg0KICAgICAgICAgICAgZm9yZWFjaCAoJENob2ljZSBpbiAkQ2hvaWNlcykgew0KDQogICAgICAgICAgICAgICAgJENo
ZWNrZWRbJENob2ljZS5JZF0gPSAkdHJ1ZQ0KICAgICAgICAgICAgfQ0KDQogICAgICAgICAgICBjb250aW51ZQ0KICAgICAgICB9
DQoNCg0KICAgICAgICBpZiAoJEFuc3dlciAtZXEgIk4iIC1vciAkQW5zd2VyIC1lcSAibiIpIHsNCg0KICAgICAgICAgICAgZm9y
ZWFjaCAoJENob2ljZSBpbiAkQ2hvaWNlcykgew0KDQogICAgICAgICAgICAgICAgJENoZWNrZWRbJENob2ljZS5JZF0gPSAkZmFs
c2UNCiAgICAgICAgICAgIH0NCg0KICAgICAgICAgICAgY29udGludWUNCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJE51bWJlciA9
IDANCg0KDQogICAgICAgIGlmICgNCiAgICAgICAgICAgIFtpbnRdOjpUcnlQYXJzZSgkQW5zd2VyLCBbcmVmXSROdW1iZXIpIC1h
bmQNCiAgICAgICAgICAgICROdW1iZXIgLWdlIDEgLWFuZA0KICAgICAgICAgICAgJE51bWJlciAtbGUgJENob2ljZXMuQ291bnQN
CiAgICAgICAgKSB7DQoNCiAgICAgICAgICAgICRJZCA9ICRDaG9pY2VzWyROdW1iZXIgLSAxXS5JZA0KDQogICAgICAgICAgICAk
Q2hlY2tlZFskSWRdID0gLW5vdCAkQ2hlY2tlZFskSWRdDQogICAgICAgIH0NCiAgICB9DQp9DQoNCg0KDQpmdW5jdGlvbiBTaG93
LUN1c3RvbVdpbkZvcm0gew0KDQogICAgaWYgKC1ub3QgKCJDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93IiAtYXMgW3R5cGVdKSkg
ew0KDQogICAgICAgIEFkZC1UeXBlIC1OYW1lc3BhY2UgQ3VzdG9tV2luIC1OYW1lIEN1c3RvbVdpbldpbmRvdyAtTWVtYmVyRGVm
aW5pdGlvbiBAIg0KW1N5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlcy5EbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0NCnB1Ymxp
YyBzdGF0aWMgZXh0ZXJuIGJvb2wgU2V0V2luZG93UG9zKFN5c3RlbS5JbnRQdHIgaFduZCwgU3lzdGVtLkludFB0ciBoV25kSW5z
ZXJ0QWZ0ZXIsIGludCBYLCBpbnQgWSwgaW50IGN4LCBpbnQgY3ksIHVpbnQgdUZsYWdzKTsNCltTeXN0ZW0uUnVudGltZS5JbnRl
cm9wU2VydmljZXMuRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildDQpwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIFNldEZvcmVncm91
bmRXaW5kb3coU3lzdGVtLkludFB0ciBoV25kKTsNCltTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXMuRGxsSW1wb3J0KCJ1
c2VyMzIuZGxsIildDQpwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIEJyaW5nV2luZG93VG9Ub3AoU3lzdGVtLkludFB0ciBoV25k
KTsNCltTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXMuRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildDQpwdWJsaWMgc3RhdGlj
IGV4dGVybiBTeXN0ZW0uSW50UHRyIEdldEZvcmVncm91bmRXaW5kb3coKTsNCltTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2Vydmlj
ZXMuRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildDQpwdWJsaWMgc3RhdGljIGV4dGVybiB1aW50IEdldFdpbmRvd1RocmVhZFByb2Nl
c3NJZChTeXN0ZW0uSW50UHRyIGhXbmQsIFN5c3RlbS5JbnRQdHIgUHJvY2Vzc0lkKTsNCltTeXN0ZW0uUnVudGltZS5JbnRlcm9w
U2VydmljZXMuRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiKV0NCnB1YmxpYyBzdGF0aWMgZXh0ZXJuIHVpbnQgR2V0Q3VycmVudFRo
cmVhZElkKCk7DQpbU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLkRsbEltcG9ydCgidXNlcjMyLmRsbCIpXQ0KcHVibGlj
IHN0YXRpYyBleHRlcm4gYm9vbCBBdHRhY2hUaHJlYWRJbnB1dCh1aW50IGlkQXR0YWNoLCB1aW50IGlkQXR0YWNoVG8sIGJvb2wg
ZkF0dGFjaCk7DQoiQA0KICAgIH0NCg0KDQogICAgJENob2ljZXMgPSBAKEdldC1DdXN0b21XaW5DaG9pY2VzKQ0KDQogICAgJENh
bnZhcyA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDI0NCwgMjQ2LCAyNDgpDQoNCiAgICAkSW5rID0gW1N5c3Rl
bS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMTUsIDIzLCA0MikNCg0KICAgICRNdXRlZCA9IFtTeXN0ZW0uRHJhd2luZy5Db2xv
cl06OkZyb21BcmdiKDcxLCA4NSwgMTA1KQ0KDQogICAgJEFjY2VudCA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21Bcmdi
KDM3LCA5OSwgMjM1KQ0KDQogICAgJEFjY2VudERhcmsgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyOSwgNzgs
IDIxNikNCg0KICAgICRMaW5lID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMjI2LCAyMzIsIDI0MCkNCg0KICAg
ICRDYXJkID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUNCg0KDQogICAgJEZvcm0gPSBOZXctT2JqZWN0IFN5c3RlbS5X
aW5kb3dzLkZvcm1zLkZvcm0NCg0KICAgICRGb3JtLlRleHQgPSAiQ3VzdG9tV2luIg0KDQogICAgJEZvcm0uU3RhcnRQb3NpdGlv
biA9ICJNYW51YWwiDQoNCiAgICAkRm9ybS5Gb3JtQm9yZGVyU3R5bGUgPSAiTm9uZSINCg0KICAgICRGb3JtLldpbmRvd1N0YXRl
ID0gIk5vcm1hbCINCg0KICAgICRGb3JtLktleVByZXZpZXcgPSAkdHJ1ZQ0KDQogICAgJEZvcm0uU2hvd0luVGFza2JhciA9ICR0
cnVlDQoNCiAgICAkU2NyZWVuQm91bmRzID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNjcmVlbl06OlByaW1hcnlTY3JlZW4uQm91
bmRzDQoNCiAgICAkRm9ybS5Cb3VuZHMgPSAkU2NyZWVuQm91bmRzDQoNCiAgICAkRm9ybS5Gb250ID0gTmV3LU9iamVjdCBTeXN0
ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDEwKQ0KDQogICAgJEZvcm0uQmFja0NvbG9yID0gJENhbnZhcw0KDQogICAgJEZv
cm0uRm9yZUNvbG9yID0gJEluaw0KDQogICAgJEZvcm0uVG9wTW9zdCA9ICR0cnVlDQoNCg0KICAgICRIZWFkZXIgPSBOZXctT2Jq
ZWN0IFN5c3RlbS5XaW5kb3dzLkZvcm1zLlBhbmVsDQoNCiAgICAkSGVhZGVyLkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0u
RHJhd2luZy5Qb2ludCgwLCAwKQ0KDQogICAgJEhlYWRlci5TaXplID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5TaXplKDcw
MCwgMTA4KQ0KDQogICAgJEhlYWRlci5CYWNrQ29sb3IgPSAkQWNjZW50DQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJEhlYWRl
cikNCg0KDQogICAgJFRpdGxlID0gTmV3LU9iamVjdCBTeXN0ZW0uV2luZG93cy5Gb3Jtcy5MYWJlbA0KDQogICAgJFRpdGxlLlRl
eHQgPSAiLS0gU0VMRUNDSU9OQSBRVUUgUVVFUkVTIEFQTElDQVIgLS0iDQoNCiAgICAkVGl0bGUuQXV0b1NpemUgPSAkZmFsc2UN
Cg0KICAgICRUaXRsZS5UZXh0QWxpZ24gPSBbU3lzdGVtLkRyYXdpbmcuQ29udGVudEFsaWdubWVudF06Ok1pZGRsZUNlbnRlcg0K
DQogICAgJFRpdGxlLlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoNjQwLCAzNikNCg0KICAgICRUaXRsZS5G
b250ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDI2LCBbU3lzdGVtLkRyYXdpbmcuRm9udFN0
eWxlXTo6Qm9sZCkNCg0KICAgICRUaXRsZS5Gb3JlQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpXaGl0ZQ0KDQogICAg
JFRpdGxlLkJhY2tDb2xvciA9ICRBY2NlbnQNCg0KICAgICRUaXRsZS5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdp
bmcuUG9pbnQoMjgsIDI2KQ0KDQogICAgJEhlYWRlci5Db250cm9scy5BZGQoJFRpdGxlKQ0KDQoNCiAgICAkSGludCA9IE5ldy1P
YmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuTGFiZWwNCg0KICAgICRIaW50LlRleHQgPSAiTmFkYSBlbXBpZXphIHRpbGRhZG8u
IE1hcmNhIGxvIHF1ZSBxdWVyZXMgYXBsaWNhci4gTG8gZGVtYXMgbm8gc2UgbW9kaWZpY2EuIg0KDQogICAgJEhpbnQuQXV0b1Np
emUgPSAkZmFsc2UNCg0KICAgICRIaW50LlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoNjQwLCAyNCkNCg0K
ICAgICRIaW50LkZvbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMTApDQoNCiAgICAkSGlu
dC5Gb3JlQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyMTksIDIzNCwgMjU0KQ0KDQogICAgJEhpbnQu
QmFja0NvbG9yID0gJEFjY2VudA0KDQogICAgJEhpbnQuTG9jYXRpb24gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50
KDI4LCA2NikNCg0KICAgICRIZWFkZXIuQ29udHJvbHMuQWRkKCRIaW50KQ0KDQoNCiAgICAkTGlzdENhcmQgPSBOZXctT2JqZWN0
IFN5c3RlbS5XaW5kb3dzLkZvcm1zLlBhbmVsDQoNCiAgICAkTGlzdENhcmQuTG9jYXRpb24gPSBOZXctT2JqZWN0IFN5c3RlbS5E
cmF3aW5nLlBvaW50KDI0LCAxMjgpDQoNCiAgICAkTGlzdENhcmQuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6
ZSg2NTIsIDQ1MikNCg0KICAgICRMaXN0Q2FyZC5CYWNrQ29sb3IgPSAkTGluZQ0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRkKCRM
aXN0Q2FyZCkNCg0KDQogICAgJExpc3QgPSBOZXctT2JqZWN0IFN5c3RlbS5XaW5kb3dzLkZvcm1zLkNoZWNrZWRMaXN0Qm94DQoN
CiAgICAkTGlzdC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMSwgMSkNCg0KICAgICRMaXN0LlNp
emUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoNjUwLCA0NTApDQoNCiAgICAkTGlzdC5DaGVja09uQ2xpY2sgPSAk
dHJ1ZQ0KDQogICAgJExpc3QuQm9yZGVyU3R5bGUgPSAiTm9uZSINCg0KICAgICRMaXN0LkludGVncmFsSGVpZ2h0ID0gJGZhbHNl
DQoNCiAgICAkTGlzdC5EcmF3TW9kZSA9ICJPd25lckRyYXdGaXhlZCINCg0KICAgICRMaXN0Lkl0ZW1IZWlnaHQgPSA0NA0KDQog
ICAgJExpc3QuRm9udCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuRm9udCgiU2Vnb2UgVUkiLCAxMSkNCg0KICAgICRMaXN0
LkJhY2tDb2xvciA9ICRDYXJkDQoNCiAgICAkTGlzdC5Gb3JlQ29sb3IgPSAkSW5rDQoNCiAgICAkc2NyaXB0OkN1c3RvbVdpbkhv
dmVySW5kZXggPSAtMQ0KDQoNCiAgICAkTGlzdC5BZGRfRHJhd0l0ZW0oew0KDQogICAgICAgIHBhcmFtKCRzZW5kZXIsICRlKQ0K
DQogICAgICAgIGlmICgkZS5JbmRleCAtbHQgMCkgeyByZXR1cm4gfQ0KDQogICAgICAgICRHcmFwaGljcyA9ICRlLkdyYXBoaWNz
DQoNCiAgICAgICAgJEdyYXBoaWNzLlNtb290aGluZ01vZGUgPSBbU3lzdGVtLkRyYXdpbmcuRHJhd2luZzJELlNtb290aGluZ01v
ZGVdOjpBbnRpQWxpYXMNCg0KICAgICAgICAkQm91bmRzID0gJGUuQm91bmRzDQoNCiAgICAgICAgJElzQ2hlY2tlZCA9ICRMaXN0
LkdldEl0ZW1DaGVja2VkKCRlLkluZGV4KQ0KDQogICAgICAgICRJc0hvdCA9ICRlLkluZGV4IC1lcSAkc2NyaXB0OkN1c3RvbVdp
bkhvdmVySW5kZXgNCg0KICAgICAgICAkQmFjayA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OldoaXRlDQoNCiAgICAgICAgaWYg
KCRJc0NoZWNrZWQpIHsNCg0KICAgICAgICAgICAgJEJhY2sgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyMzks
IDI0NiwgMjU1KQ0KDQogICAgICAgIH0NCiAgICAgICAgZWxzZWlmICgkSXNIb3QpIHsNCg0KICAgICAgICAgICAgJEJhY2sgPSBb
U3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyNDgsIDI1MCwgMjUyKQ0KICAgICAgICB9DQoNCiAgICAgICAgJEJhY2tC
cnVzaCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU29saWRCcnVzaCAkQmFjaw0KDQogICAgICAgICRHcmFwaGljcy5GaWxs
UmVjdGFuZ2xlKCRCYWNrQnJ1c2gsICRCb3VuZHMpDQoNCiAgICAgICAgJEJhY2tCcnVzaC5EaXNwb3NlKCkNCg0KICAgICAgICAk
Qm94VG9wID0gJEJvdW5kcy5ZICsgW2ludF0oKCRCb3VuZHMuSGVpZ2h0IC0gMTgpIC8gMikNCg0KICAgICAgICAkQm94ID0gTmV3
LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5SZWN0YW5nbGUoKCRCb3VuZHMuWCArIDIyKSwgJEJveFRvcCwgMTgsIDE4KQ0KDQogICAg
ICAgICRCbHVlID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMzcsIDk5LCAyMzUpDQoNCiAgICAgICAgaWYgKCRJ
c0NoZWNrZWQpIHsNCg0KICAgICAgICAgICAgJEZpbGwgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNvbGlkQnJ1c2ggJEJs
dWUNCg0KICAgICAgICAgICAgJEdyYXBoaWNzLkZpbGxSZWN0YW5nbGUoJEZpbGwsICRCb3gpDQoNCiAgICAgICAgICAgICRGaWxs
LkRpc3Bvc2UoKQ0KDQogICAgICAgICAgICAkTWFya1BlbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUGVuIChbU3lzdGVt
LkRyYXdpbmcuQ29sb3JdOjpXaGl0ZSksIDINCg0KICAgICAgICAgICAgJFBvaW50cyA9IE5ldy1PYmplY3QgJ1N5c3RlbS5EcmF3
aW5nLlBvaW50W10nIDMNCg0KICAgICAgICAgICAgJFBvaW50c1swXSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQg
KCgkQm94LlggKyA0KSwgKCRCb3guWSArIDkpKQ0KDQogICAgICAgICAgICAkUG9pbnRzWzFdID0gTmV3LU9iamVjdCBTeXN0ZW0u
RHJhd2luZy5Qb2ludCAoKCRCb3guWCArIDgpLCAoJEJveC5ZICsgMTMpKQ0KDQogICAgICAgICAgICAkUG9pbnRzWzJdID0gTmV3
LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCAoKCRCb3guWCArIDE0KSwgKCRCb3guWSArIDUpKQ0KDQogICAgICAgICAgICAk
R3JhcGhpY3MuRHJhd0xpbmVzKCRNYXJrUGVuLCAkUG9pbnRzKQ0KDQogICAgICAgICAgICAkTWFya1Blbi5EaXNwb3NlKCkNCg0K
ICAgICAgICB9DQogICAgICAgIGVsc2Ugew0KDQogICAgICAgICAgICAkQm94UGVuID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2lu
Zy5QZW4gKFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDE0OCwgMTYzLCAxODQpKQ0KDQogICAgICAgICAgICAkR3Jh
cGhpY3MuRHJhd1JlY3RhbmdsZSgkQm94UGVuLCAkQm94KQ0KDQogICAgICAgICAgICAkQm94UGVuLkRpc3Bvc2UoKQ0KICAgICAg
ICB9DQoNCiAgICAgICAgJFRleHRCcnVzaCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU29saWRCcnVzaCAoW1N5c3RlbS5E
cmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMTUsIDIzLCA0MikpDQoNCiAgICAgICAgJFRleHRSZWN0ID0gTmV3LU9iamVjdCBTeXN0
ZW0uRHJhd2luZy5SZWN0YW5nbGUoKCRCb3VuZHMuWCArIDQ4KSwgJEJvdW5kcy5ZLCAoJEJvdW5kcy5XaWR0aCAtIDYwKSwgJEJv
dW5kcy5IZWlnaHQpDQoNCiAgICAgICAgJEZvcm1hdCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU3RyaW5nRm9ybWF0DQoN
CiAgICAgICAgJEZvcm1hdC5MaW5lQWxpZ25tZW50ID0gW1N5c3RlbS5EcmF3aW5nLlN0cmluZ0FsaWdubWVudF06OkNlbnRlcg0K
DQogICAgICAgICRGb3JtYXQuVHJpbW1pbmcgPSBbU3lzdGVtLkRyYXdpbmcuU3RyaW5nVHJpbW1pbmddOjpFbGxpcHNpc0NoYXJh
Y3Rlcg0KDQogICAgICAgICRGb3JtYXQuRm9ybWF0RmxhZ3MgPSBbU3lzdGVtLkRyYXdpbmcuU3RyaW5nRm9ybWF0RmxhZ3NdOjpO
b1dyYXANCg0KICAgICAgICAkR3JhcGhpY3MuRHJhd1N0cmluZyhbc3RyaW5nXSRMaXN0Lkl0ZW1zWyRlLkluZGV4XSwgJGUuRm9u
dCwgJFRleHRCcnVzaCwgJFRleHRSZWN0LCAkRm9ybWF0KQ0KDQogICAgICAgICRUZXh0QnJ1c2guRGlzcG9zZSgpDQoNCiAgICAg
ICAgJEZvcm1hdC5EaXNwb3NlKCkNCg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQogICAgJExpc3QuQWRkX01vdXNlTW92ZSh7
DQoNCiAgICAgICAgcGFyYW0oJHNlbmRlciwgJGUpDQoNCiAgICAgICAgJEluZGV4ID0gJExpc3QuSW5kZXhGcm9tUG9pbnQoJGUu
TG9jYXRpb24pDQoNCiAgICAgICAgaWYgKCRJbmRleCAtbmUgJHNjcmlwdDpDdXN0b21XaW5Ib3ZlckluZGV4KSB7DQoNCiAgICAg
ICAgICAgICRzY3JpcHQ6Q3VzdG9tV2luSG92ZXJJbmRleCA9ICRJbmRleA0KDQogICAgICAgICAgICAkTGlzdC5JbnZhbGlkYXRl
KCkNCiAgICAgICAgfQ0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoNCiAgICAkTGlzdC5BZGRfTW91c2VMZWF2ZSh7DQoNCiAg
ICAgICAgJHNjcmlwdDpDdXN0b21XaW5Ib3ZlckluZGV4ID0gLTENCg0KICAgICAgICAkTGlzdC5JbnZhbGlkYXRlKCkNCg0KICAg
IH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQoNCiAgICBmb3JlYWNoICgkQ2hvaWNlIGluICRDaG9pY2VzKSB7DQoNCiAgICAgICAgW3Zv
aWRdJExpc3QuSXRlbXMuQWRkKCRDaG9pY2UuVGV4dCwgJGZhbHNlKQ0KICAgIH0NCg0KDQogICAgJExpc3RDYXJkLkNvbnRyb2xz
LkFkZCgkTGlzdCkNCg0KDQogICAgJE5vdGljZSA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuTGFiZWwNCg0KICAg
ICROb3RpY2UuVGV4dCA9ICIiDQoNCiAgICAkTm90aWNlLkF1dG9TaXplID0gJGZhbHNlDQoNCiAgICAkTm90aWNlLlNpemUgPSBO
ZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoNjQwLCAyMCkNCg0KICAgICROb3RpY2UuRm9udCA9IE5ldy1PYmplY3QgU3lz
dGVtLkRyYXdpbmcuRm9udCgiU2Vnb2UgVUkiLCA5KQ0KDQogICAgJE5vdGljZS5Gb3JlQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcu
Q29sb3JdOjpGcm9tQXJnYigxODUsIDI4LCAyOCkNCg0KICAgICROb3RpY2UuQmFja0NvbG9yID0gJENhbnZhcw0KDQogICAgJE5v
dGljZS5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMjQsIDU4OCkNCg0KICAgICRGb3JtLkNvbnRy
b2xzLkFkZCgkTm90aWNlKQ0KDQoNCiAgICAkTGlzdC5BZGRfU2VsZWN0ZWRJbmRleENoYW5nZWQoew0KDQogICAgICAgICROb3Rp
Y2UuVGV4dCA9ICIiDQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KDQogICAgZnVuY3Rpb24gU2V0LUN1c3RvbVdpbkZsYXRC
dXR0b24gew0KDQogICAgICAgIHBhcmFtKA0KICAgICAgICAgICAgJEJ1dHRvbiwNCiAgICAgICAgICAgIFtib29sXSRQcmltYXJ5
DQogICAgICAgICkNCg0KICAgICAgICAkQnV0dG9uLkZsYXRTdHlsZSA9ICJGbGF0Ig0KDQogICAgICAgICRCdXR0b24uQ3Vyc29y
ID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1zLkN1cnNvcnNdOjpIYW5kDQoNCiAgICAgICAgJEJ1dHRvbi5Gb250ID0gTmV3LU9iamVj
dCBTeXN0ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDEwKQ0KDQogICAgICAgIGlmICgkUHJpbWFyeSkgew0KDQogICAgICAg
ICAgICAkQnV0dG9uLkJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDM3LCA5OSwgMjM1KQ0KDQog
ICAgICAgICAgICAkQnV0dG9uLkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OldoaXRlDQoNCiAgICAgICAgICAg
ICRCdXR0b24uRmxhdEFwcGVhcmFuY2UuQm9yZGVyU2l6ZSA9IDANCg0KICAgICAgICAgICAgJEJ1dHRvbi5GbGF0QXBwZWFyYW5j
ZS5Nb3VzZU92ZXJCYWNrQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyOSwgNzgsIDIxNikNCg0KICAg
ICAgICAgICAgJEJ1dHRvbi5GbGF0QXBwZWFyYW5jZS5Nb3VzZURvd25CYWNrQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3Jd
OjpGcm9tQXJnYigzMCwgNjQsIDE3NSkNCg0KICAgICAgICAgICAgcmV0dXJuDQogICAgICAgIH0NCg0KICAgICAgICAkQnV0dG9u
LkJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OldoaXRlDQoNCiAgICAgICAgJEJ1dHRvbi5Gb3JlQ29sb3IgPSBb
U3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigxNSwgMjMsIDQyKQ0KDQogICAgICAgICRCdXR0b24uRmxhdEFwcGVhcmFu
Y2UuQm9yZGVyU2l6ZSA9IDENCg0KICAgICAgICAkQnV0dG9uLkZsYXRBcHBlYXJhbmNlLkJvcmRlckNvbG9yID0gW1N5c3RlbS5E
cmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMjAzLCAyMTMsIDIyNSkNCg0KICAgICAgICAkQnV0dG9uLkZsYXRBcHBlYXJhbmNlLk1v
dXNlT3ZlckJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDI0MSwgMjQ1LCAyNDkpDQoNCiAgICAg
ICAgJEJ1dHRvbi5GbGF0QXBwZWFyYW5jZS5Nb3VzZURvd25CYWNrQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9t
QXJnYigyMjYsIDIzMiwgMjQwKQ0KICAgIH0NCg0KDQogICAgJE1hcmtBbGwgPSBOZXctT2JqZWN0IFN5c3RlbS5XaW5kb3dzLkZv
cm1zLkJ1dHRvbg0KDQogICAgJE1hcmtBbGwuVGV4dCA9ICJNYXJjYXIgdG9kbyINCg0KICAgICRNYXJrQWxsLkxvY2F0aW9uID0g
TmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgyNCwgNjE2KQ0KDQogICAgJE1hcmtBbGwuU2l6ZSA9IE5ldy1PYmplY3Qg
U3lzdGVtLkRyYXdpbmcuU2l6ZSgxMzIsIDQwKQ0KDQogICAgU2V0LUN1c3RvbVdpbkZsYXRCdXR0b24gLUJ1dHRvbiAkTWFya0Fs
bCAtUHJpbWFyeSAkZmFsc2UNCg0KICAgICRNYXJrQWxsLkFkZF9DbGljayh7DQoNCiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAk
SW5kZXggLWx0ICRMaXN0Lkl0ZW1zLkNvdW50OyAkSW5kZXgrKykgew0KDQogICAgICAgICAgICAkTGlzdC5TZXRJdGVtQ2hlY2tl
ZCgkSW5kZXgsICR0cnVlKQ0KICAgICAgICB9DQoNCiAgICAgICAgJE5vdGljZS5UZXh0ID0gIiINCg0KICAgIH0uR2V0TmV3Q2xv
c3VyZSgpKQ0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRkKCRNYXJrQWxsKQ0KDQoNCiAgICAkQ2xlYXJBbGwgPSBOZXctT2JqZWN0
IFN5c3RlbS5XaW5kb3dzLkZvcm1zLkJ1dHRvbg0KDQogICAgJENsZWFyQWxsLlRleHQgPSAiRGVzbWFyY2FyIHRvZG8iDQoNCiAg
ICAkQ2xlYXJBbGwuTG9jYXRpb24gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50KDE2NCwgNjE2KQ0KDQogICAgJENs
ZWFyQWxsLlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoMTQ4LCA0MCkNCg0KICAgIFNldC1DdXN0b21XaW5G
bGF0QnV0dG9uIC1CdXR0b24gJENsZWFyQWxsIC1QcmltYXJ5ICRmYWxzZQ0KDQogICAgJENsZWFyQWxsLkFkZF9DbGljayh7DQoN
CiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAkSW5kZXggLWx0ICRMaXN0Lkl0ZW1zLkNvdW50OyAkSW5kZXgrKykgew0KDQogICAg
ICAgICAgICAkTGlzdC5TZXRJdGVtQ2hlY2tlZCgkSW5kZXgsICRmYWxzZSkNCiAgICAgICAgfQ0KDQogICAgICAgICROb3RpY2Uu
VGV4dCA9ICIiDQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KICAgICRGb3JtLkNvbnRyb2xzLkFkZCgkQ2xlYXJBbGwpDQoN
Cg0KICAgICRDYW5jZWwgPSBOZXctT2JqZWN0IFN5c3RlbS5XaW5kb3dzLkZvcm1zLkJ1dHRvbg0KDQogICAgJENhbmNlbC5UZXh0
ID0gIkNhbmNlbGFyIg0KDQogICAgJENhbmNlbC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoNDA0
LCA2MTYpDQoNCiAgICAkQ2FuY2VsLlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoMTIwLCA0MCkNCg0KICAg
ICRDYW5jZWwuRGlhbG9nUmVzdWx0ID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1zLkRpYWxvZ1Jlc3VsdF06OkNhbmNlbA0KDQogICAg
U2V0LUN1c3RvbVdpbkZsYXRCdXR0b24gLUJ1dHRvbiAkQ2FuY2VsIC1QcmltYXJ5ICRmYWxzZQ0KDQogICAgJEZvcm0uQ2FuY2Vs
QnV0dG9uID0gJENhbmNlbA0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRkKCRDYW5jZWwpDQoNCg0KICAgICRBcHBseSA9IE5ldy1P
YmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAgICAkQXBwbHkuVGV4dCA9ICJBcGxpY2FyIg0KDQogICAgJEFw
cGx5LkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCg1MzYsIDYxNikNCg0KICAgICRBcHBseS5TaXpl
ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5TaXplKDE0MCwgNDApDQoNCiAgICBTZXQtQ3VzdG9tV2luRmxhdEJ1dHRvbiAt
QnV0dG9uICRBcHBseSAtUHJpbWFyeSAkdHJ1ZQ0KDQogICAgJEFwcGx5LkFkZF9DbGljayh7DQoNCiAgICAgICAgJEFueUNoZWNr
ZWQgPSAkZmFsc2UNCg0KDQogICAgICAgIGZvciAoJEluZGV4ID0gMDsgJEluZGV4IC1sdCAkTGlzdC5JdGVtcy5Db3VudDsgJElu
ZGV4KyspIHsNCg0KICAgICAgICAgICAgaWYgKCRMaXN0LkdldEl0ZW1DaGVja2VkKCRJbmRleCkpIHsNCg0KICAgICAgICAgICAg
ICAgICRBbnlDaGVja2VkID0gJHRydWUNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KDQoNCiAgICAgICAgaWYgKC1ub3QgJEFu
eUNoZWNrZWQpIHsNCg0KICAgICAgICAgICAgJE5vdGljZS5UZXh0ID0gIlRpbGRhIGFsIG1lbm9zIHVuYSBvcGNpb24uIg0KDQog
ICAgICAgICAgICByZXR1cm4NCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJEZvcm0uRGlhbG9nUmVzdWx0ID0gW1N5c3RlbS5XaW5k
b3dzLkZvcm1zLkRpYWxvZ1Jlc3VsdF06Ok9LDQoNCiAgICAgICAgJEZvcm0uQ2xvc2UoKQ0KDQogICAgfS5HZXROZXdDbG9zdXJl
KCkpDQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJEFwcGx5KQ0KDQogICAgJEZvcm0uQWNjZXB0QnV0dG9uID0gJEFwcGx5DQoN
Cg0KICAgICRVcGRhdGVMYXlvdXQgPSB7DQoNCiAgICAgICAgJFdpZHRoID0gJEZvcm0uQ2xpZW50U2l6ZS5XaWR0aA0KDQogICAg
ICAgICRIZWlnaHQgPSAkRm9ybS5DbGllbnRTaXplLkhlaWdodA0KDQoNCiAgICAgICAgaWYgKCRXaWR0aCAtbHQgNjQwIC1vciAk
SGVpZ2h0IC1sdCA0ODApIHsNCg0KICAgICAgICAgICAgcmV0dXJuDQogICAgICAgIH0NCg0KDQogICAgICAgICRIZWFkZXJIZWln
aHQgPSAxNDgNCg0KICAgICAgICAkSGVhZGVyLlNldEJvdW5kcygwLCAwLCAkV2lkdGgsICRIZWFkZXJIZWlnaHQpDQoNCg0KICAg
ICAgICAkQ29udGVudFdpZHRoID0gJFdpZHRoIC0gMTIwDQoNCg0KICAgICAgICBpZiAoJENvbnRlbnRXaWR0aCAtZ3QgMTA4MCkg
ew0KDQogICAgICAgICAgICAkQ29udGVudFdpZHRoID0gMTA4MA0KICAgICAgICB9DQoNCg0KICAgICAgICAkTGVmdCA9IFtpbnRd
KCgkV2lkdGggLSAkQ29udGVudFdpZHRoKSAvIDIpDQoNCiAgICAgICAgJFRpdGxlLlNldEJvdW5kcygwLCAzMiwgJFdpZHRoLCA1
NikNCg0KICAgICAgICAkSGludC5TZXRCb3VuZHMoJExlZnQsIDk2LCAkQ29udGVudFdpZHRoLCAyOCkNCg0KDQogICAgICAgICRC
dXR0b25Ub3AgPSAkSGVpZ2h0IC0gODgNCg0KICAgICAgICAkTm90aWNlVG9wID0gJEJ1dHRvblRvcCAtIDMyDQoNCiAgICAgICAg
JExpc3RUb3AgPSAkSGVhZGVySGVpZ2h0ICsgMjgNCg0KICAgICAgICAkTGlzdEhlaWdodCA9ICROb3RpY2VUb3AgLSAkTGlzdFRv
cCAtIDE2DQoNCg0KICAgICAgICBpZiAoJExpc3RIZWlnaHQgLWx0IDE2MCkgew0KDQogICAgICAgICAgICAkTGlzdEhlaWdodCA9
IDE2MA0KICAgICAgICB9DQoNCg0KICAgICAgICAkTGlzdENhcmQuU2V0Qm91bmRzKCRMZWZ0LCAkTGlzdFRvcCwgJENvbnRlbnRX
aWR0aCwgJExpc3RIZWlnaHQpDQoNCiAgICAgICAgJExpc3QuU2V0Qm91bmRzKDEsIDEsICgkQ29udGVudFdpZHRoIC0gMiksICgk
TGlzdEhlaWdodCAtIDIpKQ0KDQogICAgICAgICROb3RpY2UuU2V0Qm91bmRzKCRMZWZ0LCAkTm90aWNlVG9wLCAkQ29udGVudFdp
ZHRoLCAyNCkNCg0KDQogICAgICAgICRNYXJrQWxsLlNldEJvdW5kcygkTGVmdCwgJEJ1dHRvblRvcCwgMTYwLCA1MikNCg0KICAg
ICAgICAkQ2xlYXJBbGwuU2V0Qm91bmRzKCgkTGVmdCArIDE3NiksICRCdXR0b25Ub3AsIDE4MCwgNTIpDQoNCiAgICAgICAgJEFw
cGx5LlNldEJvdW5kcygoJExlZnQgKyAkQ29udGVudFdpZHRoIC0gMTgwKSwgJEJ1dHRvblRvcCwgMTgwLCA1MikNCg0KICAgICAg
ICAkQ2FuY2VsLlNldEJvdW5kcygoJExlZnQgKyAkQ29udGVudFdpZHRoIC0gMTgwIC0gMTYgLSAxNTApLCAkQnV0dG9uVG9wLCAx
NTAsIDUyKQ0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpDQoNCg0KICAgICYgJFVwZGF0ZUxheW91dA0KDQoNCiAgICAkRm9ybS5BZGRf
U2hvd24oew0KDQogICAgICAgICRGb3JtLkJvdW5kcyA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2Ny
ZWVuLkJvdW5kcw0KDQogICAgICAgICRGb3JtLldpbmRvd1N0YXRlID0gIk5vcm1hbCINCg0KICAgICAgICAmICRVcGRhdGVMYXlv
dXQNCg0KICAgICAgICAkSGFuZGxlID0gJEZvcm0uSGFuZGxlDQoNCiAgICAgICAgJEZsYWdzID0gW3VpbnQzMl0oMHgwMDAxIC1i
b3IgMHgwMDAyIC1ib3IgMHgwMDQwKQ0KDQogICAgICAgIFt2b2lkXVtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6U2V0V2lu
ZG93UG9zKA0KICAgICAgICAgICAgJEhhbmRsZSwNCiAgICAgICAgICAgIFtJbnRQdHJdKC0xKSwNCiAgICAgICAgICAgIDAsDQog
ICAgICAgICAgICAwLA0KICAgICAgICAgICAgMCwNCiAgICAgICAgICAgIDAsDQogICAgICAgICAgICAkRmxhZ3MNCiAgICAgICAg
KQ0KDQogICAgICAgICRGb3JlZ3JvdW5kID0gW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpHZXRGb3JlZ3JvdW5kV2luZG93
KCkNCg0KICAgICAgICAkRm9yZWdyb3VuZFRocmVhZCA9IFtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6R2V0V2luZG93VGhy
ZWFkUHJvY2Vzc0lkKA0KICAgICAgICAgICAgJEZvcmVncm91bmQsDQogICAgICAgICAgICBbSW50UHRyXTo6WmVybw0KICAgICAg
ICApDQoNCiAgICAgICAgJEN1cnJlbnRUaHJlYWQgPSBbQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OkdldEN1cnJlbnRUaHJl
YWRJZCgpDQoNCg0KICAgICAgICBpZiAoJEZvcmVncm91bmRUaHJlYWQgLW5lICRDdXJyZW50VGhyZWFkKSB7DQoNCiAgICAgICAg
ICAgIFt2b2lkXVtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6QXR0YWNoVGhyZWFkSW5wdXQoDQogICAgICAgICAgICAgICAg
JEZvcmVncm91bmRUaHJlYWQsDQogICAgICAgICAgICAgICAgJEN1cnJlbnRUaHJlYWQsDQogICAgICAgICAgICAgICAgJHRydWUN
CiAgICAgICAgICAgICkNCiAgICAgICAgfQ0KDQoNCiAgICAgICAgW3ZvaWRdW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpC
cmluZ1dpbmRvd1RvVG9wKCRIYW5kbGUpDQoNCiAgICAgICAgW3ZvaWRdW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpTZXRG
b3JlZ3JvdW5kV2luZG93KCRIYW5kbGUpDQoNCg0KICAgICAgICBpZiAoJEZvcmVncm91bmRUaHJlYWQgLW5lICRDdXJyZW50VGhy
ZWFkKSB7DQoNCiAgICAgICAgICAgIFt2b2lkXVtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6QXR0YWNoVGhyZWFkSW5wdXQo
DQogICAgICAgICAgICAgICAgJEZvcmVncm91bmRUaHJlYWQsDQogICAgICAgICAgICAgICAgJEN1cnJlbnRUaHJlYWQsDQogICAg
ICAgICAgICAgICAgJGZhbHNlDQogICAgICAgICAgICApDQogICAgICAgIH0NCg0KDQogICAgICAgICRGb3JtLlRvcE1vc3QgPSAk
dHJ1ZQ0KDQogICAgICAgICRGb3JtLkFjdGl2YXRlKCkNCg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQoNCiAgICAkRm9ybS5U
b3BNb3N0ID0gJHRydWUNCg0KICAgICRSZXN1bHQgPSAkRm9ybS5TaG93RGlhbG9nKCkNCg0KICAgICRQaWNrZWQgPSBOZXctT2Jq
ZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQ0KDQoNCiAgICBpZiAoJFJlc3VsdCAtZXEgW1N5c3Rl
bS5XaW5kb3dzLkZvcm1zLkRpYWxvZ1Jlc3VsdF06Ok9LKSB7DQoNCiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAkSW5kZXggLWx0
ICRDaG9pY2VzLkNvdW50OyAkSW5kZXgrKykgew0KDQogICAgICAgICAgICBpZiAoJExpc3QuR2V0SXRlbUNoZWNrZWQoJEluZGV4
KSkgew0KDQogICAgICAgICAgICAgICAgJFBpY2tlZC5BZGQoJENob2ljZXNbJEluZGV4XS5JZCkNCiAgICAgICAgICAgIH0NCiAg
ICAgICAgfQ0KICAgIH0NCg0KDQogICAgJEZvcm0uRGlzcG9zZSgpDQoNCg0KICAgIGlmICgkUmVzdWx0IC1uZSBbU3lzdGVtLldp
bmRvd3MuRm9ybXMuRGlhbG9nUmVzdWx0XTo6T0sgLW9yICRQaWNrZWQuQ291bnQgLWVxIDApIHsNCg0KICAgICAgICByZXR1cm4g
JG51bGwNCiAgICB9DQoNCg0KICAgIHJldHVybiAsJFBpY2tlZC5Ub0FycmF5KCkNCn0NCg0KDQoNCmZ1bmN0aW9uIFJlYWQtQ3Vz
dG9tV2luU2VsZWN0aW9uIHsNCg0KICAgICRBcGFydG1lbnQgPSBbVGhyZWFkaW5nLlRocmVhZF06OkN1cnJlbnRUaHJlYWQuQXBh
cnRtZW50U3RhdGUNCg0KDQogICAgaWYgKCIkQXBhcnRtZW50IiAtZXEgIlNUQSIpIHsNCg0KICAgICAgICB0cnkgew0KDQogICAg
ICAgICAgICBBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5XaW5kb3dzLkZvcm1zDQoNCiAgICAgICAgICAgIEFkZC1UeXBl
IC1Bc3NlbWJseU5hbWUgU3lzdGVtLkRyYXdpbmcNCg0KICAgICAgICAgICAgW1N5c3RlbS5XaW5kb3dzLkZvcm1zLkFwcGxpY2F0
aW9uXTo6RW5hYmxlVmlzdWFsU3R5bGVzKCkNCg0KICAgICAgICAgICAgJFBpY2tlZCA9IFNob3ctQ3VzdG9tV2luRm9ybQ0KDQoN
CiAgICAgICAgICAgIGlmICgkbnVsbCAtZXEgJFBpY2tlZCkgew0KDQogICAgICAgICAgICAgICAgcmV0dXJuICRudWxsDQogICAg
ICAgICAgICB9DQoNCg0KICAgICAgICAgICAgcmV0dXJuICwkUGlja2VkDQogICAgICAgIH0NCiAgICAgICAgY2F0Y2ggew0KDQog
ICAgICAgICAgICBXcml0ZS1Mb2cgIk5vIHNlIHB1ZG8gYWJyaXIgbGEgdmVudGFuYSBkZSBzZWxlY2Npb246ICQoJF8uRXhjZXB0
aW9uLk1lc3NhZ2UpIiAiV0FSTiINCiAgICAgICAgfQ0KICAgIH0NCg0KDQogICAgJFBpY2tlZCA9IFNob3ctQ3VzdG9tV2luQ29u
c29sZQ0KDQoNCiAgICBpZiAoJG51bGwgLWVxICRQaWNrZWQpIHsNCg0KICAgICAgICByZXR1cm4gJG51bGwNCiAgICB9DQoNCg0K
ICAgIHJldHVybiAsJFBpY2tlZA0KfQ0KDQoNCldyaXRlLUxvZyAiTWVudTogMjAyNjEwMjNqIg0KDQoNCiRTZWxlY3RlZCA9IFJl
YWQtQ3VzdG9tV2luU2VsZWN0aW9uDQoNCg0KaWYgKCRudWxsIC1lcSAkU2VsZWN0ZWQpIHsNCg0KICAgIFdyaXRlLUhvc3QgIiIN
CiAgICBXcml0ZS1Ib3N0ICJDYW5jZWxhZG8uIE5vIHNlIG1vZGlmaWNvIG5hZGEuIg0KICAgIFdyaXRlLUhvc3QgIiINCg0KICAg
IFdyaXRlLUxvZyAiRWwgdXN1YXJpbyBjYW5jZWxvIGxhIHNlbGVjY2lvbi4iICJXQVJOIg0KDQogICAgU3RvcC1DdXN0b21XaW4g
LUNvZGUgMA0KfQ0KDQoNCiRTZWxlY3RlZCA9IEAoJFNlbGVjdGVkKQ0KDQpXcml0ZS1Mb2cgKCJPcGNpb25lcyBlbGVnaWRhczog
IiArICgkU2VsZWN0ZWQgLWpvaW4gIiwgIikpDQoNCg0KJEFyY2hpdGVjdHVyZSA9IEdldC1Pc0FyY2hpdGVjdHVyZQ0KDQpXcml0
ZS1Mb2cgIkFycXVpdGVjdHVyYTogJEFyY2hpdGVjdHVyZSINCg0KDQppZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQW55RGVzayIp
IHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgSW5zdGFsbC1VbmF0dGVuZGVkQW55RGVzaw0KDQoNCiAgICAgICAgaWYgKFtpbnRd
JHNjcmlwdDpBbnlEZXNrRXhpdENvZGUgLW5lIDApIHsNCg0KICAgICAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkFueURlc2s6
IG5vIHNlIGNvbXBsZXRvLiBDb2RpZ28gJCgkc2NyaXB0OkFueURlc2tFeGl0Q29kZSkuIg0KICAgICAgICB9DQoNCiAgICB9DQog
ICAgY2F0Y2ggew0KDQogICAgICAgICRGYWlsTGluZSA9ICRfLkludm9jYXRpb25JbmZvLlNjcmlwdExpbmVOdW1iZXINCg0KICAg
ICAgICBBZGQtRGVwbG95RmFpbHVyZSAiQW55RGVzayAobGluZWEgJHtGYWlsTGluZX0pOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdl
KSINCiAgICB9DQp9DQoNCg0KJEFwcE5hbWVzID0gQCgNCiAgICAkU2VsZWN0ZWQgfCBXaGVyZS1PYmplY3Qgew0KICAgICAgICAk
XyAtaW4gQCgiTm90ZXBhZCsrIiwgIjctWmlwIiwgIkZpcmVmb3giLCAiR29vZ2xlIENocm9tZSIsICJQdVRUWSIsICJXaW5TQ1Ai
LCAiVk13YXJlIFRvb2xzIikNCiAgICB9DQopDQoNCg0KaWYgKCRBcHBOYW1lcy5Db3VudCAtZ3QgMCkgew0KDQogICAgSW5zdGFs
bC1CYXNpY0FwcGxpY2F0aW9ucyAtQXJjaGl0ZWN0dXJlICRBcmNoaXRlY3R1cmUgLU5hbWVzICRBcHBOYW1lcw0KfQ0KDQoNCmlm
ICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJHaXQiKSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIEludm9rZS1CaW5TY3JpcHQgLU5h
bWUgIkdpdCINCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlvbkluZm8uU2Ny
aXB0TGluZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJHaXQgKGxpbmVhICR7RmFpbExpbmV9KTogJCgkXy5F
eGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJNb2JhWHRlcm0iKSB7DQoN
CiAgICB0cnkgew0KDQogICAgICAgIEludm9rZS1CaW5TY3JpcHQgLU5hbWUgIk1vYmFYdGVybSINCg0KICAgIH0NCiAgICBjYXRj
aCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlvbkluZm8uU2NyaXB0TGluZU51bWJlcg0KDQogICAgICAgIEFk
ZC1EZXBsb3lGYWlsdXJlICJNb2JhWHRlcm0gKGxpbmVhICR7RmFpbExpbmV9KTogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQog
ICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJDYWxjIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBJbnZv
a2UtQmluU2NyaXB0IC1OYW1lICJDYWxjIg0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExpbmUgPSAkXy5J
bnZvY2F0aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkNhbGN1bGFkb3JhIChs
aW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1j
b250YWlucyAiT2ZmaWNlIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBJbnN0YWxsLU9mZmljZTIwMjRMdHNjIC1BcmNoaXRl
Y3R1cmUgJEFyY2hpdGVjdHVyZQ0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExpbmUgPSAkXy5JbnZvY2F0
aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIk9mZmljZSAyMDI0IExUU0MgKGxp
bmVhICR7RmFpbExpbmV9KTogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNv
bnRhaW5zICJQb3dlclNoZWxsIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBXcml0ZS1Mb2cgIkVqZWN1dGFuZG8gQ29ycmVy
IFBvd2Vyc2hlbGwuIg0KDQogICAgICAgIFtOZXQuU2VydmljZVBvaW50TWFuYWdlcl06OlNlY3VyaXR5UHJvdG9jb2wgPSBbTmV0
LlNlY3VyaXR5UHJvdG9jb2xUeXBlXTo6VGxzMTINCg0KICAgICAgICAkUG93ZXJTaGVsbFNjcmlwdCA9IEludm9rZS1SZXN0TWV0
aG9kIGANCiAgICAgICAgICAgIC1VcmkgImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS9lbWlqdW5rZS93aW5iYXNp
Yy9tYWluL3BzLnBzMSIgYA0KICAgICAgICAgICAgLVVzZUJhc2ljUGFyc2luZw0KDQogICAgICAgIGlmICgkUG93ZXJTaGVsbFNj
cmlwdCAtaXMgW1N5c3RlbS5BcnJheV0pIHsNCg0KICAgICAgICAgICAgJFBvd2VyU2hlbGxTY3JpcHQgPSAkUG93ZXJTaGVsbFNj
cmlwdCAtam9pbiAiYG4iDQogICAgICAgIH0NCiAgICAgICAgZWxzZWlmICgkUG93ZXJTaGVsbFNjcmlwdCAtaXNub3QgW3N0cmlu
Z10pIHsNCg0KICAgICAgICAgICAgJFBvd2VyU2hlbGxTY3JpcHQgPSBbc3RyaW5nXSRQb3dlclNoZWxsU2NyaXB0DQogICAgICAg
IH0NCg0KDQogICAgICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRQb3dlclNoZWxsU2NyaXB0KSkgew0KDQog
ICAgICAgICAgICB0aHJvdyAicHMucHMxIGxsZWdvIHZhY2lvLiINCiAgICAgICAgfQ0KDQoNCiAgICAgICAgaWYgKCRQb3dlclNo
ZWxsU2NyaXB0LkNvbnRhaW5zKCJsaW5lcyBjb2xsYXBzZWQiKSkgew0KDQogICAgICAgICAgICB0aHJvdyAicHMucHMxIG5vIHNl
IHB1ZWRlIGVqZWN1dGFyOiBlbCBhcmNoaXZvIHN1YmlkbyBlc3RhIGNvbGFwc2Fkby4iDQogICAgICAgIH0NCg0KDQogICAgICAg
IEludm9rZS1FeHByZXNzaW9uICRQb3dlclNoZWxsU2NyaXB0DQoNCiAgICAgICAgV3JpdGUtTG9nICJDb3JyZXIgUG93ZXJzaGVs
bCB0ZXJtaW5vLiIgIk9LIg0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExpbmUgPSAkXy5JbnZvY2F0aW9u
SW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkNvcnJlciBQb3dlcnNoZWxsIChsaW5l
YSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1jb250
YWlucyAiRmlyZXdhbGwiKSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIERpc2FibGUtV2luZG93c0ZpcmV3YWxsUGVybWFuZW50
bHkNCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkZpcmV3YWxsOiAkKCRfLkV4Y2Vw
dGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIlJkcCIpIHsNCg0KICAgIHRyeSB7
DQoNCiAgICAgICAgRW5hYmxlLVJlbW90ZURlc2t0b3BXaXRob3V0TmxhDQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAg
IEFkZC1EZXBsb3lGYWlsdXJlICJFc2NyaXRvcmlvIHJlbW90bzogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0K
DQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJJUHY2Iikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBEaXNhYmxlLUlQdjZD
b21wbGV0ZWx5DQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJJUHY2OiAkKCRfLkV4
Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KJFNjcmlwdDpIaWRlU2VhcmNoID0gJFNlbGVjdGVkIC1jb250YWlucyAi
U2VhcmNoIg0KDQokU2NyaXB0OkFsaWduTGVmdCA9ICRTZWxlY3RlZCAtY29udGFpbnMgIlRhc2tiYXIiDQoNCg0KaWYgKCRTY3Jp
cHQ6SGlkZVNlYXJjaCAtb3IgJFNjcmlwdDpBbGlnbkxlZnQpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgU2V0LVRhc2tiYXJM
YXlvdXQNCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkJhcnJhIGRlIHRhcmVhczog
JCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCkdldC1DaGlsZEl0ZW0gLUxpdGVyYWxQYXRoICRUZW1wRGly
IC1GaWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICBSZW1vdmUtSXRlbSAtRm9yY2UgLUVycm9yQWN0aW9u
IFNpbGVudGx5Q29udGludWUNCg0KDQpXcml0ZS1Ib3N0ICIiDQpXcml0ZS1Ib3N0ICI9PT09PT09PT09PT09PT09PT09PT09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iDQpXcml0ZS1Ib3N0ICIgUkVTVUxUQURPIg0KV3JpdGUtSG9zdCAi
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09Ig0KV3JpdGUtSG9zdCAi
Ig0KV3JpdGUtSG9zdCAiTG9nOiAkTG9nRmlsZSINCldyaXRlLUhvc3QgIiINCg0KDQppZiAoJFNjcmlwdDpGYWlsdXJlcy5Db3Vu
dCAtZXEgMCkgew0KDQogICAgaWYgKCRBcHBOYW1lcy5Db3VudCAtZ3QgMCkgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIlByb2dy
YW1hcyBlbGVnaWRvcyAgICAgICAgICAgICAgIDogSU5TVEFMQURPUyBPIFlBIFBSRVNFTlRFUyINCiAgICB9DQoNCg0KICAgIGlm
ICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJBbnlEZXNrIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkFueURlc2sgICAgICAgICAg
ICAgICAgICAgICAgICAgOiBJTlNUQUxBRE8iDQoNCiAgICAgICAgaWYgKCRTY3JpcHQ6TmV3SUQpIHsNCg0KICAgICAgICAgICAg
V3JpdGUtSG9zdCAiQW55RGVzayBJRCAgICAgICAgICAgICAgICAgICAgICA6ICRTY3JpcHQ6TmV3SUQiDQogICAgICAgIH0NCiAg
ICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJHaXQiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiR2l0ICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICA6IElOU1RBTEFETyBPIFlBIFBSRVNFTlRFIg0KICAgIH0NCg0KDQogICAgaWYgKCRT
ZWxlY3RlZCAtY29udGFpbnMgIk1vYmFYdGVybSIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJNb2JhWHRlcm0gICAgICAgICAg
ICAgICAgICAgICAgIDogQ09QSUFETyINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJDYWxjIikgew0K
DQogICAgICAgIFdyaXRlLUhvc3QgIkNhbGN1bGFkb3JhICAgICAgICAgICAgICAgICAgICAgOiBBQklFUlRBIg0KICAgIH0NCg0K
DQogICAgaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIk9mZmljZSIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJPZmZpY2UgMjAy
NCBMVFNDICAgICAgICAgICAgICAgIDogSU5TVEFMQURPIg0KICAgIH0NCg0KDQogICAgaWYgKCRTZWxlY3RlZCAtY29udGFpbnMg
IlBvd2VyU2hlbGwiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiQ29ycmVyIFBvd2Vyc2hlbGwgICAgICAgICAgICAgICA6IEVK
RUNVVEFETyINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJGaXJld2FsbCIpIHsNCg0KICAgICAgICBX
cml0ZS1Ib3N0ICJGaXJld2FsbCBkZSBXaW5kb3dzICAgICAgICAgICAgIDogREVTSEFCSUxJVEFETyINCiAgICB9DQoNCg0KICAg
IGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJSZHAiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiRXNjcml0b3JpbyByZW1vdG8g
ICAgICAgICAgICAgICA6IEhBQklMSVRBRE8iDQogICAgICAgIFdyaXRlLUhvc3QgIkF1dGVudGljYWNpb24gYSBuaXZlbCBkZSBy
ZWQgICAgOiBERVNNQVJDQURBIg0KICAgIH0NCg0KDQogICAgaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIklQdjYiKSB7DQoNCiAg
ICAgICAgV3JpdGUtSG9zdCAiSVB2NiAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IERFU0hBQklMSVRBRE8gQUwgUkVJTklD
SUFSIg0KICAgIH0NCg0KDQogICAgaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIlNlYXJjaCIpIHsNCg0KICAgICAgICBXcml0ZS1I
b3N0ICJCdXNxdWVkYSBlbiBsYSBiYXJyYSBkZSB0YXJlYXMgOiBPQ1VMVEEiDQogICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVk
IC1jb250YWlucyAiVGFza2JhciIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJBbGluZWFjaW9uIGRlIGxhIGJhcnJhICAgICAg
ICAgOiBJWlFVSUVSREEiDQogICAgfQ0KDQoNCiAgICBXcml0ZS1Ib3N0ICIiDQogICAgV3JpdGUtSG9zdCAiQ1VTVE9NV0lOIEZJ
TkFMSVpBRE8iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4NCiAgICBXcml0ZS1Ib3N0ICIiDQoNCg0KICAgIGlmICgkU2VsZWN0ZWQg
LWNvbnRhaW5zICJJUHY2Iikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIlJlaW5pY2llIGVsIGVxdWlwbyBwYXJhIGNvbXBsZXRh
ciBsYSBkZXNoYWJpbGl0YWNpb24gZGUgSVB2Ni4iDQogICAgICAgIFdyaXRlLUhvc3QgIiINCiAgICB9DQoNCg0KICAgIFdyaXRl
LUxvZyAiQ3VzdG9tV2luIGZpbmFsaXphZG8uIiAiT0siDQoNCiAgICBTdG9wLUN1c3RvbVdpbiAtQ29kZSAwDQp9DQoNCg0KV3Jp
dGUtSG9zdCAiQ1VTVE9NV0lOIEZJTkFMSVpBRE8gQ09OIEVSUk9SRVMiIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93DQoNCldyaXRl
LUhvc3QgIiINCg0KZm9yZWFjaCAoJEZhaWx1cmUgaW4gJFNjcmlwdDpGYWlsdXJlcykgew0KDQogICAgV3JpdGUtSG9zdCAiIC0g
JEZhaWx1cmUiDQp9DQoNCldyaXRlLUhvc3QgIiINCldyaXRlLUhvc3QgIlJldmlzZTogJExvZ0ZpbGUiDQpXcml0ZS1Ib3N0ICIi
DQoNCldyaXRlLUxvZyAiQ3VzdG9tV2luIGZpbmFsaXphZG8gY29uIGVycm9yZXMuIiAiV0FSTiINCg0KU3RvcC1DdXN0b21XaW4g
LUNvZGUgMQ0KDQoNCiMgRmluIGRlbCBzY3JpcHQuDQo=
'@

    $Packed = $Packed -replace "\s", ""

    return [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($Packed)
    )
}


function Test-PopupCode {

    param (
        [string]$Code
    )


    if ([string]::IsNullOrWhiteSpace($Code)) {

        return $false
    }


    if ($Code -match '\[\d+ lines collapsed\]') {

        return $false
    }


    if (-not $Code.Contains("Fin del script.")) {

        return $false
    }


    if (-not $Code.Contains("function Show-CustomWinForm")) {

        return $false
    }


    return $true
}


function Read-PopupScriptText {

    $FileName = "popup.ps1"

    $LocalPath = ""


    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {

        $LocalPath = Join-Path $PSScriptRoot "bin\$FileName"
    }


    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath)) {

        Write-Log "Ejecutando bin\$FileName local."

        return [System.IO.File]::ReadAllText($LocalPath)
    }


    $Uri = "https://raw.githubusercontent.com/emijunke/winbasic/main/bin/$FileName"

    Write-Log "Ejecutando $Uri"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Code = Invoke-RestMethod -Uri $Uri -UseBasicParsing


    if ($Code -is [System.Array]) {

        $Code = $Code -join "`n"
    }
    elseif ($Code -isnot [string]) {

        $Code = [string]$Code
    }


    return $Code
}


function Invoke-CustomWinPopup {

    $Code = $null


    try {

        $Code = Read-PopupScriptText
    }
    catch {

        Write-Log "No se pudo leer popup.ps1: $($_.Exception.Message)" "WARN"
    }


    if (-not (Test-PopupCode -Code $Code)) {

        Write-Log "popup.ps1 en GitHub esta cortado. Se usa el menu incluido en CustomWin." "WARN"


        try {

            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

            [void][System.Windows.Forms.MessageBox]::Show(
                "popup.ps1 en GitHub esta cortado. Se abre el menu incluido en CustomWin.",
                "CustomWin",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        catch {
        }


        $Code = Get-PopupFallbackCode
    }


    if (-not (Test-PopupCode -Code $Code)) {

        throw "El menu incluido en CustomWin esta incompleto."
    }


    $SavedErrorAction = $ErrorActionPreference


    try {

        Invoke-Expression $Code
    }
    finally {

        $ErrorActionPreference = $SavedErrorAction
    }
}


function Get-OfficeDeploymentToolUrl {

    $Pattern = 'https://download\.microsoft\.com/download/[0-9a-fA-F-]+/officedeploymenttool_[0-9-]+\.exe'

    $Fallback = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"


    try {

        $Page = Invoke-WebRequest `
            -Uri "https://www.microsoft.com/en-us/download/details.aspx?id=49117" `
            -UseBasicParsing `
            -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"


        $Match = [regex]::Match($Page.Content, $Pattern)


        if ($Match.Success) {

            return $Match.Value
        }
    }
    catch {
    }


    return $Fallback
}



function Get-Office2024LtscVersion {

    $Base = $null


    try {

        $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )

        $Key = $Base.OpenSubKey(
            "SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
        )


        if ($Key) {

            $Products = [string]$Key.GetValue("ProductReleaseIds")

            $Version = [string]$Key.GetValue("VersionToReport")

            $Key.Close()


            foreach ($Product in ($Products -split ",")) {

                if ($Product.Trim() -eq "ProPlus2024Volume") {

                    if ([string]::IsNullOrWhiteSpace($Version)) {

                        return "ProPlus2024Volume"
                    }


                    return $Version.Trim()
                }
            }
        }
    }
    finally {

        if ($Base) {

            $Base.Close()
        }
    }


    foreach ($Entry in (Get-UninstallEntries)) {

        if ($Entry.DisplayName -match '^Microsoft Office LTSC Professional Plus 2024') {

            if ([string]::IsNullOrWhiteSpace([string]$Entry.DisplayVersion)) {

                return [string]$Entry.DisplayName
            }


            return [string]$Entry.DisplayVersion
        }
    }


    return ""
}



function Test-Office2024LtscSourceReady {

    param (
        [Parameter(Mandatory = $true)]
        [string]$OfficeDir
    )


    $DataDir = Join-Path $OfficeDir "Office\Data"

    $Catalog = Join-Path $DataDir "v64.cab"


    if (-not (Test-Path -LiteralPath $Catalog)) {

        return $false
    }


    $Core = Get-ChildItem `
        -LiteralPath $DataDir `
        -Recurse `
        -Filter "stream.x64.x-none.dat" `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 1GB } |
        Select-Object -First 1


    if (-not $Core) {

        return $false
    }


    $Language = Get-ChildItem `
        -LiteralPath $DataDir `
        -Recurse `
        -Filter "stream.x64.es-es.dat" `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 50MB } |
        Select-Object -First 1


    if (-not $Language) {

        return $false
    }


    return $true
}



function Install-Office2024Ltsc {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )


    if ($Architecture -ne "x64") {

        throw "Esta configuracion de Office 2024 LTSC es solo para Windows de 64 bits."
    }


    $Installed = Get-Office2024LtscVersion


    if (-not [string]::IsNullOrWhiteSpace($Installed)) {

        Write-Log "Office 2024 LTSC ya esta instalado ($Installed). No se descarga ni se reinstala." "OK"

        return
    }


    $OfficeDir = "C:\Office2024LTSC"

    $SetupExe = Join-Path $OfficeDir "setup.exe"

    $ConfigPath = Join-Path $OfficeDir "configuration.xml"

    New-Item -ItemType Directory -Path $OfficeDir -Force | Out-Null


    Write-Log "Preparando Office 2024 LTSC en $OfficeDir..."


    try {

        $ToolUrl = Get-OfficeDeploymentToolUrl

        $ToolFile = Join-Path $OfficeDir "officedeploymenttool.exe"


        Write-Log "Descargando Office Deployment Tool..."

        Write-Log "Origen: $ToolUrl"

        Save-WebFile -Uri $ToolUrl -Destination $ToolFile


        $ToolSize = (Get-Item -LiteralPath $ToolFile).Length


        if ($ToolSize -lt 400KB) {

            throw "El Office Deployment Tool descargado parece invalido. Tamano: $ToolSize bytes."
        }


        $Trust = Test-InstallerTrust -Path $ToolFile

        Write-Log "Integridad de Office Deployment Tool: $Trust" "OK"

        Unblock-File -LiteralPath $ToolFile -ErrorAction SilentlyContinue


        $ExtractLog = Join-Path $OfficeDir "odt-extract.log"

        $ExtractCode = Invoke-InstallerProcess `
            -FilePath $ToolFile `
            -Arguments "/quiet /norestart /extract:`"$OfficeDir`" /log:`"$ExtractLog`"" `
            -TimeoutSeconds 600 `
            -WorkingDirectory $OfficeDir


        if ($ExtractCode -notin @(0, 3010, 1641, $null)) {

            throw "No se pudo extraer setup.exe. Codigo: $ExtractCode."
        }
    }
    catch {

        if (-not (Test-Path -LiteralPath $SetupExe)) {

            throw
        }


        Write-Log "No se pudo actualizar setup.exe. Se usa el que ya esta en $OfficeDir. $($_.Exception.Message)" "WARN"
    }


    if (-not (Test-Path -LiteralPath $SetupExe)) {

        throw "No se encontro setup.exe en $OfficeDir."
    }


    $ConfigXml = @(
        '<Configuration>'
        '  <Add OfficeClientEdition="64" Channel="PerpetualVL2024">'
        '    <Product ID="ProPlus2024Volume">'
        '      <Language ID="es-es" />'
        '      <ExcludeApp ID="Lync" />'
        '      <ExcludeApp ID="OneDrive" />'
        '    </Product>'
        '  </Add>'
        '  <Display Level="None" AcceptEULA="TRUE" />'
        '  <Property Name="SharedComputerLicensing" Value="0" />'
        '  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />'
        '  <Property Name="DeviceBasedLicensing" Value="0" />'
        '</Configuration>'
    ) -join "`r`n"

    $Utf8 = New-Object System.Text.UTF8Encoding $false

    [System.IO.File]::WriteAllText($ConfigPath, $ConfigXml, $Utf8)


    if (Test-Office2024LtscSourceReady -OfficeDir $OfficeDir) {

        Write-Log "Los archivos de Office 2024 LTSC ya estan en $OfficeDir. Se omite la descarga." "OK"

    }
    else {

        Write-Log "Descargando los archivos de Office 2024 LTSC. Puede tardar bastante..."


        $DownloadCode = Invoke-InstallerProcess `
            -FilePath $SetupExe `
            -Arguments "/download `"$ConfigPath`"" `
            -TimeoutSeconds 14400 `
            -WorkingDirectory $OfficeDir


        if ($DownloadCode -notin @(0, 3010, 1641, $null)) {

            throw "La descarga de Office 2024 LTSC fallo. Codigo: $DownloadCode."
        }


        if (-not (Test-Office2024LtscSourceReady -OfficeDir $OfficeDir)) {

            throw "La descarga termino, pero no quedo el paquete completo de Office en $OfficeDir."
        }


        Write-Log "Descarga de Office completada." "OK"
    }


    Write-Log "Instalando Office 2024 LTSC sin ventanas..."


    $ConfigureCode = Invoke-InstallerProcess `
        -FilePath $SetupExe `
        -Arguments "/configure `"$ConfigPath`"" `
        -TimeoutSeconds 7200 `
        -WorkingDirectory $OfficeDir


    if ($ConfigureCode -notin @(0, 3010, 1641, $null)) {

        throw "La instalacion de Office 2024 LTSC fallo. Codigo: $ConfigureCode."
    }


    $Installed = Get-Office2024LtscVersion


    if ([string]::IsNullOrWhiteSpace($Installed)) {

        throw "Office 2024 LTSC no quedo registrado despues de la instalacion."
    }


    Write-Log "Office 2024 LTSC instalado ($Installed)." "OK"

    Write-Log "Los archivos de instalacion quedan en $OfficeDir."
}



function Disable-WindowsFirewallPermanently {

    Write-Log "Deshabilitando el Firewall de Windows en todas las redes..."


    Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False


    foreach ($Profile in @("DomainProfile", "PrivateProfile", "PublicProfile")) {

        Set-RegistryDword `
            -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\$Profile" `
            -Name "EnableFirewall" `
            -Value 0


        Set-RegistryDword `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$Profile" `
            -Name "EnableFirewall" `
            -Value 0
    }


    $StillEnabled = @(
        Get-NetFirewallProfile |
            Where-Object { $_.Enabled -eq $true }
    )


    if ($StillEnabled.Count -gt 0) {

        throw "Quedaron perfiles de firewall habilitados: $($StillEnabled.Name -join ', ')"
    }


    Write-Log "Firewall deshabilitado en Domain, Private y Public." "OK"

    Write-Log "La directiva local mantiene el firewall apagado despues de reiniciar." "OK"
}



function Enable-RemoteDesktopWithoutNla {

    Write-Log "Habilitando Escritorio remoto sin autenticacion de nivel de red..."


    Set-RegistryDword `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" `
        -Value 0


    Set-RegistryDword `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -Name "UserAuthentication" `
        -Value 0


    Set-RegistryDword `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -Name "fEnableWinStation" `
        -Value 1


    Set-RegistryDword `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
        -Name "fDenyTSConnections" `
        -Value 0


    Set-RegistryDword `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
        -Name "UserAuthentication" `
        -Value 0


    Set-Service -Name "TermService" -StartupType Automatic

    $Service = Get-Service -Name "TermService"


    if ($Service.Status -ne "Running") {

        Start-Service -Name "TermService"
    }


    foreach ($Group in @("Remote Desktop", "Escritorio remoto")) {

        try {

            Enable-NetFirewallRule -DisplayGroup $Group -ErrorAction Stop

        }
        catch {
        }
    }


    $Deny = Get-ItemProperty `
        -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections"


    $Nla = Get-ItemProperty `
        -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -Name "UserAuthentication"


    if ($Deny.fDenyTSConnections -ne 0 -or $Nla.UserAuthentication -ne 0) {

        throw "RDP no quedo habilitado sin autenticacion de nivel de red."
    }


    Write-Log "Escritorio remoto habilitado." "OK"

    Write-Log "Autenticacion a nivel de red desmarcada." "OK"
}



function Disable-IPv6Completely {

    Write-Log "Deshabilitando IPv6..."


    # 0xFF deshabilita IPv6 en todas las interfaces, salvo el loopback,
    # que Windows conserva. El valor se aplica al reiniciar.
    Set-RegistryDword `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
        -Name "DisabledComponents" `
        -Value 255


    $Bindings = @(
        Get-NetAdapterBinding `
            -ComponentID "ms_tcpip6" `
            -ErrorAction SilentlyContinue
    )


    foreach ($Binding in $Bindings) {

        if ($Binding.Enabled) {

            Disable-NetAdapterBinding `
                -Name $Binding.Name `
                -ComponentID "ms_tcpip6" `
                -ErrorAction SilentlyContinue
        }
    }


    $StillBound = @(
        Get-NetAdapterBinding `
            -ComponentID "ms_tcpip6" `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -eq $true }
    )


    if ($StillBound.Count -gt 0) {

        Write-Log `
            "IPv6 sigue enlazado en: $($StillBound.Name -join ', ')" `
            "WARN"
    }


    $Components = (
        Get-ItemProperty `
            -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
            -Name "DisabledComponents"
    ).DisabledComponents


    if ([int]$Components -ne 255) {

        throw "DisabledComponents no quedo en 255."
    }


    Write-Log "IPv6 deshabilitado en los adaptadores." "OK"

    Write-Log "DisabledComponents=255. Reinicie el equipo para completar el cambio." "WARN"
}



function Set-TaskbarLayoutOnKey {

    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryRoot
    )


    if ($Script:HideSearch) {

        Set-RegistryDword `
            -Path "$RegistryRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
            -Name "SearchboxTaskbarMode" `
            -Value 0


        # Sin esta marca, el Explorador trata el valor anterior como
        # ausente y vuelve a mostrar el cuadro de busqueda.
        Set-RegistryDword `
            -Path "$RegistryRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
            -Name "SearchboxTaskbarModeCache" `
            -Value 1
    }


    if ($Script:AlignLeft) {

        Set-RegistryDword `
            -Path "$RegistryRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "TaskbarAl" `
            -Value 0
    }
}



function Invoke-RegistryCommand {

    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )


    $Reg = "$env:SystemRoot\System32\reg.exe"


    if (
        [Environment]::Is64BitOperatingSystem -and
        -not [Environment]::Is64BitProcess
    ) {

        $Reg = "$env:SystemRoot\Sysnative\reg.exe"
    }


    $PreviousErrorAction = $ErrorActionPreference

    $ErrorActionPreference = "Continue"


    try {

        & $Reg @ArgumentList > $null

        return $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference = $PreviousErrorAction
    }
}



function Dismount-UserHive {

    param (
        [Parameter(Mandatory = $true)]
        [string]$HiveName
    )


    $Code = 1


    for ($Try = 1; $Try -le 5; $Try++) {

        [gc]::Collect()

        [gc]::WaitForPendingFinalizers()

        $Code = Invoke-RegistryCommand -ArgumentList @("unload", "HKU\$HiveName")


        if ($Code -eq 0) {

            return
        }


        Start-Sleep -Seconds 1
    }


    throw "No se pudo cerrar el perfil de registro $HiveName."
}



function Set-OfflineTaskbarLayout {

    param (

        [Parameter(Mandatory = $true)]
        [string]$NtUserPath,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )


    $HiveName = "CustomWinTaskbar"

    $Loaded = "Registry::HKEY_USERS\$HiveName"


    if (Test-Path -LiteralPath $Loaded) {

        Dismount-UserHive -HiveName $HiveName
    }


    $Code = Invoke-RegistryCommand -ArgumentList @(
        "load",
        "HKU\$HiveName",
        $NtUserPath
    )


    if ($Code -ne 0) {

        throw "No se pudo abrir el perfil de $Label."
    }


    try {

        Set-TaskbarLayoutOnKey -RegistryRoot $Loaded

        Write-Log "Barra de tareas aplicada a $Label." "OK"
    }
    finally {

        Dismount-UserHive -HiveName $HiveName
    }
}



function Stop-ExplorerShell {

    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {

        $Running = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)

        if ($Running.Count -eq 0) {

            return
        }


        foreach ($Process in $Running) {

            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }


        Start-Sleep -Milliseconds 200
    }
}



function Start-ExplorerShell {

    if (Get-Process -Name "explorer" -ErrorAction SilentlyContinue) {

        return
    }


    $TaskName = "CustomWinExplorer"

    $Schtasks = "$env:SystemRoot\System32\schtasks.exe"


    if (
        [Environment]::Is64BitOperatingSystem -and
        -not [Environment]::Is64BitProcess
    ) {

        $Schtasks = "$env:SystemRoot\Sysnative\schtasks.exe"
    }


    $ExplorerPath = "$env:SystemRoot\explorer.exe"

    $XmlPath = Join-Path $env:TEMP "CustomWinExplorer.xml"

    # Sin /ST: en Windows en espanol esa hora se rechazaba y el
    # Explorador quedaba elevado. LeastPrivilege usa el token limitado.
    $Xml = '<?xml version="1.0" encoding="UTF-16"?>' +
        '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' +
        '<Principals><Principal id="Author">' +
        '<LogonType>InteractiveToken</LogonType>' +
        '<RunLevel>LeastPrivilege</RunLevel>' +
        '</Principal></Principals>' +
        '<Settings>' +
        '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' +
        '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' +
        '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' +
        '<AllowHardTerminate>true</AllowHardTerminate>' +
        '<StartWhenAvailable>false</StartWhenAvailable>' +
        '<Enabled>true</Enabled>' +
        '<Hidden>true</Hidden>' +
        '<AllowStartOnDemand>true</AllowStartOnDemand>' +
        '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' +
        '</Settings>' +
        '<Actions Context="Author"><Exec><Command>' +
        $ExplorerPath +
        '</Command></Exec></Actions></Task>'

    $Started = $false

    $Detail = ""

    $PreviousErrorAction = $ErrorActionPreference

    $ErrorActionPreference = "Continue"


    try {

        [System.IO.File]::WriteAllText(
            $XmlPath,
            $Xml,
            [System.Text.Encoding]::Unicode
        )

        $CreateOutput = & $Schtasks /Create /TN $TaskName /XML $XmlPath /F 2>&1


        if ($LASTEXITCODE -eq 0) {

            $RunOutput = & $Schtasks /Run /TN $TaskName 2>&1


            for ($Wait = 1; $Wait -le 40; $Wait++) {

                if (Get-Process -Name "explorer" -ErrorAction SilentlyContinue) {

                    $Started = $true

                    break
                }


                Start-Sleep -Milliseconds 250
            }


            if (-not $Started) {

                $Detail = (($RunOutput | Out-String)).Trim()
            }
        }
        else {

            $Detail = (($CreateOutput | Out-String)).Trim()
        }
    }
    catch {

        $Detail = [string]$_.Exception.Message
    }
    finally {

        & $Schtasks /Delete /TN $TaskName /F 2>&1 | Out-Null

        Remove-Item -LiteralPath $XmlPath -Force -ErrorAction SilentlyContinue

        $ErrorActionPreference = $PreviousErrorAction
    }


    if ($Started -or (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {

        return
    }


    if (-not [string]::IsNullOrWhiteSpace($Detail)) {

        Write-Log "No se pudo iniciar el Explorador sin elevacion: $Detail" "WARN"
    }


    Start-Process -FilePath $ExplorerPath

    Write-Log "El Explorador se inicio desde la consola elevada." "WARN"
}



function Test-TaskbarLayoutApplied {

    if ($Script:HideSearch) {

        $SearchMode = (
            Get-ItemProperty `
                -LiteralPath "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
                -Name "SearchboxTaskbarMode"
        ).SearchboxTaskbarMode

        $SearchCache = (
            Get-ItemProperty `
                -LiteralPath "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
                -Name "SearchboxTaskbarModeCache"
        ).SearchboxTaskbarModeCache


        if ([int]$SearchMode -ne 0 -or [int]$SearchCache -ne 1) {

            return $false
        }
    }


    if ($Script:AlignLeft) {

        $Alignment = (
            Get-ItemProperty `
                -LiteralPath "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
                -Name "TaskbarAl"
        ).TaskbarAl


        if ([int]$Alignment -ne 0) {

            return $false
        }
    }


    return $true
}



function Set-TaskbarLayout {

    if ($Script:HideSearch -and $Script:AlignLeft) {

        Write-Log "Ocultando la busqueda y alineando la barra de tareas a la izquierda..."

    }
    elseif ($Script:HideSearch) {

        Write-Log "Ocultando el campo de busqueda de la barra de tareas..."

    }
    else {

        Write-Log "Alineando los iconos de la barra de tareas a la izquierda..."
    }


    $LiveRoots = @("HKCU:")


    $ProfileList = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"

    foreach ($Profile in @(Get-ChildItem -LiteralPath $ProfileList -ErrorAction SilentlyContinue)) {

        $Sid = $Profile.PSChildName

        if ($Sid -notlike "S-1-5-21-*" -and $Sid -notlike "S-1-12-1-*") {

            continue
        }


        $Image = (
            Get-ItemProperty `
                -LiteralPath $Profile.PSPath `
                -Name "ProfileImagePath" `
                -ErrorAction SilentlyContinue
        ).ProfileImagePath


        if ([string]::IsNullOrWhiteSpace($Image)) {

            continue
        }


        $Image = [Environment]::ExpandEnvironmentVariables([string]$Image)

        $NtUser = Join-Path $Image "NTUSER.DAT"

        if (-not (Test-Path -LiteralPath $NtUser)) {

            continue
        }


        $LoadedUser = "Registry::HKEY_USERS\$Sid"


        try {

            if (Test-Path -LiteralPath $LoadedUser) {

                if ($LiveRoots -notcontains $LoadedUser) {

                    $LiveRoots += $LoadedUser
                }

                continue
            }


            Set-OfflineTaskbarLayout -NtUserPath $NtUser -Label $Image
        }
        catch {

            Write-Log "No se pudo aplicar la barra de tareas en ${Image}: $($_.Exception.Message)" "WARN"
        }
    }


    $DefaultUser = Join-Path $env:SystemDrive "Users\Default\NTUSER.DAT"

    if (Test-Path -LiteralPath $DefaultUser) {

        Set-OfflineTaskbarLayout -NtUserPath $DefaultUser -Label "usuarios nuevos"
    }


    # El Explorador guarda la barra que tiene en memoria al cerrarse.
    # Primero se cierra y despues se escribe la configuracion.
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {

        Stop-ExplorerShell


        foreach ($LiveRoot in $LiveRoots) {

            if ($LiveRoot -eq "HKCU:" -or (Test-Path -LiteralPath $LiveRoot)) {

                Set-TaskbarLayoutOnKey -RegistryRoot $LiveRoot
            }
        }


        Start-Sleep -Milliseconds 400


        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {

            break
        }
    }


    Start-ExplorerShell

    Start-Sleep -Seconds 2


    Set-TaskbarLayoutOnKey -RegistryRoot "HKCU:"


    if (-not (Test-TaskbarLayoutApplied)) {

        Stop-ExplorerShell

        Set-TaskbarLayoutOnKey -RegistryRoot "HKCU:"

        Start-ExplorerShell

        Start-Sleep -Seconds 2

        Set-TaskbarLayoutOnKey -RegistryRoot "HKCU:"
    }


    if (-not (Test-TaskbarLayoutApplied)) {

        throw "La barra de tareas no quedo configurada."
    }


    if ($Script:HideSearch) {

        Write-Log "Campo de busqueda de la barra de tareas oculto." "OK"
    }


    if ($Script:AlignLeft) {

        Write-Log "Iconos de la barra de tareas alineados a la izquierda." "OK"
    }
}



function Get-AnyDeskService {

    return Get-Service `
        -Name "AnyDesk" `
        -ErrorAction SilentlyContinue
}



function Get-AnyDeskServicePid {

    $Service = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name='AnyDesk'" `
        -ErrorAction SilentlyContinue


    if ($Service -and $Service.ProcessId) {

        return [int]$Service.ProcessId
    }


    return 0
}



function Get-AnyDeskServiceExecutable {

    $Service = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name='AnyDesk'" `
        -ErrorAction SilentlyContinue


    if (-not $Service -or -not $Service.PathName) {

        return $null
    }


    $PathName = [string]$Service.PathName

    $Executable = $null


    if ($PathName -match '^"([^"]+\.exe)"') {

        $Executable = $Matches[1]

    }
    elseif ($PathName -match '^(\S+\.exe)') {

        $Executable = $Matches[1]
    }


    if (
        $Executable -and
        (Test-Path -LiteralPath $Executable) -and
        ($Executable -notlike "$TempDir\*")
    ) {

        return $Executable
    }


    return $null
}



function Find-InstalledAnyDesk {

    $Paths = @(
        (Join-Path $InstallDir "AnyDesk.exe")
    )


    if (${env:ProgramFiles(x86)}) {

        $Paths += Join-Path `
            ${env:ProgramFiles(x86)} `
            "AnyDesk\AnyDesk.exe"
    }


    if ($env:ProgramFiles) {

        $Paths += Join-Path `
            $env:ProgramFiles `
            "AnyDesk\AnyDesk.exe"
    }


    $FromService = Get-AnyDeskServiceExecutable

    if ($FromService) {

        $Paths += $FromService
    }


    foreach ($Path in $Paths) {

        if ($Path -and (Test-Path -LiteralPath $Path)) {

            return $Path
        }
    }


    return $null
}



function Wait-InstalledAnyDeskFile {

    param (
        [int]$TimeoutSeconds = 60
    )


    $Elapsed = 0


    while ($Elapsed -lt $TimeoutSeconds) {

        $Found = Find-InstalledAnyDesk

        if ($Found) {

            return $Found
        }


        Start-Sleep -Seconds 2

        $Elapsed += 2
    }


    return Find-InstalledAnyDesk
}



function Remove-AnyDeskServiceRecord {

    $ServicePid = Get-AnyDeskServicePid

    $Service = Get-AnyDeskService


    if ($Service -and $Service.Status -ne "Stopped") {

        try {

            Stop-Service `
                -Name "AnyDesk" `
                -Force `
                -ErrorAction Stop


            $Service.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                [TimeSpan]::FromSeconds(20)
            )

        }
        catch {

            Write-Log `
                "No se pudo detener el servicio antes de reemplazarlo: $($_.Exception.Message)" `
                "WARN"
        }
    }


    if (
        $ServicePid -and
        $ServicePid -ne 0
    ) {

        Stop-Process `
            -Id $ServicePid `
            -Force `
            -ErrorAction SilentlyContinue
    }


    & "$env:SystemRoot\System32\sc.exe" delete AnyDesk |
        Out-Null


    $Elapsed = 0


    while ($Elapsed -lt 20) {

        if (-not (Get-AnyDeskService)) {

            Write-Log `
                "Servicio anterior eliminado. Se instalara de nuevo." `
                "OK"

            return
        }


        Start-Sleep -Seconds 1

        $Elapsed++
    }


    Write-Log `
        "El servicio anterior sigue registrado. El instalador intentara reemplazarlo." `
        "WARN"
}



function Receive-AnyDeskInstaller {

    $NeedsDownload = $true


    if (Test-Path -LiteralPath $Installer) {

        $Existing = Get-Item -LiteralPath $Installer

        if ($Existing.Length -ge 1MB) {

            $ExistingSignature = Get-AuthenticodeSignature $Installer

            if ($ExistingSignature.Status -eq "Valid") {

                $NeedsDownload = $false

                Write-Log `
                    ("Instalador ya presente. Tamano: {0:N2} MB" -f ($Existing.Length / 1MB)) `
                    "OK"
            }
        }
    }


    if ($NeedsDownload) {

        Write-Log `
            "No se encontro un instalador valido. Se descargara AnyDesk."


        try {

            [Net.ServicePointManager]::SecurityProtocol = `
                [Net.SecurityProtocolType]::Tls12


            Invoke-WebRequest `
                -Uri $DownloadUrl `
                -OutFile $Installer `
                -UseBasicParsing

        }
        catch {

            Write-Log `
                "Error descargando AnyDesk: $($_.Exception.Message)" `
                "ERROR"


            Stop-AnyDeskDeploy -Code 20
        }
    }


    if (-not (Test-Path -LiteralPath $Installer)) {

        Write-Log `
            "No se encontro el instalador descargado." `
            "ERROR"


        Stop-AnyDeskDeploy -Code 21
    }


    $DownloadedFile = Get-Item -LiteralPath $Installer


    if ($DownloadedFile.Length -lt 1MB) {

        Write-Log `
            "El archivo descargado parece invalido. Tamano: $($DownloadedFile.Length) bytes." `
            "ERROR"


        Stop-AnyDeskDeploy -Code 22
    }


    if ($NeedsDownload) {

        Write-Log `
            ("Descarga completada. Tamano: {0:N2} MB" -f ($DownloadedFile.Length / 1MB)) `
            "OK"
    }


    Write-Log `
        "Validando firma digital del instalador..."


    $Signature = Get-AuthenticodeSignature `
        $Installer


    if ($Signature.Status -ne "Valid") {

        Write-Log `
            "La firma digital del instalador no es valida. Estado: $($Signature.Status)" `
            "ERROR"


        Remove-Item `
            -LiteralPath $Installer `
            -Force `
            -ErrorAction SilentlyContinue


        Stop-AnyDeskDeploy -Code 23
    }


    Write-Log `
        "Firma digital valida: $($Signature.SignerCertificate.Subject)" `
        "OK"
}



function Start-AnyDeskInstallerProcess {

    param (
        [string[]]$ArgumentList
    )


    $Quoted = foreach ($Argument in $ArgumentList) {

        if ($Argument -match '\s|"') {

            '"' + ($Argument -replace '"', '\"') + '"'

        }
        else {

            $Argument
        }
    }


    $ArgumentString = $Quoted -join " "


    Write-Log `
        "Comando de instalacion: $ArgumentString"


    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = $Installer

    $StartInfo.Arguments = $ArgumentString

    $StartInfo.UseShellExecute = $false

    $StartInfo.CreateNoWindow = $true


    $Process = New-Object System.Diagnostics.Process

    $Process.StartInfo = $StartInfo


    if (-not $Process.Start()) {

        throw "No se pudo iniciar el instalador."
    }


    return $Process
}



function Find-PortableAnyDesk {

    $Processes = Get-Process `
        -Name "AnyDesk" `
        -ErrorAction SilentlyContinue


    foreach ($Process in $Processes) {

        try {

            if (
                $Process.Path -and
                (Test-Path -LiteralPath $Process.Path)
            ) {

                $Path = $Process.Path


                if (
                    $Path -notlike "$env:ProgramFiles\AnyDesk\*" -and
                    (
                        -not ${env:ProgramFiles(x86)} -or
                        $Path -notlike "${env:ProgramFiles(x86)}\AnyDesk\*"
                    )
                ) {

                    return $Path
                }
            }

        }
        catch {

            # Algunos procesos pueden impedir consultar Path.
        }
    }


    return $null
}



function ConvertTo-AnyDeskIDKey {

    param (
        [string]$Id
    )


    if ([string]::IsNullOrWhiteSpace($Id)) {

        return $null
    }


    return ($Id -replace "\s", "")
}



function Read-AnyDeskConfigValue {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )


    if (-not (Test-Path -LiteralPath $Path)) {

        return $null
    }


    foreach ($Line in [System.IO.File]::ReadAllLines($Path)) {

        $Separator = $Line.IndexOf("=")

        if ($Separator -lt 1) {

            continue
        }


        $Key = $Line.Substring(0, $Separator).Trim()

        if ($Key -eq $Name) {

            return $Line.Substring($Separator + 1).Trim()
        }
    }


    return $null
}



function Get-AnyDeskIDFromServiceConfig {

    foreach ($Path in @($SystemConfig, $ServiceConfig)) {

        $Value = Read-AnyDeskConfigValue `
            -Path $Path `
            -Name "ad.anynet.id"


        if ($Value) {

            return $Value
        }
    }


    return $null
}



function Get-AnyDeskID {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [switch]$FromInstalledService
    )


    if ($FromInstalledService) {

        $FromConfig = Get-AnyDeskIDFromServiceConfig

        if ($FromConfig) {

            return $FromConfig
        }
    }


    try {

        $Result = (
            & $Executable --get-id 2>$null |
            Out-String
        ).Trim()


        if ($Result) {

            return $Result
        }

    }
    catch {
    }


    return $null
}



function Get-AnyDeskAlias {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Executable
    )


    try {

        $Result = (
            & $Executable --get-alias 2>$null |
            Out-String
        ).Trim()


        if ($Result) {

            return $Result
        }

    }
    catch {
    }


    return $null
}



function Get-AnyDeskStatus {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Executable
    )


    try {

        $Result = (
            & $Executable --get-status 2>$null |
            Out-String
        ).Trim()


        if ($Result) {

            return $Result
        }

    }
    catch {
    }


    return "Desconocido"
}



function Get-AnyDeskVersion {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Executable
    )


    try {

        $Result = (
            & $Executable --version 2>$null |
            Out-String
        ).Trim()


        if ($Result) {

            return $Result
        }

    }
    catch {
    }


    try {

        return (
            Get-Item -LiteralPath $Executable
        ).VersionInfo.FileVersion

    }
    catch {
    }


    return "No disponible"
}



function Wait-AnyDeskService {

    param (

        [int]$TimeoutSeconds = 90
    )


    $Elapsed = 0


    while ($Elapsed -lt $TimeoutSeconds) {

        $Service = Get-AnyDeskService


        if ($Service) {

            return $Service
        }


        Start-Sleep -Seconds 2

        $Elapsed += 2
    }


    return $null
}



function Test-PathUnderInstallDir {

    param (
        [string]$Path
    )


    if ([string]::IsNullOrWhiteSpace($Path)) {

        return $false
    }


    $Clean = $Path.Trim().Trim('"')

    if ($Clean -match '^(?:"([^"]+\.exe)"|([^\s"]+\.exe))') {

        if ($Matches[1]) {

            $Clean = $Matches[1]

        }
        else {

            $Clean = $Matches[2]
        }
    }


    $Prefix = $InstallDir.TrimEnd("\")


    return $Clean.StartsWith(
        $Prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}



function Set-AnyDeskConfigKeys {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )


    $Directory = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $Directory)) {

        New-Item `
            -ItemType Directory `
            -Path $Directory `
            -Force |
            Out-Null
    }


    $Existing = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath $Path) {

        foreach ($Line in [System.IO.File]::ReadAllLines($Path)) {

            $Existing.Add($Line)
        }
    }


    $Written = @{}

    $Output = New-Object System.Collections.Generic.List[string]


    foreach ($Line in $Existing) {

        $Trimmed = $Line.Trim()

        if (
            $Trimmed.Length -eq 0 -or
            $Trimmed.StartsWith("#")
        ) {

            $Output.Add($Line)

            continue
        }


        $Separator = $Line.IndexOf("=")

        if ($Separator -lt 1) {

            $Output.Add($Line)

            continue
        }


        $Name = $Line.Substring(0, $Separator).Trim()

        if ($Values.ContainsKey($Name)) {

            $Output.Add(("{0}={1}" -f $Name, $Values[$Name]))

            $Written[$Name] = $true

        }
        else {

            $Output.Add($Line)
        }
    }


    foreach ($Name in @($Values.Keys)) {

        if (-not $Written.ContainsKey($Name)) {

            $Output.Add(("{0}={1}" -f $Name, $Values[$Name]))
        }
    }


    $Utf8 = New-Object System.Text.UTF8Encoding $false

    [System.IO.File]::WriteAllLines(
        $Path,
        $Output.ToArray(),
        $Utf8
    )
}



function Update-AnyDeskSilentConfig {

    # Solo el system.conf del servicio. No se toca el system.conf de
    # %AppData%, porque ahi puede vivir la instancia portable.
    $Saved = $false


    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {

        try {

            Set-AnyDeskConfigKeys `
                -Path $SystemConfig `
                -Values $SilentConfig


            $Saved = $true

            break

        }
        catch {

            if ($Attempt -ge 5) {

                Write-Log `
                    "No se pudo escribir ${SystemConfig}: $($_.Exception.Message)" `
                    "WARN"
            }
            else {

                Start-Sleep -Seconds 1
            }
        }
    }


    if ($Saved) {

        Write-Log `
            "Configuracion silenciosa escrita: $SystemConfig" `
            "OK"
    }


    $Applied = Read-AnyDeskConfigValue `
        -Path $SystemConfig `
        -Name "ad.security.interactive_access"


    $Script:SilentConfigApplied = $Saved -and ($Applied -eq "2")


    if ($Script:SilentConfigApplied) {

        Write-Log `
            "Solicitudes entrantes desactivadas. Solo acceso desatendido." `
            "OK"

    }
    else {

        Write-Log `
            "No quedo confirmado ad.security.interactive_access=2." `
            "WARN"
    }


    return $Script:SilentConfigApplied
}



function Test-AnyDeskPasswordHashStored {

    if (-not (Test-Path -LiteralPath $SystemConfig)) {

        return $false
    }


    foreach ($Line in [System.IO.File]::ReadAllLines($SystemConfig)) {

        if ($Line -match "(?i)pwd_hash\s*=\s*\S+") {

            return $true
        }
    }


    return $false
}



function Remove-AnyDeskShortcut {

    param (

        [Parameter(Mandatory = $true)]
        [string]$Path
    )


    if (-not (Test-Path -LiteralPath $Path)) {

        return
    }


    $Item = Get-Item -LiteralPath $Path -Force


    if ($Item.PSIsContainer) {

        return
    }


    $Name = $Item.Name

    $KnownName = (
        $Name -eq "AnyDesk.lnk" -or
        $Name -eq "AnyDesk.exe.lnk"
    )

    $Target = $null


    if ($Name -like "*.lnk") {

        try {

            $Shell = New-Object -ComObject WScript.Shell

            $Shortcut = $Shell.CreateShortcut($Item.FullName)

            $Target = [string]$Shortcut.TargetPath

        }
        catch {

            $Target = $null
        }
    }


    # Un acceso que apunta a la copia portable se conserva.
    if ($Target) {

        $Remove = Test-PathUnderInstallDir -Path $Target

    }
    else {

        $Remove = $KnownName
    }


    if (-not $Remove) {

        return
    }


    Remove-Item `
        -LiteralPath $Item.FullName `
        -Force `
        -ErrorAction Stop


    $Script:RemovedShortcuts++

    Write-Log `
        "Acceso directo eliminado: $($Item.FullName)" `
        "OK"
}



function Get-AnyDeskShortcutRoots {

    $Roots = New-Object System.Collections.Generic.List[string]


    foreach (
        $Folder in @(
            "CommonDesktopDirectory",
            "CommonPrograms",
            "CommonStartup",
            "CommonStartMenu",
            "Desktop",
            "Programs",
            "Startup",
            "StartMenu"
        )
    ) {

        $Path = [Environment]::GetFolderPath($Folder)

        if ($Path) {

            $Roots.Add($Path)
        }
    }


    $Users = Get-ChildItem `
        -LiteralPath "C:\Users" `
        -Directory `
        -ErrorAction SilentlyContinue


    foreach ($User in $Users) {

        if (
            $User.Name -in @(
                "Public",
                "Default",
                "Default User",
                "All Users"
            )
        ) {

            continue
        }


        foreach (
            $Relative in @(
                "Desktop",
                "Escritorio",
                "AppData\Roaming\Microsoft\Windows\Start Menu\Programs",
                "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup",
                "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
            )
        ) {

            $Roots.Add((Join-Path $User.FullName $Relative))
        }
    }


    return $Roots
}



function Get-AnyDeskProgramRoots {

    $Roots = @{}


    foreach (
        $Folder in @(
            [Environment]::GetFolderPath("CommonPrograms"),
            [Environment]::GetFolderPath("Programs")
        )
    ) {

        if ($Folder) {

            $Roots[[System.IO.Path]::GetFullPath($Folder)] = $true
        }
    }


    $Users = Get-ChildItem `
        -LiteralPath "C:\Users" `
        -Directory `
        -ErrorAction SilentlyContinue


    foreach ($User in $Users) {

        if (
            $User.Name -in @(
                "Public",
                "Default",
                "Default User",
                "All Users"
            )
        ) {

            continue
        }


        $Programs = Join-Path `
            $User.FullName `
            "AppData\Roaming\Microsoft\Windows\Start Menu\Programs"


        if (Test-Path -LiteralPath $Programs) {

            $Roots[[System.IO.Path]::GetFullPath($Programs)] = $true
        }
    }


    # La coma evita que PowerShell desarme el hashtable al salir.
    return ,$Roots
}



function Remove-AnyDeskShortcuts {

    $Seen = @{}

    $ProgramRoots = Get-AnyDeskProgramRoots


    foreach ($Root in @(Get-AnyDeskShortcutRoots)) {

        if (-not (Test-Path -LiteralPath $Root)) {

            continue
        }


        $FullRoot = [System.IO.Path]::GetFullPath($Root)

        if ($Seen.ContainsKey($FullRoot)) {

            continue
        }


        $Seen[$FullRoot] = $true


        $ProgramFolder = Join-Path $FullRoot "AnyDesk"

        if (
            $ProgramRoots.ContainsKey($FullRoot) -and
            (Test-Path -LiteralPath $ProgramFolder)
        ) {

            try {

                Remove-Item `
                    -LiteralPath $ProgramFolder `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop


                $Script:RemovedShortcuts++

                Write-Log `
                    "Carpeta de accesos eliminada: $ProgramFolder" `
                    "OK"

            }
            catch {

                Write-Log `
                    "No se pudo eliminar ${ProgramFolder}: $($_.Exception.Message)" `
                    "WARN"
            }
        }


        $Links = Get-ChildItem `
            -LiteralPath $FullRoot `
            -Filter "*.lnk" `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue


        foreach ($Link in $Links) {

            try {

                Remove-AnyDeskShortcut -Path $Link.FullName

            }
            catch {

                Write-Log `
                    "No se pudo eliminar $($Link.FullName): $($_.Exception.Message)" `
                    "WARN"
            }
        }
    }
}



function Remove-AnyDeskRunValue {

    param (

        [Parameter(Mandatory = $true)]
        [string]$KeyPath
    )


    if (-not (Test-Path -LiteralPath $KeyPath)) {

        return
    }


    $Properties = Get-ItemProperty `
        -LiteralPath $KeyPath `
        -ErrorAction SilentlyContinue


    if (-not $Properties) {

        return
    }


    foreach ($Property in $Properties.PSObject.Properties) {

        if ($Property.Name -like "PS*") {

            continue
        }


        $Value = [string]$Property.Value

        if (-not (Test-PathUnderInstallDir -Path $Value)) {

            continue
        }


        Remove-ItemProperty `
            -LiteralPath $KeyPath `
            -Name $Property.Name `
            -ErrorAction Stop


        $Script:RemovedStartupEntries++

        Write-Log `
            "Inicio automatico de la ventana eliminado: $KeyPath :: $($Property.Name)" `
            "OK"
    }
}



function Get-AnyDeskRunKeyPaths {

    $Keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )


    $UserHives = Get-ChildItem `
        -Path "Registry::HKEY_USERS" `
        -ErrorAction SilentlyContinue


    foreach ($Hive in $UserHives) {

        if ($Hive.PSChildName -notmatch "^S-1-5-21-") {

            continue
        }


        if ($Hive.PSChildName -match "_Classes$") {

            continue
        }


        $Keys += "Registry::HKEY_USERS\$($Hive.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"
    }


    return $Keys
}



function Remove-AnyDeskStartupEntries {

    foreach ($Key in @(Get-AnyDeskRunKeyPaths)) {

        try {

            Remove-AnyDeskRunValue -KeyPath $Key

        }
        catch {

            Write-Log `
                "No se pudo limpiar ${Key}: $($_.Exception.Message)" `
                "WARN"
        }
    }
}



function Remove-AnyDeskLogonTasks {

    try {

        $Tasks = @(Get-ScheduledTask -ErrorAction Stop)

    }
    catch {

        Write-Log `
            "No se pudieron consultar tareas programadas: $($_.Exception.Message)" `
            "WARN"

        return
    }


    foreach ($Task in $Tasks) {

        $LaunchesGui = $false


        foreach ($Action in @($Task.Actions)) {

            $Arguments = [string]$Action.Arguments

            if ($Arguments -match "(?i)--service") {

                continue
            }


            if (Test-PathUnderInstallDir -Path ([string]$Action.Execute)) {

                $LaunchesGui = $true
            }
        }


        if (-not $LaunchesGui) {

            continue
        }


        $StartsAtLogon = $false


        foreach ($Trigger in @($Task.Triggers)) {

            if (
                $Trigger.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger"
            ) {

                $StartsAtLogon = $true
            }
        }


        if (-not $StartsAtLogon) {

            continue
        }


        try {

            Unregister-ScheduledTask `
                -TaskName $Task.TaskName `
                -TaskPath $Task.TaskPath `
                -Confirm:$false `
                -ErrorAction Stop


            $Script:RemovedStartupEntries++

            Write-Log `
                "Tarea de inicio de sesion eliminada: $($Task.TaskName)" `
                "OK"

        }
        catch {

            Write-Log `
                "No se pudo eliminar la tarea $($Task.TaskName): $($_.Exception.Message)" `
                "WARN"
        }
    }
}



function Stop-InstalledAnyDeskGui {

    # El servicio y la instancia portable no se tocan.
    # Solo se cierra la ventana creada por la instalacion nueva.

    if ($Script:InitialService -and -not $Script:ReplacedInstall) {

        return
    }


    $ServicePid = Get-AnyDeskServicePid

    $Processes = @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "Name='AnyDesk.exe'" `
            -ErrorAction SilentlyContinue
    )


    foreach ($Process in $Processes) {

        $Command = [string]$Process.CommandLine

        $ExePath = [string]$Process.ExecutablePath


        if ($Process.ProcessId -eq $ServicePid) {

            continue
        }


        if ($Command -match "(?i)--service") {

            continue
        }


        if (
            $Script:PortableExe -and
            $ExePath -and
            ($ExePath -ieq $Script:PortableExe)
        ) {

            continue
        }


        if (-not $ExePath -or -not $Command) {

            Write-Log `
                "PID $($Process.ProcessId) sin ruta o linea de comando. No se detuvo." `
                "WARN"

            continue
        }


        if (-not (Test-PathUnderInstallDir -Path $ExePath)) {

            continue
        }


        try {

            Stop-Process `
                -Id $Process.ProcessId `
                -Force `
                -ErrorAction Stop


            $Script:ClosedGuiCount++

            Write-Log `
                "Ventana de AnyDesk cerrada. PID $($Process.ProcessId). El servicio sigue activo." `
                "OK"

        }
        catch {

            Write-Log `
                "No se pudo cerrar la ventana PID $($Process.ProcessId): $($_.Exception.Message)" `
                "WARN"
        }
    }
}



function Restart-NewAnyDeskService {

    Write-Log `
        "Aplicando la configuracion silenciosa sobre la instalacion nueva."


    try {

        Stop-Service `
            -Name "AnyDesk" `
            -Force `
            -ErrorAction Stop


        $Service = Get-AnyDeskService

        $Service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds(30)
        )


        Write-Log `
            "Servicio detenido para escribir system.conf." `
            "OK"

    }
    catch {

        Write-Log `
            "No se pudo detener el servicio nuevo: $($_.Exception.Message)" `
            "ERROR"

        return $false
    }


    $ConfigOk = Update-AnyDeskSilentConfig


    try {

        if (-not (Test-AnyDeskPasswordHashStored)) {

            Write-Log `
                "No se encontro el hash de la password en system.conf." `
                "WARN"
        }

    }
    catch {

        Write-Log `
            "No se pudo comprobar el hash de la password: $($_.Exception.Message)" `
            "WARN"
    }


    try {

        Start-Service `
            -Name "AnyDesk" `
            -ErrorAction Stop


        $Service = Get-AnyDeskService

        $Service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(30)
        )


        Write-Log `
            "Servicio AnyDesk en ejecucion, sin ventana de usuario." `
            "OK"

    }
    catch {

        Write-Log `
            "No se pudo iniciar el servicio despues de configurar la interfaz: $($_.Exception.Message)" `
            "ERROR"


        try {

            Start-Service `
                -Name "AnyDesk" `
                -ErrorAction Stop


            Write-Log `
                "Servicio AnyDesk recuperado." `
                "WARN"

        }
        catch {

            Write-Log `
                "El servicio AnyDesk quedo detenido: $($_.Exception.Message)" `
                "ERROR"
        }


        return $false
    }


    return $ConfigOk
}



function Hide-AnyDeskUserInterface {

    Write-Log `
        "Ocultando la interfaz local de AnyDesk."


    Remove-AnyDeskShortcuts

    Remove-AnyDeskStartupEntries

    Remove-AnyDeskLogonTasks


    if ($Script:RemovedShortcuts -eq 0) {

        Write-Log `
            "No habia accesos directos de la instalacion persistente." `
            "OK"
    }


    if ($Script:RemovedStartupEntries -eq 0) {

        Write-Log `
            "No habia entradas de inicio de la ventana." `
            "OK"
    }


    if ((-not $Script:InitialService) -or $Script:ReplacedInstall) {

        $Ready = Restart-NewAnyDeskService

        Start-Sleep -Seconds 3

        Stop-InstalledAnyDeskGui

        Start-Sleep -Seconds 2

        Stop-InstalledAnyDeskGui


        if ($Script:ClosedGuiCount -eq 0) {

            Write-Log `
                "La instalacion no dejo una ventana abierta." `
                "OK"
        }


        return $Ready
    }


    Write-Log `
        "El servicio ya estaba en ejecucion. No se reinicia, para conservar la sesion actual." `
        "WARN"


    Write-Log `
        "La ventana que ya este abierta permanece hasta el proximo cierre de sesion." `
        "WARN"


    $Written = Update-AnyDeskSilentConfig

    if ($Written) {

        Write-Log `
            "La opcion de solicitudes entrantes queda escrita y se aplicara al proximo inicio del servicio." `
            "OK"
    }


    return $Written
}



function Test-AnyDeskStartupRemains {

    foreach ($Key in @(Get-AnyDeskRunKeyPaths)) {

        if (-not (Test-Path -LiteralPath $Key)) {

            continue
        }


        $Properties = Get-ItemProperty `
            -LiteralPath $Key `
            -ErrorAction SilentlyContinue


        if (-not $Properties) {

            continue
        }


        foreach ($Property in $Properties.PSObject.Properties) {

            if ($Property.Name -like "PS*") {

                continue
            }


            if (Test-PathUnderInstallDir -Path ([string]$Property.Value)) {

                return $true
            }
        }
    }


    return $false
}


function Stop-AnyDeskDeploy {

    param (
        [int]$Code
    )


    # Siempre lanza. El catch de Install-UnattendedAnyDesk lo convierte
    # en un resultado y sigue con el resto de CustomWin. exit cerraria
    # la consola de irm | iex.
    throw "AnyDeskDeployExit:$Code"
}



function Install-UnattendedAnyDesk {

    $script:AnyDeskExitCode = 1

    $ShowUserInterface = $false


    foreach ($ScopeName in @("Global", "Script")) {

        $ExistingShow = Get-Variable `
            -Name "ShowUserInterface" `
            -Scope $ScopeName `
            -ErrorAction SilentlyContinue


        if ($ExistingShow -and [bool]$ExistingShow.Value) {

            $ShowUserInterface = $true

            break
        }
    }


    $PasswordText = ""


    foreach ($ScopeName in @("Global", "Script")) {

        $ExistingPassword = Get-Variable `
            -Name "UnattendedPassword" `
            -Scope $ScopeName `
            -ErrorAction SilentlyContinue


        if (
            $ExistingPassword -and
            -not [string]::IsNullOrWhiteSpace([string]$ExistingPassword.Value)
        ) {

            $PasswordText = [string]$ExistingPassword.Value

            break
        }
    }


    $UnattendedPassword = $PasswordText


    if ([string]::IsNullOrWhiteSpace($UnattendedPassword)) {

        Write-Host ""
        Write-Host "============================================================"
        Write-Host " CONFIGURACION DE ACCESO DESATENDIDO"
        Write-Host "============================================================"
        Write-Host ""

        $SecurePassword = Read-Host `
            "Ingrese la password de acceso desatendido de AnyDesk" `
            -AsSecureString

        $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $SecurePassword
        )

        try {

            $UnattendedPassword = `
                [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

        }
        finally {

            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }


$DownloadUrl = "https://download.anydesk.com/AnyDesk.exe"

$InstallDir = if (${env:ProgramFiles(x86)}) {

    Join-Path ${env:ProgramFiles(x86)} "AnyDesk"

}
else {

    Join-Path $env:ProgramFiles "AnyDesk"
}


$DefaultInstalledExe = Join-Path `
    $InstallDir `
    "AnyDesk.exe"


$TempDir = Join-Path `
    $env:TEMP `
    "AnyDeskDeploy"


$Installer = Join-Path `
    $TempDir `
    "AnyDesk.exe"


$LogDir = $script:LogDir

$LogFile = $script:LogFile


$SystemConfig = "C:\ProgramData\AnyDesk\system.conf"

$ServiceConfig = "C:\ProgramData\AnyDesk\service.conf"


$Script:PortableExe          = $null
$Script:InstalledExe         = $null
$Script:OldID                = $null
$Script:NewID                = $null
$Script:InitialService       = $null
$Script:RemovedShortcuts     = 0
$Script:RemovedStartupEntries = 0
$Script:ClosedGuiCount       = 0
$Script:SilentConfigApplied  = $false


# Claves oficiales de AnyDesk. interactive_access=2 equivale a
# "Never show incoming session requests": solo entra quien conoce
# la password de acceso desatendido.
$SilentConfig = @{
    "ad.security.interactive_access" = "2"
    "ad.features.discovery"          = "false"
    "ad.discovery.enabled"           = "false"
    "ad.discovery.hidden"            = "true"
    "ad.discovery.show_tile"         = "0"
}


try {

New-Item `
    -ItemType Directory `
    -Path $LogDir `
    -Force |
    Out-Null


New-Item `
    -ItemType Directory `
    -Path $TempDir `
    -Force |
    Out-Null


Write-Host ""
Write-Host "============================================================"
Write-Host " ANYDESK - DEPLOY AUTOMATICO"
Write-Host "============================================================"
Write-Host ""


Write-Log "Inicio del deployment."

Write-Log `
    "Equipo: $env:COMPUTERNAME"

Write-Log `
    "Usuario: $env:USERDOMAIN\$env:USERNAME"


if ($ShowUserInterface) {

    Write-Log `
        "Modo de interfaz: VISIBLE."

}
else {

    Write-Log `
        "Modo de interfaz: OCULTA para el usuario local."
}



# ============================================================
# VALIDAR ADMINISTRADOR
# ============================================================

if (-not (Test-Administrator)) {

    Write-Log `
        "PowerShell no esta ejecutandose como Administrador." `
        "ERROR"


    Write-Host ""
    Write-Host "Ejecute PowerShell como Administrador."
    Write-Host ""


    Stop-AnyDeskDeploy -Code 10
}


Write-Log `
    "Privilegios de administrador confirmados." `
    "OK"



# ============================================================
# VALIDAR PASSWORD
# ============================================================

if (
    [string]::IsNullOrWhiteSpace($UnattendedPassword) -or
    $UnattendedPassword.Length -lt 8
) {

    Write-Log `
        "La password de acceso desatendido debe tener al menos 8 caracteres." `
        "ERROR"


    Stop-AnyDeskDeploy -Code 11
}


Write-Log `
    "Password de acceso desatendido recibida."


Write-Log `
    "La password NO sera escrita en el log."



# ============================================================
# RELEVAMIENTO INICIAL
# ============================================================

Write-Log `
    "Relevando estado actual de AnyDesk..."


$InitialService = Get-AnyDeskService

$Script:InitialService = $InitialService

$Script:InstalledExe = Find-InstalledAnyDesk

$Script:PortableExe = Find-PortableAnyDesk



# ============================================================
# ANYDESK PORTABLE
# ============================================================

if ($Script:PortableExe) {

    Write-Log `
        "AnyDesk PORTABLE detectado." `
        "WARN"


    Write-Log `
        "Portable: $Script:PortableExe"


    $PortableVersion = Get-AnyDeskVersion `
        -Executable $Script:PortableExe


    Write-Log `
        "Version portable: $PortableVersion"


    $Script:OldID = Get-AnyDeskID `
        -Executable $Script:PortableExe


    if ($Script:OldID) {

        Write-Log `
            "ID AnyDesk actual: $Script:OldID" `
            "OK"
    }


    Write-Log `
        "La instancia portable NO sera detenida." `
        "WARN"


    Write-Log `
        "Esto permite preservar la sesion remota actual." `
        "INFO"
}



# ============================================================
# INSTALACION EXISTENTE
# ============================================================

if ($InitialService) {

    Write-Log `
        "Servicio AnyDesk detectado. Sera reemplazado." `
        "WARN"


    Write-Log `
        "Estado inicial del servicio: $($InitialService.Status)"


    if ($Script:InstalledExe) {

        Write-Log `
            "Instalacion persistente: $Script:InstalledExe" `
            "OK"


        if (-not $Script:OldID) {

            $Script:OldID = Get-AnyDeskID `
                -Executable $Script:InstalledExe `
                -FromInstalledService
        }

    }

}
else {

    Write-Log `
        "No existe servicio AnyDesk." `
        "WARN"


    if ($Script:PortableExe) {

        Write-Log `
            "Se realizara instalacion persistente sin detener el portable." `
            "WARN"

    }
    else {

        Write-Log `
            "AnyDesk no esta instalado. Se realizara instalacion."
    }
}



# ============================================================
# DESCARGAR E INSTALAR O REEMPLAZAR
# ============================================================

$Script:ReplacedInstall = $false

$Script:RemoveFirst = $false


if ($InitialService -or $Script:InstalledExe) {

    $Script:ReplacedInstall = $true

    $Script:RemoveFirst = [bool]$Script:InstalledExe


    if (-not $Script:InstalledExe) {

        Write-Log `
            "Hay un servicio AnyDesk sin ejecutable en la carpeta de instalacion." `
            "WARN"


        Remove-AnyDeskServiceRecord

    }
    else {

        Write-Log `
            "Se reemplazara la instalacion de $($Script:InstalledExe)." `
            "WARN"
    }
}


Receive-AnyDeskInstaller


# ========================================================
# INSTALACION
# ========================================================

Write-Log `
    "Iniciando instalacion persistente de AnyDesk..."


    if ($Script:PortableExe) {

        Write-Log `
            "IMPORTANTE: no se detendra $Script:PortableExe" `
            "WARN"
    }


    # La ruta va entre comillas en ProcessStartInfo. Start-Process de
    # Windows PowerShell 5.1 parte "C:\Program Files (x86)\AnyDesk".
    $InstallArguments = @(
        "--install",
        $InstallDir
    )


    if ($Script:RemoveFirst) {

        $InstallArguments += "--remove-first"
    }


    $InstallArguments += "--silent"


    if ($ShowUserInterface) {

        $InstallArguments += @(
            "--start-with-win",
            "--create-shortcuts",
            "--create-desktop-icon"
        )

        Write-Log `
            "La instalacion creara accesos directos y abrira con Windows."

    }
    else {

        # Sin --start-with-win, --create-shortcuts ni --create-desktop-icon.
        # El servicio Automatic cubre el acceso desatendido despues de reiniciar.
        Write-Log `
            "Instalacion silenciosa, sin accesos directos ni ventana al iniciar Windows."
    }


    try {

        $InstallProcess = Start-AnyDeskInstallerProcess `
            -ArgumentList $InstallArguments


        Write-Log `
            "Proceso de instalacion iniciado. PID: $($InstallProcess.Id)"


        try {

            $InstallProcess |
                Wait-Process `
                    -Timeout 60 `
                    -ErrorAction Stop

        }
        catch {

            Write-Log `
                "El instalador continua ejecutandose o excedio el tiempo de espera." `
                "WARN"
        }

    }
    catch {

        Write-Log `
            "Error ejecutando el instalador: $($_.Exception.Message)" `
            "ERROR"


        Stop-AnyDeskDeploy -Code 24
    }



    # ========================================================
    # ESPERAR SERVICIO
    # ========================================================

    Write-Log `
        "Esperando creacion del servicio AnyDesk..."


    $Service = Wait-AnyDeskService `
        -TimeoutSeconds 90


    if (-not $Service) {

        Write-Log `
            "No se creo el servicio AnyDesk despues de la instalacion." `
            "ERROR"


        Write-Log `
            "La instancia portable, si existia, NO fue detenida." `
            "WARN"


        Stop-AnyDeskDeploy -Code 25
    }



    if ($Script:ReplacedInstall) {

        Write-Log `
            "Servicio AnyDesk reemplazado." `
            "OK"

    }
    else {

        Write-Log `
            "Servicio AnyDesk creado correctamente." `
            "OK"
    }


    Write-Log `
        "Esperando el ejecutable en $InstallDir..."


    $Script:InstalledExe = Wait-InstalledAnyDeskFile `
        -TimeoutSeconds 60


    if (-not $Script:InstalledExe) {

        Write-Log `
            "El servicio existe pero no se encontro el ejecutable instalado." `
            "ERROR"


        Stop-AnyDeskDeploy -Code 26
    }



    Write-Log `
        "AnyDesk instalado en: $Script:InstalledExe" `
        "OK"



# ============================================================
# LOCALIZAR EJECUTABLE PERSISTENTE
# ============================================================

if (-not $Script:InstalledExe) {

    $Script:InstalledExe = Find-InstalledAnyDesk
}


if (-not $Script:InstalledExe) {

    if (Test-Path -LiteralPath $DefaultInstalledExe) {

        $Script:InstalledExe = $DefaultInstalledExe
    }
}


if (-not $Script:InstalledExe) {

    Write-Log `
        "No fue posible localizar el AnyDesk instalado." `
        "ERROR"


    Stop-AnyDeskDeploy -Code 27
}



# ============================================================
# SERVICIO
# ============================================================

Write-Log `
    "Verificando servicio AnyDesk..."


$Service = Get-AnyDeskService


if (-not $Service) {

    Write-Log `
        "No se encontro el servicio AnyDesk." `
        "ERROR"


    Stop-AnyDeskDeploy -Code 30
}



Write-Log `
    "Servicio AnyDesk detectado." `
    "OK"


Write-Log `
    "Estado actual: $($Service.Status)"



# ============================================================
# STARTUP AUTOMATIC
# ============================================================

try {

    Set-Service `
        -Name "AnyDesk" `
        -StartupType Automatic


    Write-Log `
        "Inicio automatico del servicio configurado." `
        "OK"

}
catch {

    Write-Log `
        "No fue posible configurar StartupType: $($_.Exception.Message)" `
        "WARN"
}



# ============================================================
# INICIAR SERVICIO SOLO SI ESTA DETENIDO
# ============================================================

$Service.Refresh()


if ($Service.Status -ne "Running") {

    Write-Log `
        "El servicio esta detenido. Se iniciara." `
        "WARN"


    try {

        Start-Service `
            -Name "AnyDesk"


        $Service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(30)
        )


        Write-Log `
            "Servicio AnyDesk iniciado." `
            "OK"

    }
    catch {

        Write-Log `
            "No fue posible iniciar el servicio: $($_.Exception.Message)" `
            "ERROR"


        Stop-AnyDeskDeploy -Code 31
    }

}
else {

    if ($ShowUserInterface) {

        Write-Log `
            "Servicio ya se encuentra Running." `
            "OK"

    }
    elseif ((-not $Script:InitialService) -or $Script:ReplacedInstall) {

        Write-Log `
            "Servicio en ejecucion. Se reiniciara una vez al aplicar la interfaz oculta." `
            "OK"

    }
    else {

        Write-Log `
            "Servicio ya se encuentra Running." `
            "OK"
    }
}



# ============================================================
# VERIFICAR STARTUP TYPE
# ============================================================

try {

    $ServiceCIM = Get-CimInstance `
        Win32_Service `
        -Filter "Name='AnyDesk'"


    if ($ServiceCIM) {

        Write-Log `
            "StartupType servicio: $($ServiceCIM.StartMode)" `
            "OK"
    }

}
catch {

    Write-Log `
        "No se pudo consultar StartupType mediante CIM." `
        "WARN"
}



# ============================================================
# CONFIGURAR PASSWORD SOBRE INSTALACION PERSISTENTE
# ============================================================

Write-Log `
    "Configurando acceso desatendido sobre la instalacion persistente..."


Write-Log `
    "Ejecutable utilizado: $Script:InstalledExe"


try {

    $UnattendedPassword |
        & $Script:InstalledExe `
            --set-password `
            _unattended_access


    $PasswordExitCode = $LASTEXITCODE


    if (
        $null -ne $PasswordExitCode -and
        $PasswordExitCode -ne 0
    ) {

        Write-Log `
            "AnyDesk devolvio codigo $PasswordExitCode al configurar la password." `
            "ERROR"


        Stop-AnyDeskDeploy -Code 40
    }


    Write-Log `
        "Password de acceso desatendido configurada." `
        "OK"

}
catch {

    Write-Log `
        "Error configurando acceso desatendido: $($_.Exception.Message)" `
        "ERROR"


    Stop-AnyDeskDeploy -Code 41
}



# ============================================================
# CERRAR VENTANA DE UNA INSTALACION NUEVA
# ============================================================

if (
    (-not $ShowUserInterface) -and
    (-not $Script:InitialService)
) {

    Stop-InstalledAnyDeskGui
}



# ============================================================
# ESPERAR REGISTRO
# ============================================================

Write-Log `
    "Esperando registro de AnyDesk..."


Start-Sleep -Seconds 5



# ============================================================
# OBTENER ID FINAL
# ============================================================

for ($Attempt = 1; $Attempt -le 12; $Attempt++) {

    $Script:NewID = Get-AnyDeskID `
        -Executable $Script:InstalledExe `
        -FromInstalledService


    if ($Script:NewID) {

        break
    }


    Write-Log `
        "Esperando ID AnyDesk. Intento $Attempt/12..."


    Start-Sleep -Seconds 5
}



# ============================================================
# DATOS FINALES
# ============================================================

$Version = Get-AnyDeskVersion `
    -Executable $Script:InstalledExe


$Alias = Get-AnyDeskAlias `
    -Executable $Script:InstalledExe


$Status = Get-AnyDeskStatus `
    -Executable $Script:InstalledExe


$Service = Get-AnyDeskService


$ServiceCIM = Get-CimInstance `
    Win32_Service `
    -Filter "Name='AnyDesk'" `
    -ErrorAction SilentlyContinue



# ============================================================
# COMPARAR ID
# ============================================================

$IDResult = "No comparable"


if (
    $Script:OldID -and
    $Script:NewID
) {

    $OldKey = ConvertTo-AnyDeskIDKey $Script:OldID

    $NewKey = ConvertTo-AnyDeskIDKey $Script:NewID


    if ($OldKey -eq $NewKey) {

        $IDResult = "SIN CAMBIOS"


        Write-Log `
            "El ID AnyDesk se mantuvo: $Script:NewID" `
            "OK"

    }
    else {

        $IDResult = "CAMBIO DE ID"


        Write-Log `
            "ATENCION: el ID AnyDesk cambio." `
            "WARN"


        Write-Log `
            "ID anterior: $Script:OldID" `
            "WARN"


        Write-Log `
            "ID nuevo: $Script:NewID" `
            "WARN"
    }
}



# ============================================================
# OCULTAR INTERFAZ LOCAL
# ============================================================

if ($ShowUserInterface) {

    Write-Log `
        "Se conserva la interfaz visible de AnyDesk." `
        "OK"

}
else {

    $UiOk = Hide-AnyDeskUserInterface

    if (-not $UiOk) {

        Write-Log `
            "La interfaz local no quedo completamente oculta." `
            "WARN"
    }


    # --get-id y --version pueden volver a abrir la ventana.
    if (-not $Script:InitialService) {

        Stop-InstalledAnyDeskGui
    }


    $Service = Get-AnyDeskService

    $ServiceCIM = Get-CimInstance `
        Win32_Service `
        -Filter "Name='AnyDesk'" `
        -ErrorAction SilentlyContinue


    if (-not $Script:NewID) {

        $Script:NewID = Get-AnyDeskIDFromServiceConfig
    }
}



# ============================================================
# VALIDACION FINAL
# ============================================================

$DeploymentOK = $true



if (-not $Service) {

    Write-Log `
        "No se encontro el servicio AnyDesk al finalizar." `
        "ERROR"


    $DeploymentOK = $false

}
elseif ($Service.Status -ne "Running") {

    Write-Log `
        "El servicio AnyDesk no esta Running." `
        "ERROR"


    $DeploymentOK = $false
}



if (
    $ServiceCIM -and
    $ServiceCIM.StartMode -ne "Auto"
) {

    Write-Log `
        "El servicio AnyDesk no esta configurado Automatic." `
        "WARN"


    $DeploymentOK = $false
}



if (-not $Script:NewID) {

    Write-Log `
        "No se pudo obtener un ID AnyDesk final." `
        "WARN"


    $DeploymentOK = $false
}



if (-not (Test-Path -LiteralPath $Script:InstalledExe)) {

    Write-Log `
        "No existe el ejecutable persistente." `
        "ERROR"


    $DeploymentOK = $false
}



if (-not $ShowUserInterface) {

    if (Test-AnyDeskStartupRemains) {

        Write-Log `
            "La ventana de AnyDesk sigue registrada para iniciar con Windows." `
            "WARN"


        $DeploymentOK = $false
    }


    if (-not $Script:SilentConfigApplied) {

        Write-Log `
            "Las solicitudes entrantes no quedaron desactivadas." `
            "WARN"


        $DeploymentOK = $false
    }
}



# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " RESULTADO DEPLOY ANYDESK"
Write-Host "============================================================"
Write-Host ""


Write-Host `
    ("Equipo             : {0}" -f $env:COMPUTERNAME)


Write-Host `
    ("Ejecutable         : {0}" -f $Script:InstalledExe)


Write-Host `
    ("Version            : {0}" -f $Version)



if ($Service) {

    Write-Host `
        ("Servicio           : {0}" -f $Service.Status)

}
else {

    Write-Host `
        "Servicio           : NO ENCONTRADO"
}



if ($ServiceCIM) {

    Write-Host `
        ("Inicio servicio    : {0}" -f $ServiceCIM.StartMode)

}
else {

    Write-Host `
        "Inicio servicio    : No disponible"
}



if ($Script:OldID) {

    Write-Host `
        ("ID anterior        : {0}" -f $Script:OldID)

}
else {

    Write-Host `
        "ID anterior        : No disponible"
}



if ($Script:NewID) {

    Write-Host `
        ("ID actual          : {0}" -f $Script:NewID)

}
else {

    Write-Host `
        "ID actual          : No disponible"
}



if ($Alias) {

    Write-Host `
        ("Alias              : {0}" -f $Alias)

}
else {

    Write-Host `
        "Alias              : No configurado"
}



Write-Host `
    ("Estado AnyDesk     : {0}" -f $Status)


Write-Host `
    ("Comparacion ID     : {0}" -f $IDResult)


Write-Host `
    "Acceso desatendido : CONFIGURADO"



if ($ShowUserInterface) {

    Write-Host `
        "Interfaz local     : VISIBLE"

}
else {

    Write-Host `
        "Interfaz local     : OCULTA"


    Write-Host `
        ("Accesos directos   : {0} eliminados" -f $Script:RemovedShortcuts)


    Write-Host `
        ("Inicios de ventana : {0} eliminados" -f $Script:RemovedStartupEntries)


    Write-Host `
        "Solicitudes        : solo acceso desatendido"
}



if ($Script:PortableExe) {

    Write-Host `
        ("Portable original  : {0}" -f $Script:PortableExe)

}
else {

    Write-Host `
        "Portable original  : No detectado"
}


Write-Host `
    ("Log                : {0}" -f $LogFile)


Write-Host ""
Write-Host "============================================================"



# ============================================================
# RESULTADO FINAL
# ============================================================

if ($DeploymentOK) {

    Write-Host ""
    Write-Host `
        "DEPLOY FINALIZADO CORRECTAMENTE" `
        -ForegroundColor Green


    if ($Script:NewID) {

        Write-Host ""
        Write-Host `
            "AnyDesk ID: $Script:NewID" `
            -ForegroundColor Green
    }


    Write-Host ""


    Write-Log `
        "Deployment finalizado correctamente." `
        "OK"

}
else {

    Write-Host ""
    Write-Host `
        "DEPLOY FINALIZADO CON ADVERTENCIAS" `
        -ForegroundColor Yellow


    Write-Host `
        "Revise: $LogFile"


    Write-Host ""


    Write-Log `
        "Deployment finalizado con advertencias." `
        "WARN"
}



# ============================================================
# LIMPIEZA
# ============================================================

if (Test-Path -LiteralPath $Installer) {

    Remove-Item `
        -LiteralPath $Installer `
        -Force `
        -ErrorAction SilentlyContinue
}



# Reducir permanencia de la password en variables.
$UnattendedPassword = $null
$SecurePassword = $null
$BSTR = [IntPtr]::Zero



Write-Log `
    "Fin del script."


Write-Host ""
Write-Host "IMPORTANTE:"
Write-Host "No se detuvo ni reinicio deliberadamente la instancia"
Write-Host "AnyDesk portable utilizada para la conexion inicial."

if (-not $ShowUserInterface) {

    Write-Host ""
    Write-Host "La aplicacion no queda en el escritorio, el menu Inicio"
    Write-Host "ni el inicio de Windows. El acceso entra por el servicio."
    Write-Host "Durante una sesion remota el equipo muestra el marco"
    Write-Host "y la barra de sesion de AnyDesk."
}

Write-Host ""



if ($DeploymentOK) {

    Stop-AnyDeskDeploy -Code 0

}
else {

    Stop-AnyDeskDeploy -Code 1
}

}
catch {

    $DeployMessage = [string]$_.Exception.Message


    if ($DeployMessage -like "AnyDeskDeployExit:*") {

        $DeployExitCode = 1

        $DeployParsedCode = 0


        if (
            [int]::TryParse(
                ($DeployMessage -replace "^AnyDeskDeployExit:", ""),
                [ref]$DeployParsedCode
            )
        ) {

            $DeployExitCode = $DeployParsedCode
        }


        $UnattendedPassword = $null

        $SecurePassword = $null

        $script:AnyDeskExitCode = $DeployExitCode

        return
    }


    $UnattendedPassword = $null

    $SecurePassword = $null

    throw
}
}


try {

    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null


    Write-Host ""
    Write-Host "============================================================"
    Write-Host " CUSTOMWIN"
    Write-Host "============================================================"
    Write-Host ""


    Write-Log "Inicio de CustomWin."

    Write-Log "Revision: 20261023j"

    Write-Log "Equipo: $env:COMPUTERNAME"

    Write-Log "Usuario: $env:USERDOMAIN\$env:USERNAME"


    if (-not (Test-Administrator)) {

        Write-Log "PowerShell no esta ejecutandose como Administrador." "ERROR"

        Write-Host ""
        Write-Host "Ejecute PowerShell como Administrador."
        Write-Host ""

        Stop-CustomWin -Code 10
    }


    Write-Log "Privilegios de administrador confirmados." "OK"


    Invoke-CustomWinPopup
}
catch {

    $DeployMessage = [string]$_.Exception.Message


    if ($DeployMessage -like "CustomWinExit:*") {

        $DeployExitCode = 1

        $DeployParsedCode = 0


        if (
            [int]::TryParse(
                ($DeployMessage -replace "^CustomWinExit:", ""),
                [ref]$DeployParsedCode
            )
        ) {

            $DeployExitCode = $DeployParsedCode
        }


        $global:LASTEXITCODE = $DeployExitCode


        if ($PSCommandPath) {

            exit $DeployExitCode
        }


        return
    }


    Write-Log "Error no controlado: $DeployMessage" "ERROR"

    throw
}
