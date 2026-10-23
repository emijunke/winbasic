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

eHQgPSAiRWxlZ2kgcXVlIHF1ZXJlcyBhcGxpY2FyIg0KDQogICAgJFRpdGxlLkF1dG9TaXplID0gJGZhbHNlDQoNCiAgICAkVGl0

bGUuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NDAsIDM2KQ0KDQogICAgJFRpdGxlLkZvbnQgPSBOZXct

T2JqZWN0IFN5c3RlbS5EcmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMjYsIFtTeXN0ZW0uRHJhd2luZy5Gb250U3R5bGVdOjpCb2xk

KQ0KDQogICAgJFRpdGxlLkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OldoaXRlDQoNCiAgICAkVGl0bGUuQmFj

a0NvbG9yID0gJEFjY2VudA0KDQogICAgJFRpdGxlLkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgy

OCwgMjYpDQoNCiAgICAkSGVhZGVyLkNvbnRyb2xzLkFkZCgkVGl0bGUpDQoNCg0KICAgICRIaW50ID0gTmV3LU9iamVjdCBTeXN0

ZW0uV2luZG93cy5Gb3Jtcy5MYWJlbA0KDQogICAgJEhpbnQuVGV4dCA9ICJOYWRhIGVtcGllemEgdGlsZGFkby4gTWFyY2EgbG8g

cXVlIHF1ZXJlcyBhcGxpY2FyLiBMbyBkZW1hcyBubyBzZSBtb2RpZmljYS4iDQoNCiAgICAkSGludC5BdXRvU2l6ZSA9ICRmYWxz

ZQ0KDQogICAgJEhpbnQuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NDAsIDI0KQ0KDQogICAgJEhpbnQu

Rm9udCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuRm9udCgiU2Vnb2UgVUkiLCAxMCkNCg0KICAgICRIaW50LkZvcmVDb2xv

ciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDIxOSwgMjM0LCAyNTQpDQoNCiAgICAkSGludC5CYWNrQ29sb3Ig

PSAkQWNjZW50DQoNCiAgICAkSGludC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMjgsIDY2KQ0K

DQogICAgJEhlYWRlci5Db250cm9scy5BZGQoJEhpbnQpDQoNCg0KICAgICRMaXN0Q2FyZCA9IE5ldy1PYmplY3QgU3lzdGVtLldp

bmRvd3MuRm9ybXMuUGFuZWwNCg0KICAgICRMaXN0Q2FyZC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9p

bnQoMjQsIDEyOCkNCg0KICAgICRMaXN0Q2FyZC5TaXplID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5TaXplKDY1MiwgNDUy

KQ0KDQogICAgJExpc3RDYXJkLkJhY2tDb2xvciA9ICRMaW5lDQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJExpc3RDYXJkKQ0K

DQoNCiAgICAkTGlzdCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQ2hlY2tlZExpc3RCb3gNCg0KICAgICRMaXN0

LkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgxLCAxKQ0KDQogICAgJExpc3QuU2l6ZSA9IE5ldy1P

YmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NTAsIDQ1MCkNCg0KICAgICRMaXN0LkNoZWNrT25DbGljayA9ICR0cnVlDQoNCiAg

ICAkTGlzdC5Cb3JkZXJTdHlsZSA9ICJOb25lIg0KDQogICAgJExpc3QuSW50ZWdyYWxIZWlnaHQgPSAkZmFsc2UNCg0KICAgICRM

aXN0LkRyYXdNb2RlID0gIk93bmVyRHJhd0ZpeGVkIg0KDQogICAgJExpc3QuSXRlbUhlaWdodCA9IDQ0DQoNCiAgICAkTGlzdC5G

b250ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDExKQ0KDQogICAgJExpc3QuQmFja0NvbG9y

ID0gJENhcmQNCg0KICAgICRMaXN0LkZvcmVDb2xvciA9ICRJbmsNCg0KICAgICRzY3JpcHQ6Q3VzdG9tV2luSG92ZXJJbmRleCA9

IC0xDQoNCg0KICAgICRMaXN0LkFkZF9EcmF3SXRlbSh7DQoNCiAgICAgICAgcGFyYW0oJHNlbmRlciwgJGUpDQoNCiAgICAgICAg

aWYgKCRlLkluZGV4IC1sdCAwKSB7IHJldHVybiB9DQoNCiAgICAgICAgJEdyYXBoaWNzID0gJGUuR3JhcGhpY3MNCg0KICAgICAg

ICAkR3JhcGhpY3MuU21vb3RoaW5nTW9kZSA9IFtTeXN0ZW0uRHJhd2luZy5EcmF3aW5nMkQuU21vb3RoaW5nTW9kZV06OkFudGlB

bGlhcw0KDQogICAgICAgICRCb3VuZHMgPSAkZS5Cb3VuZHMNCg0KICAgICAgICAkSXNDaGVja2VkID0gJExpc3QuR2V0SXRlbUNo

ZWNrZWQoJGUuSW5kZXgpDQoNCiAgICAgICAgJElzSG90ID0gJGUuSW5kZXggLWVxICRzY3JpcHQ6Q3VzdG9tV2luSG92ZXJJbmRl

eA0KDQogICAgICAgICRCYWNrID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUNCg0KICAgICAgICBpZiAoJElzQ2hlY2tl

ZCkgew0KDQogICAgICAgICAgICAkQmFjayA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDIzOSwgMjQ2LCAyNTUp

DQoNCiAgICAgICAgfQ0KICAgICAgICBlbHNlaWYgKCRJc0hvdCkgew0KDQogICAgICAgICAgICAkQmFjayA9IFtTeXN0ZW0uRHJh

d2luZy5Db2xvcl06OkZyb21BcmdiKDI0OCwgMjUwLCAyNTIpDQogICAgICAgIH0NCg0KICAgICAgICAkQmFja0JydXNoID0gTmV3

LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Tb2xpZEJydXNoICRCYWNrDQoNCiAgICAgICAgJEdyYXBoaWNzLkZpbGxSZWN0YW5nbGUo

JEJhY2tCcnVzaCwgJEJvdW5kcykNCg0KICAgICAgICAkQmFja0JydXNoLkRpc3Bvc2UoKQ0KDQogICAgICAgICRCb3hUb3AgPSAk

Qm91bmRzLlkgKyBbaW50XSgoJEJvdW5kcy5IZWlnaHQgLSAxOCkgLyAyKQ0KDQogICAgICAgICRCb3ggPSBOZXctT2JqZWN0IFN5

c3RlbS5EcmF3aW5nLlJlY3RhbmdsZSgoJEJvdW5kcy5YICsgMjIpLCAkQm94VG9wLCAxOCwgMTgpDQoNCiAgICAgICAgJEJsdWUg

PSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigzNywgOTksIDIzNSkNCg0KICAgICAgICBpZiAoJElzQ2hlY2tlZCkg

ew0KDQogICAgICAgICAgICAkRmlsbCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU29saWRCcnVzaCAkQmx1ZQ0KDQogICAg

ICAgICAgICAkR3JhcGhpY3MuRmlsbFJlY3RhbmdsZSgkRmlsbCwgJEJveCkNCg0KICAgICAgICAgICAgJEZpbGwuRGlzcG9zZSgp

DQoNCiAgICAgICAgICAgICRNYXJrUGVuID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5QZW4gKFtTeXN0ZW0uRHJhd2luZy5D

b2xvcl06OldoaXRlKSwgMg0KDQogICAgICAgICAgICAkUG9pbnRzID0gTmV3LU9iamVjdCAnU3lzdGVtLkRyYXdpbmcuUG9pbnRb

XScgMw0KDQogICAgICAgICAgICAkUG9pbnRzWzBdID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCAoKCRCb3guWCAr

IDQpLCAoJEJveC5ZICsgOSkpDQoNCiAgICAgICAgICAgICRQb2ludHNbMV0gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBv

aW50ICgoJEJveC5YICsgOCksICgkQm94LlkgKyAxMykpDQoNCiAgICAgICAgICAgICRQb2ludHNbMl0gPSBOZXctT2JqZWN0IFN5

c3RlbS5EcmF3aW5nLlBvaW50ICgoJEJveC5YICsgMTQpLCAoJEJveC5ZICsgNSkpDQoNCiAgICAgICAgICAgICRHcmFwaGljcy5E

cmF3TGluZXMoJE1hcmtQZW4sICRQb2ludHMpDQoNCiAgICAgICAgICAgICRNYXJrUGVuLkRpc3Bvc2UoKQ0KDQogICAgICAgIH0N

CiAgICAgICAgZWxzZSB7DQoNCiAgICAgICAgICAgICRCb3hQZW4gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBlbiAoW1N5

c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMTQ4LCAxNjMsIDE4NCkpDQoNCiAgICAgICAgICAgICRHcmFwaGljcy5EcmF3

UmVjdGFuZ2xlKCRCb3hQZW4sICRCb3gpDQoNCiAgICAgICAgICAgICRCb3hQZW4uRGlzcG9zZSgpDQogICAgICAgIH0NCg0KICAg

ICAgICAkVGV4dEJydXNoID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Tb2xpZEJydXNoIChbU3lzdGVtLkRyYXdpbmcuQ29s

b3JdOjpGcm9tQXJnYigxNSwgMjMsIDQyKSkNCg0KICAgICAgICAkVGV4dFJlY3QgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5n

LlJlY3RhbmdsZSgoJEJvdW5kcy5YICsgNDgpLCAkQm91bmRzLlksICgkQm91bmRzLldpZHRoIC0gNjApLCAkQm91bmRzLkhlaWdo

dCkNCg0KICAgICAgICAkRm9ybWF0ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5TdHJpbmdGb3JtYXQNCg0KICAgICAgICAk

Rm9ybWF0LkxpbmVBbGlnbm1lbnQgPSBbU3lzdGVtLkRyYXdpbmcuU3RyaW5nQWxpZ25tZW50XTo6Q2VudGVyDQoNCiAgICAgICAg

JEZvcm1hdC5UcmltbWluZyA9IFtTeXN0ZW0uRHJhd2luZy5TdHJpbmdUcmltbWluZ106OkVsbGlwc2lzQ2hhcmFjdGVyDQoNCiAg

ICAgICAgJEZvcm1hdC5Gb3JtYXRGbGFncyA9IFtTeXN0ZW0uRHJhd2luZy5TdHJpbmdGb3JtYXRGbGFnc106Ok5vV3JhcA0KDQog

ICAgICAgICRHcmFwaGljcy5EcmF3U3RyaW5nKFtzdHJpbmddJExpc3QuSXRlbXNbJGUuSW5kZXhdLCAkZS5Gb250LCAkVGV4dEJy

dXNoLCAkVGV4dFJlY3QsICRGb3JtYXQpDQoNCiAgICAgICAgJFRleHRCcnVzaC5EaXNwb3NlKCkNCg0KICAgICAgICAkRm9ybWF0

LkRpc3Bvc2UoKQ0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoNCiAgICAkTGlzdC5BZGRfTW91c2VNb3ZlKHsNCg0KICAgICAg

ICBwYXJhbSgkc2VuZGVyLCAkZSkNCg0KICAgICAgICAkSW5kZXggPSAkTGlzdC5JbmRleEZyb21Qb2ludCgkZS5Mb2NhdGlvbikN

Cg0KICAgICAgICBpZiAoJEluZGV4IC1uZSAkc2NyaXB0OkN1c3RvbVdpbkhvdmVySW5kZXgpIHsNCg0KICAgICAgICAgICAgJHNj

cmlwdDpDdXN0b21XaW5Ib3ZlckluZGV4ID0gJEluZGV4DQoNCiAgICAgICAgICAgICRMaXN0LkludmFsaWRhdGUoKQ0KICAgICAg

ICB9DQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KICAgICRMaXN0LkFkZF9Nb3VzZUxlYXZlKHsNCg0KICAgICAgICAkc2Ny

aXB0OkN1c3RvbVdpbkhvdmVySW5kZXggPSAtMQ0KDQogICAgICAgICRMaXN0LkludmFsaWRhdGUoKQ0KDQogICAgfS5HZXROZXdD

bG9zdXJlKCkpDQoNCg0KICAgIGZvcmVhY2ggKCRDaG9pY2UgaW4gJENob2ljZXMpIHsNCg0KICAgICAgICBbdm9pZF0kTGlzdC5J

dGVtcy5BZGQoJENob2ljZS5UZXh0LCAkZmFsc2UpDQogICAgfQ0KDQoNCiAgICAkTGlzdENhcmQuQ29udHJvbHMuQWRkKCRMaXN0

KQ0KDQoNCiAgICAkTm90aWNlID0gTmV3LU9iamVjdCBTeXN0ZW0uV2luZG93cy5Gb3Jtcy5MYWJlbA0KDQogICAgJE5vdGljZS5U

ZXh0ID0gIiINCg0KICAgICROb3RpY2UuQXV0b1NpemUgPSAkZmFsc2UNCg0KICAgICROb3RpY2UuU2l6ZSA9IE5ldy1PYmplY3Qg

U3lzdGVtLkRyYXdpbmcuU2l6ZSg2NDAsIDIwKQ0KDQogICAgJE5vdGljZS5Gb250ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2lu

Zy5Gb250KCJTZWdvZSBVSSIsIDkpDQoNCiAgICAkTm90aWNlLkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZy

b21BcmdiKDE4NSwgMjgsIDI4KQ0KDQogICAgJE5vdGljZS5CYWNrQ29sb3IgPSAkQ2FudmFzDQoNCiAgICAkTm90aWNlLkxvY2F0

aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgyNCwgNTg4KQ0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRkKCRO

b3RpY2UpDQoNCg0KICAgICRMaXN0LkFkZF9TZWxlY3RlZEluZGV4Q2hhbmdlZCh7DQoNCiAgICAgICAgJE5vdGljZS5UZXh0ID0g

IiINCg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQoNCiAgICBmdW5jdGlvbiBTZXQtQ3VzdG9tV2luRmxhdEJ1dHRvbiB7DQoN

CiAgICAgICAgcGFyYW0oDQogICAgICAgICAgICAkQnV0dG9uLA0KICAgICAgICAgICAgW2Jvb2xdJFByaW1hcnkNCiAgICAgICAg

KQ0KDQogICAgICAgICRCdXR0b24uRmxhdFN0eWxlID0gIkZsYXQiDQoNCiAgICAgICAgJEJ1dHRvbi5DdXJzb3IgPSBbU3lzdGVt

LldpbmRvd3MuRm9ybXMuQ3Vyc29yc106OkhhbmQNCg0KICAgICAgICAkQnV0dG9uLkZvbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5E

cmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMTApDQoNCiAgICAgICAgaWYgKCRQcmltYXJ5KSB7DQoNCiAgICAgICAgICAgICRCdXR0

b24uQmFja0NvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMzcsIDk5LCAyMzUpDQoNCiAgICAgICAgICAg

ICRCdXR0b24uRm9yZUNvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUNCg0KICAgICAgICAgICAgJEJ1dHRvbi5G

bGF0QXBwZWFyYW5jZS5Cb3JkZXJTaXplID0gMA0KDQogICAgICAgICAgICAkQnV0dG9uLkZsYXRBcHBlYXJhbmNlLk1vdXNlT3Zl

ckJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDI5LCA3OCwgMjE2KQ0KDQogICAgICAgICAgICAk

QnV0dG9uLkZsYXRBcHBlYXJhbmNlLk1vdXNlRG93bkJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21Bcmdi

KDMwLCA2NCwgMTc1KQ0KDQogICAgICAgICAgICByZXR1cm4NCiAgICAgICAgfQ0KDQogICAgICAgICRCdXR0b24uQmFja0NvbG9y

ID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUNCg0KICAgICAgICAkQnV0dG9uLkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJh

d2luZy5Db2xvcl06OkZyb21BcmdiKDE1LCAyMywgNDIpDQoNCiAgICAgICAgJEJ1dHRvbi5GbGF0QXBwZWFyYW5jZS5Cb3JkZXJT

aXplID0gMQ0KDQogICAgICAgICRCdXR0b24uRmxhdEFwcGVhcmFuY2UuQm9yZGVyQ29sb3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29s

b3JdOjpGcm9tQXJnYigyMDMsIDIxMywgMjI1KQ0KDQogICAgICAgICRCdXR0b24uRmxhdEFwcGVhcmFuY2UuTW91c2VPdmVyQmFj

a0NvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMjQxLCAyNDUsIDI0OSkNCg0KICAgICAgICAkQnV0dG9u

LkZsYXRBcHBlYXJhbmNlLk1vdXNlRG93bkJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDIyNiwg

MjMyLCAyNDApDQogICAgfQ0KDQoNCiAgICAkTWFya0FsbCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQnV0dG9u

DQoNCiAgICAkTWFya0FsbC5UZXh0ID0gIk1hcmNhciB0b2RvIg0KDQogICAgJE1hcmtBbGwuTG9jYXRpb24gPSBOZXctT2JqZWN0

IFN5c3RlbS5EcmF3aW5nLlBvaW50KDI0LCA2MTYpDQoNCiAgICAkTWFya0FsbC5TaXplID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJh

d2luZy5TaXplKDEzMiwgNDApDQoNCiAgICBTZXQtQ3VzdG9tV2luRmxhdEJ1dHRvbiAtQnV0dG9uICRNYXJrQWxsIC1QcmltYXJ5

ICRmYWxzZQ0KDQogICAgJE1hcmtBbGwuQWRkX0NsaWNrKHsNCg0KICAgICAgICBmb3IgKCRJbmRleCA9IDA7ICRJbmRleCAtbHQg

JExpc3QuSXRlbXMuQ291bnQ7ICRJbmRleCsrKSB7DQoNCiAgICAgICAgICAgICRMaXN0LlNldEl0ZW1DaGVja2VkKCRJbmRleCwg

JHRydWUpDQogICAgICAgIH0NCg0KICAgICAgICAkTm90aWNlLlRleHQgPSAiIg0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoN

CiAgICAkRm9ybS5Db250cm9scy5BZGQoJE1hcmtBbGwpDQoNCg0KICAgICRDbGVhckFsbCA9IE5ldy1PYmplY3QgU3lzdGVtLldp

bmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAgICAkQ2xlYXJBbGwuVGV4dCA9ICJEZXNtYXJjYXIgdG9kbyINCg0KICAgICRDbGVhckFs

bC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMTY0LCA2MTYpDQoNCiAgICAkQ2xlYXJBbGwuU2l6

ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSgxNDgsIDQwKQ0KDQogICAgU2V0LUN1c3RvbVdpbkZsYXRCdXR0b24g

LUJ1dHRvbiAkQ2xlYXJBbGwgLVByaW1hcnkgJGZhbHNlDQoNCiAgICAkQ2xlYXJBbGwuQWRkX0NsaWNrKHsNCg0KICAgICAgICBm

b3IgKCRJbmRleCA9IDA7ICRJbmRleCAtbHQgJExpc3QuSXRlbXMuQ291bnQ7ICRJbmRleCsrKSB7DQoNCiAgICAgICAgICAgICRM

aXN0LlNldEl0ZW1DaGVja2VkKCRJbmRleCwgJGZhbHNlKQ0KICAgICAgICB9DQoNCiAgICAgICAgJE5vdGljZS5UZXh0ID0gIiIN

Cg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRkKCRDbGVhckFsbCkNCg0KDQogICAgJENh

bmNlbCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAgICAkQ2FuY2VsLlRleHQgPSAiQ2FuY2Vs

YXIiDQoNCiAgICAkQ2FuY2VsLkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCg0MDQsIDYxNikNCg0K

ICAgICRDYW5jZWwuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSgxMjAsIDQwKQ0KDQogICAgJENhbmNlbC5E

aWFsb2dSZXN1bHQgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuRGlhbG9nUmVzdWx0XTo6Q2FuY2VsDQoNCiAgICBTZXQtQ3VzdG9t

V2luRmxhdEJ1dHRvbiAtQnV0dG9uICRDYW5jZWwgLVByaW1hcnkgJGZhbHNlDQoNCiAgICAkRm9ybS5DYW5jZWxCdXR0b24gPSAk

Q2FuY2VsDQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJENhbmNlbCkNCg0KDQogICAgJEFwcGx5ID0gTmV3LU9iamVjdCBTeXN0

ZW0uV2luZG93cy5Gb3Jtcy5CdXR0b24NCg0KICAgICRBcHBseS5UZXh0ID0gIkFwbGljYXIiDQoNCiAgICAkQXBwbHkuTG9jYXRp

b24gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50KDUzNiwgNjE2KQ0KDQogICAgJEFwcGx5LlNpemUgPSBOZXctT2Jq

ZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoMTQwLCA0MCkNCg0KICAgIFNldC1DdXN0b21XaW5GbGF0QnV0dG9uIC1CdXR0b24gJEFw

cGx5IC1QcmltYXJ5ICR0cnVlDQoNCiAgICAkQXBwbHkuQWRkX0NsaWNrKHsNCg0KICAgICAgICAkQW55Q2hlY2tlZCA9ICRmYWxz

ZQ0KDQoNCiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAkSW5kZXggLWx0ICRMaXN0Lkl0ZW1zLkNvdW50OyAkSW5kZXgrKykgew0K

DQogICAgICAgICAgICBpZiAoJExpc3QuR2V0SXRlbUNoZWNrZWQoJEluZGV4KSkgew0KDQogICAgICAgICAgICAgICAgJEFueUNo

ZWNrZWQgPSAkdHJ1ZQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQoNCg0KICAgICAgICBpZiAoLW5vdCAkQW55Q2hlY2tlZCkg

ew0KDQogICAgICAgICAgICAkTm90aWNlLlRleHQgPSAiVGlsZGEgYWwgbWVub3MgdW5hIG9wY2lvbi4iDQoNCiAgICAgICAgICAg

IHJldHVybg0KICAgICAgICB9DQoNCg0KICAgICAgICAkRm9ybS5EaWFsb2dSZXN1bHQgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMu

RGlhbG9nUmVzdWx0XTo6T0sNCg0KICAgICAgICAkRm9ybS5DbG9zZSgpDQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KICAg

ICRGb3JtLkNvbnRyb2xzLkFkZCgkQXBwbHkpDQoNCiAgICAkRm9ybS5BY2NlcHRCdXR0b24gPSAkQXBwbHkNCg0KDQogICAgJFVw

ZGF0ZUxheW91dCA9IHsNCg0KICAgICAgICAkV2lkdGggPSAkRm9ybS5DbGllbnRTaXplLldpZHRoDQoNCiAgICAgICAgJEhlaWdo

dCA9ICRGb3JtLkNsaWVudFNpemUuSGVpZ2h0DQoNCg0KICAgICAgICBpZiAoJFdpZHRoIC1sdCA2NDAgLW9yICRIZWlnaHQgLWx0

IDQ4MCkgew0KDQogICAgICAgICAgICByZXR1cm4NCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJEhlYWRlckhlaWdodCA9IDE0OA0K

DQogICAgICAgICRIZWFkZXIuU2V0Qm91bmRzKDAsIDAsICRXaWR0aCwgJEhlYWRlckhlaWdodCkNCg0KDQogICAgICAgICRDb250

ZW50V2lkdGggPSAkV2lkdGggLSAxMjANCg0KDQogICAgICAgIGlmICgkQ29udGVudFdpZHRoIC1ndCAxMDgwKSB7DQoNCiAgICAg

ICAgICAgICRDb250ZW50V2lkdGggPSAxMDgwDQogICAgICAgIH0NCg0KDQogICAgICAgICRMZWZ0ID0gW2ludF0oKCRXaWR0aCAt

ICRDb250ZW50V2lkdGgpIC8gMikNCg0KICAgICAgICAkVGl0bGUuU2V0Qm91bmRzKCRMZWZ0LCA0MCwgJENvbnRlbnRXaWR0aCwg

NDgpDQoNCiAgICAgICAgJEhpbnQuU2V0Qm91bmRzKCRMZWZ0LCA5NiwgJENvbnRlbnRXaWR0aCwgMjgpDQoNCg0KICAgICAgICAk

QnV0dG9uVG9wID0gJEhlaWdodCAtIDg4DQoNCiAgICAgICAgJE5vdGljZVRvcCA9ICRCdXR0b25Ub3AgLSAzMg0KDQogICAgICAg

ICRMaXN0VG9wID0gJEhlYWRlckhlaWdodCArIDI4DQoNCiAgICAgICAgJExpc3RIZWlnaHQgPSAkTm90aWNlVG9wIC0gJExpc3RU

b3AgLSAxNg0KDQoNCiAgICAgICAgaWYgKCRMaXN0SGVpZ2h0IC1sdCAxNjApIHsNCg0KICAgICAgICAgICAgJExpc3RIZWlnaHQg

PSAxNjANCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJExpc3RDYXJkLlNldEJvdW5kcygkTGVmdCwgJExpc3RUb3AsICRDb250ZW50

V2lkdGgsICRMaXN0SGVpZ2h0KQ0KDQogICAgICAgICRMaXN0LlNldEJvdW5kcygxLCAxLCAoJENvbnRlbnRXaWR0aCAtIDIpLCAo

JExpc3RIZWlnaHQgLSAyKSkNCg0KICAgICAgICAkTm90aWNlLlNldEJvdW5kcygkTGVmdCwgJE5vdGljZVRvcCwgJENvbnRlbnRX

aWR0aCwgMjQpDQoNCg0KICAgICAgICAkTWFya0FsbC5TZXRCb3VuZHMoJExlZnQsICRCdXR0b25Ub3AsIDE2MCwgNTIpDQoNCiAg

ICAgICAgJENsZWFyQWxsLlNldEJvdW5kcygoJExlZnQgKyAxNzYpLCAkQnV0dG9uVG9wLCAxODAsIDUyKQ0KDQogICAgICAgICRB

cHBseS5TZXRCb3VuZHMoKCRMZWZ0ICsgJENvbnRlbnRXaWR0aCAtIDE4MCksICRCdXR0b25Ub3AsIDE4MCwgNTIpDQoNCiAgICAg

ICAgJENhbmNlbC5TZXRCb3VuZHMoKCRMZWZ0ICsgJENvbnRlbnRXaWR0aCAtIDE4MCAtIDE2IC0gMTUwKSwgJEJ1dHRvblRvcCwg

MTUwLCA1MikNCiAgICB9LkdldE5ld0Nsb3N1cmUoKQ0KDQoNCiAgICAmICRVcGRhdGVMYXlvdXQNCg0KDQogICAgJEZvcm0uQWRk

X1Nob3duKHsNCg0KICAgICAgICAkRm9ybS5Cb3VuZHMgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2NyZWVuXTo6UHJpbWFyeVNj

cmVlbi5Cb3VuZHMNCg0KICAgICAgICAkRm9ybS5XaW5kb3dTdGF0ZSA9ICJOb3JtYWwiDQoNCiAgICAgICAgJiAkVXBkYXRlTGF5

b3V0DQoNCiAgICAgICAgJEhhbmRsZSA9ICRGb3JtLkhhbmRsZQ0KDQogICAgICAgICRGbGFncyA9IFt1aW50MzJdKDB4MDAwMSAt

Ym9yIDB4MDAwMiAtYm9yIDB4MDA0MCkNCg0KICAgICAgICBbdm9pZF1bQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OlNldFdp

bmRvd1BvcygNCiAgICAgICAgICAgICRIYW5kbGUsDQogICAgICAgICAgICBbSW50UHRyXSgtMSksDQogICAgICAgICAgICAwLA0K

ICAgICAgICAgICAgMCwNCiAgICAgICAgICAgIDAsDQogICAgICAgICAgICAwLA0KICAgICAgICAgICAgJEZsYWdzDQogICAgICAg

ICkNCg0KICAgICAgICAkRm9yZWdyb3VuZCA9IFtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6R2V0Rm9yZWdyb3VuZFdpbmRv

dygpDQoNCiAgICAgICAgJEZvcmVncm91bmRUaHJlYWQgPSBbQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OkdldFdpbmRvd1Ro

cmVhZFByb2Nlc3NJZCgNCiAgICAgICAgICAgICRGb3JlZ3JvdW5kLA0KICAgICAgICAgICAgW0ludFB0cl06Olplcm8NCiAgICAg

ICAgKQ0KDQogICAgICAgICRDdXJyZW50VGhyZWFkID0gW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpHZXRDdXJyZW50VGhy

ZWFkSWQoKQ0KDQoNCiAgICAgICAgaWYgKCRGb3JlZ3JvdW5kVGhyZWFkIC1uZSAkQ3VycmVudFRocmVhZCkgew0KDQogICAgICAg

ICAgICBbdm9pZF1bQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OkF0dGFjaFRocmVhZElucHV0KA0KICAgICAgICAgICAgICAg

ICRGb3JlZ3JvdW5kVGhyZWFkLA0KICAgICAgICAgICAgICAgICRDdXJyZW50VGhyZWFkLA0KICAgICAgICAgICAgICAgICR0cnVl

DQogICAgICAgICAgICApDQogICAgICAgIH0NCg0KDQogICAgICAgIFt2b2lkXVtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6

QnJpbmdXaW5kb3dUb1RvcCgkSGFuZGxlKQ0KDQogICAgICAgIFt2b2lkXVtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6U2V0

Rm9yZWdyb3VuZFdpbmRvdygkSGFuZGxlKQ0KDQoNCiAgICAgICAgaWYgKCRGb3JlZ3JvdW5kVGhyZWFkIC1uZSAkQ3VycmVudFRo

cmVhZCkgew0KDQogICAgICAgICAgICBbdm9pZF1bQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OkF0dGFjaFRocmVhZElucHV0

KA0KICAgICAgICAgICAgICAgICRGb3JlZ3JvdW5kVGhyZWFkLA0KICAgICAgICAgICAgICAgICRDdXJyZW50VGhyZWFkLA0KICAg

ICAgICAgICAgICAgICRmYWxzZQ0KICAgICAgICAgICAgKQ0KICAgICAgICB9DQoNCg0KICAgICAgICAkRm9ybS5Ub3BNb3N0ID0g

JHRydWUNCg0KICAgICAgICAkRm9ybS5BY3RpdmF0ZSgpDQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KDQogICAgJEZvcm0u

VG9wTW9zdCA9ICR0cnVlDQoNCiAgICAkUmVzdWx0ID0gJEZvcm0uU2hvd0RpYWxvZygpDQoNCiAgICAkUGlja2VkID0gTmV3LU9i

amVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10NCg0KDQogICAgaWYgKCRSZXN1bHQgLWVxIFtTeXN0

ZW0uV2luZG93cy5Gb3Jtcy5EaWFsb2dSZXN1bHRdOjpPSykgew0KDQogICAgICAgIGZvciAoJEluZGV4ID0gMDsgJEluZGV4IC1s

dCAkQ2hvaWNlcy5Db3VudDsgJEluZGV4KyspIHsNCg0KICAgICAgICAgICAgaWYgKCRMaXN0LkdldEl0ZW1DaGVja2VkKCRJbmRl

eCkpIHsNCg0KICAgICAgICAgICAgICAgICRQaWNrZWQuQWRkKCRDaG9pY2VzWyRJbmRleF0uSWQpDQogICAgICAgICAgICB9DQog

ICAgICAgIH0NCiAgICB9DQoNCg0KICAgICRGb3JtLkRpc3Bvc2UoKQ0KDQoNCiAgICBpZiAoJFJlc3VsdCAtbmUgW1N5c3RlbS5X

aW5kb3dzLkZvcm1zLkRpYWxvZ1Jlc3VsdF06Ok9LIC1vciAkUGlja2VkLkNvdW50IC1lcSAwKSB7DQoNCiAgICAgICAgcmV0dXJu

ICRudWxsDQogICAgfQ0KDQoNCiAgICByZXR1cm4gLCRQaWNrZWQuVG9BcnJheSgpDQp9DQoNCg0KDQpmdW5jdGlvbiBSZWFkLUN1

c3RvbVdpblNlbGVjdGlvbiB7DQoNCiAgICAkQXBhcnRtZW50ID0gW1RocmVhZGluZy5UaHJlYWRdOjpDdXJyZW50VGhyZWFkLkFw

YXJ0bWVudFN0YXRlDQoNCg0KICAgIGlmICgiJEFwYXJ0bWVudCIgLWVxICJTVEEiKSB7DQoNCiAgICAgICAgdHJ5IHsNCg0KICAg

ICAgICAgICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uV2luZG93cy5Gb3Jtcw0KDQogICAgICAgICAgICBBZGQtVHlw

ZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5EcmF3aW5nDQoNCiAgICAgICAgICAgIFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5BcHBsaWNh

dGlvbl06OkVuYWJsZVZpc3VhbFN0eWxlcygpDQoNCiAgICAgICAgICAgICRQaWNrZWQgPSBTaG93LUN1c3RvbVdpbkZvcm0NCg0K

DQogICAgICAgICAgICBpZiAoJG51bGwgLWVxICRQaWNrZWQpIHsNCg0KICAgICAgICAgICAgICAgIHJldHVybiAkbnVsbA0KICAg

ICAgICAgICAgfQ0KDQoNCiAgICAgICAgICAgIHJldHVybiAsJFBpY2tlZA0KICAgICAgICB9DQogICAgICAgIGNhdGNoIHsNCg0K

ICAgICAgICAgICAgV3JpdGUtTG9nICJObyBzZSBwdWRvIGFicmlyIGxhIHZlbnRhbmEgZGUgc2VsZWNjaW9uOiAkKCRfLkV4Y2Vw

dGlvbi5NZXNzYWdlKSIgIldBUk4iDQogICAgICAgIH0NCiAgICB9DQoNCg0KICAgICRQaWNrZWQgPSBTaG93LUN1c3RvbVdpbkNv

bnNvbGUNCg0KDQogICAgaWYgKCRudWxsIC1lcSAkUGlja2VkKSB7DQoNCiAgICAgICAgcmV0dXJuICRudWxsDQogICAgfQ0KDQoN

CiAgICByZXR1cm4gLCRQaWNrZWQNCn0NCg0KDQpXcml0ZS1Mb2cgIk1lbnU6IDIwMjYxMDIzaSINCg0KDQokU2VsZWN0ZWQgPSBS

ZWFkLUN1c3RvbVdpblNlbGVjdGlvbg0KDQoNCmlmICgkbnVsbCAtZXEgJFNlbGVjdGVkKSB7DQoNCiAgICBXcml0ZS1Ib3N0ICIi

DQogICAgV3JpdGUtSG9zdCAiQ2FuY2VsYWRvLiBObyBzZSBtb2RpZmljbyBuYWRhLiINCiAgICBXcml0ZS1Ib3N0ICIiDQoNCiAg

ICBXcml0ZS1Mb2cgIkVsIHVzdWFyaW8gY2FuY2VsbyBsYSBzZWxlY2Npb24uIiAiV0FSTiINCg0KICAgIFN0b3AtQ3VzdG9tV2lu

IC1Db2RlIDANCn0NCg0KDQokU2VsZWN0ZWQgPSBAKCRTZWxlY3RlZCkNCg0KV3JpdGUtTG9nICgiT3BjaW9uZXMgZWxlZ2lkYXM6

ICIgKyAoJFNlbGVjdGVkIC1qb2luICIsICIpKQ0KDQoNCiRBcmNoaXRlY3R1cmUgPSBHZXQtT3NBcmNoaXRlY3R1cmUNCg0KV3Jp

dGUtTG9nICJBcnF1aXRlY3R1cmE6ICRBcmNoaXRlY3R1cmUiDQoNCg0KaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIkFueURlc2si

KSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIEluc3RhbGwtVW5hdHRlbmRlZEFueURlc2sNCg0KDQogICAgICAgIGlmIChbaW50

XSRzY3JpcHQ6QW55RGVza0V4aXRDb2RlIC1uZSAwKSB7DQoNCiAgICAgICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJBbnlEZXNr

OiBubyBzZSBjb21wbGV0by4gQ29kaWdvICQoJHNjcmlwdDpBbnlEZXNrRXhpdENvZGUpLiINCiAgICAgICAgfQ0KDQogICAgfQ0K

ICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExpbmUgPSAkXy5JbnZvY2F0aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAg

ICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkFueURlc2sgKGxpbmVhICR7RmFpbExpbmV9KTogJCgkXy5FeGNlcHRpb24uTWVzc2Fn

ZSkiDQogICAgfQ0KfQ0KDQoNCiRBcHBOYW1lcyA9IEAoDQogICAgJFNlbGVjdGVkIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAg

JF8gLWluIEAoIk5vdGVwYWQrKyIsICI3LVppcCIsICJGaXJlZm94IiwgIkdvb2dsZSBDaHJvbWUiLCAiUHVUVFkiLCAiV2luU0NQ

IiwgIlZNd2FyZSBUb29scyIpDQogICAgfQ0KKQ0KDQoNCmlmICgkQXBwTmFtZXMuQ291bnQgLWd0IDApIHsNCg0KICAgIEluc3Rh

bGwtQmFzaWNBcHBsaWNhdGlvbnMgLUFyY2hpdGVjdHVyZSAkQXJjaGl0ZWN0dXJlIC1OYW1lcyAkQXBwTmFtZXMNCn0NCg0KDQpp

ZiAoJFNlbGVjdGVkIC1jb250YWlucyAiR2l0Iikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBJbnZva2UtQmluU2NyaXB0IC1O

YW1lICJHaXQiDQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAgICRGYWlsTGluZSA9ICRfLkludm9jYXRpb25JbmZvLlNj

cmlwdExpbmVOdW1iZXINCg0KICAgICAgICBBZGQtRGVwbG95RmFpbHVyZSAiR2l0IChsaW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8u

RXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1jb250YWlucyAiTW9iYVh0ZXJtIikgew0K

DQogICAgdHJ5IHsNCg0KICAgICAgICBJbnZva2UtQmluU2NyaXB0IC1OYW1lICJNb2JhWHRlcm0iDQoNCiAgICB9DQogICAgY2F0

Y2ggew0KDQogICAgICAgICRGYWlsTGluZSA9ICRfLkludm9jYXRpb25JbmZvLlNjcmlwdExpbmVOdW1iZXINCg0KICAgICAgICBB

ZGQtRGVwbG95RmFpbHVyZSAiTW9iYVh0ZXJtIChsaW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0K

ICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQ2FsYyIpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgSW52

b2tlLUJpblNjcmlwdCAtTmFtZSAiQ2FsYyINCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8u

SW52b2NhdGlvbkluZm8uU2NyaXB0TGluZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJDYWxjdWxhZG9yYSAo

bGluZWEgJHtGYWlsTGluZX0pOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KaWYgKCRTZWxlY3RlZCAt

Y29udGFpbnMgIk9mZmljZSIpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgSW5zdGFsbC1PZmZpY2UyMDI0THRzYyAtQXJjaGl0

ZWN0dXJlICRBcmNoaXRlY3R1cmUNCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2Nh

dGlvbkluZm8uU2NyaXB0TGluZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJPZmZpY2UgMjAyNCBMVFNDIChs

aW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1j

b250YWlucyAiUG93ZXJTaGVsbCIpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgV3JpdGUtTG9nICJFamVjdXRhbmRvIENvcnJl

ciBQb3dlcnNoZWxsLiINCg0KICAgICAgICBbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJdOjpTZWN1cml0eVByb3RvY29sID0gW05l

dC5TZWN1cml0eVByb3RvY29sVHlwZV06OlRsczEyDQoNCiAgICAgICAgJFBvd2VyU2hlbGxTY3JpcHQgPSBJbnZva2UtUmVzdE1l

dGhvZCBgDQogICAgICAgICAgICAtVXJpICJodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20vZW1panVua2Uvd2luYmFz

aWMvbWFpbi9wcy5wczEiIGANCiAgICAgICAgICAgIC1Vc2VCYXNpY1BhcnNpbmcNCg0KICAgICAgICBpZiAoJFBvd2VyU2hlbGxT

Y3JpcHQgLWlzIFtTeXN0ZW0uQXJyYXldKSB7DQoNCiAgICAgICAgICAgICRQb3dlclNoZWxsU2NyaXB0ID0gJFBvd2VyU2hlbGxT

Y3JpcHQgLWpvaW4gImBuIg0KICAgICAgICB9DQogICAgICAgIGVsc2VpZiAoJFBvd2VyU2hlbGxTY3JpcHQgLWlzbm90IFtzdHJp

bmddKSB7DQoNCiAgICAgICAgICAgICRQb3dlclNoZWxsU2NyaXB0ID0gW3N0cmluZ10kUG93ZXJTaGVsbFNjcmlwdA0KICAgICAg

ICB9DQoNCg0KICAgICAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkUG93ZXJTaGVsbFNjcmlwdCkpIHsNCg0K

ICAgICAgICAgICAgdGhyb3cgInBzLnBzMSBsbGVnbyB2YWNpby4iDQogICAgICAgIH0NCg0KDQogICAgICAgIGlmICgkUG93ZXJT

aGVsbFNjcmlwdC5Db250YWlucygibGluZXMgY29sbGFwc2VkIikpIHsNCg0KICAgICAgICAgICAgdGhyb3cgInBzLnBzMSBubyBz

ZSBwdWVkZSBlamVjdXRhcjogZWwgYXJjaGl2byBzdWJpZG8gZXN0YSBjb2xhcHNhZG8uIg0KICAgICAgICB9DQoNCg0KICAgICAg

ICBJbnZva2UtRXhwcmVzc2lvbiAkUG93ZXJTaGVsbFNjcmlwdA0KDQogICAgICAgIFdyaXRlLUxvZyAiQ29ycmVyIFBvd2Vyc2hl

bGwgdGVybWluby4iICJPSyINCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlv

bkluZm8uU2NyaXB0TGluZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJDb3JyZXIgUG93ZXJzaGVsbCAobGlu

ZWEgJHtGYWlsTGluZX0pOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KaWYgKCRTZWxlY3RlZCAtY29u

dGFpbnMgIkZpcmV3YWxsIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBEaXNhYmxlLVdpbmRvd3NGaXJld2FsbFBlcm1hbmVu

dGx5DQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJGaXJld2FsbDogJCgkXy5FeGNl

cHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJSZHAiKSB7DQoNCiAgICB0cnkg

ew0KDQogICAgICAgIEVuYWJsZS1SZW1vdGVEZXNrdG9wV2l0aG91dE5sYQ0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAg

ICBBZGQtRGVwbG95RmFpbHVyZSAiRXNjcml0b3JpbyByZW1vdG86ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0N

Cg0KDQppZiAoJFNlbGVjdGVkIC1jb250YWlucyAiSVB2NiIpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgRGlzYWJsZS1JUHY2

Q29tcGxldGVseQ0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICBBZGQtRGVwbG95RmFpbHVyZSAiSVB2NjogJCgkXy5F

eGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCiRTY3JpcHQ6SGlkZVNlYXJjaCA9ICRTZWxlY3RlZCAtY29udGFpbnMg

IlNlYXJjaCINCg0KJFNjcmlwdDpBbGlnbkxlZnQgPSAkU2VsZWN0ZWQgLWNvbnRhaW5zICJUYXNrYmFyIg0KDQoNCmlmICgkU2Ny

aXB0OkhpZGVTZWFyY2ggLW9yICRTY3JpcHQ6QWxpZ25MZWZ0KSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIFNldC1UYXNrYmFy

TGF5b3V0DQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJCYXJyYSBkZSB0YXJlYXM6

ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQpHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkVGVtcERp

ciAtRmlsZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB8DQogICAgUmVtb3ZlLUl0ZW0gLUZvcmNlIC1FcnJvckFjdGlv

biBTaWxlbnRseUNvbnRpbnVlDQoNCg0KV3JpdGUtSG9zdCAiIg0KV3JpdGUtSG9zdCAiPT09PT09PT09PT09PT09PT09PT09PT09

PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09Ig0KV3JpdGUtSG9zdCAiIFJFU1VMVEFETyINCldyaXRlLUhvc3Qg

Ij09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSINCldyaXRlLUhvc3Qg

IiINCldyaXRlLUhvc3QgIkxvZzogJExvZ0ZpbGUiDQpXcml0ZS1Ib3N0ICIiDQoNCg0KaWYgKCRTY3JpcHQ6RmFpbHVyZXMuQ291

bnQgLWVxIDApIHsNCg0KICAgIGlmICgkQXBwTmFtZXMuQ291bnQgLWd0IDApIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJQcm9n

cmFtYXMgZWxlZ2lkb3MgICAgICAgICAgICAgICA6IElOU1RBTEFET1MgTyBZQSBQUkVTRU5URVMiDQogICAgfQ0KDQoNCiAgICBp

ZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQW55RGVzayIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJBbnlEZXNrICAgICAgICAg

ICAgICAgICAgICAgICAgIDogSU5TVEFMQURPIg0KDQogICAgICAgIGlmICgkU2NyaXB0Ok5ld0lEKSB7DQoNCiAgICAgICAgICAg

IFdyaXRlLUhvc3QgIkFueURlc2sgSUQgICAgICAgICAgICAgICAgICAgICAgOiAkU2NyaXB0Ok5ld0lEIg0KICAgICAgICB9DQog

ICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiR2l0Iikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkdpdCAg

ICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBJTlNUQUxBRE8gTyBZQSBQUkVTRU5URSINCiAgICB9DQoNCg0KICAgIGlmICgk

U2VsZWN0ZWQgLWNvbnRhaW5zICJNb2JhWHRlcm0iKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiTW9iYVh0ZXJtICAgICAgICAg

ICAgICAgICAgICAgICA6IENPUElBRE8iDQogICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQ2FsYyIpIHsN

Cg0KICAgICAgICBXcml0ZS1Ib3N0ICJDYWxjdWxhZG9yYSAgICAgICAgICAgICAgICAgICAgIDogQUJJRVJUQSINCiAgICB9DQoN

Cg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJPZmZpY2UiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiT2ZmaWNlIDIw

MjQgTFRTQyAgICAgICAgICAgICAgICA6IElOU1RBTEFETyINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5z

ICJQb3dlclNoZWxsIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkNvcnJlciBQb3dlcnNoZWxsICAgICAgICAgICAgICAgOiBF

SkVDVVRBRE8iDQogICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiRmlyZXdhbGwiKSB7DQoNCiAgICAgICAg

V3JpdGUtSG9zdCAiRmlyZXdhbGwgZGUgV2luZG93cyAgICAgICAgICAgICA6IERFU0hBQklMSVRBRE8iDQogICAgfQ0KDQoNCiAg

ICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiUmRwIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkVzY3JpdG9yaW8gcmVtb3Rv

ICAgICAgICAgICAgICAgOiBIQUJJTElUQURPIg0KICAgICAgICBXcml0ZS1Ib3N0ICJBdXRlbnRpY2FjaW9uIGEgbml2ZWwgZGUg

cmVkICAgIDogREVTTUFSQ0FEQSINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJJUHY2Iikgew0KDQog

ICAgICAgIFdyaXRlLUhvc3QgIklQdjYgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBERVNIQUJJTElUQURPIEFMIFJFSU5J

Q0lBUiINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJTZWFyY2giKSB7DQoNCiAgICAgICAgV3JpdGUt

SG9zdCAiQnVzcXVlZGEgZW4gbGEgYmFycmEgZGUgdGFyZWFzIDogT0NVTFRBIg0KICAgIH0NCg0KDQogICAgaWYgKCRTZWxlY3Rl

ZCAtY29udGFpbnMgIlRhc2tiYXIiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiQWxpbmVhY2lvbiBkZSBsYSBiYXJyYSAgICAg

ICAgIDogSVpRVUlFUkRBIg0KICAgIH0NCg0KDQogICAgV3JpdGUtSG9zdCAiIg0KICAgIFdyaXRlLUhvc3QgIkNVU1RPTVdJTiBG

SU5BTElaQURPIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuDQogICAgV3JpdGUtSG9zdCAiIg0KDQoNCiAgICBpZiAoJFNlbGVjdGVk

IC1jb250YWlucyAiSVB2NiIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJSZWluaWNpZSBlbCBlcXVpcG8gcGFyYSBjb21wbGV0

YXIgbGEgZGVzaGFiaWxpdGFjaW9uIGRlIElQdjYuIg0KICAgICAgICBXcml0ZS1Ib3N0ICIiDQogICAgfQ0KDQoNCiAgICBXcml0

ZS1Mb2cgIkN1c3RvbVdpbiBmaW5hbGl6YWRvLiIgIk9LIg0KDQogICAgU3RvcC1DdXN0b21XaW4gLUNvZGUgMA0KfQ0KDQoNCldy

aXRlLUhvc3QgIkNVU1RPTVdJTiBGSU5BTElaQURPIENPTiBFUlJPUkVTIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdw0KDQpXcml0

ZS1Ib3N0ICIiDQoNCmZvcmVhY2ggKCRGYWlsdXJlIGluICRTY3JpcHQ6RmFpbHVyZXMpIHsNCg0KICAgIFdyaXRlLUhvc3QgIiAt

ICRGYWlsdXJlIg0KfQ0KDQpXcml0ZS1Ib3N0ICIiDQpXcml0ZS1Ib3N0ICJSZXZpc2U6ICRMb2dGaWxlIg0KV3JpdGUtSG9zdCAi

Ig0KDQpXcml0ZS1Mb2cgIkN1c3RvbVdpbiBmaW5hbGl6YWRvIGNvbiBlcnJvcmVzLiIgIldBUk4iDQoNClN0b3AtQ3VzdG9tV2lu

IC1Db2RlIDENCg0KDQojIEZpbiBkZWwgc2NyaXB0Lg0K
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

    Write-Log "Revision: 20261023i"

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
