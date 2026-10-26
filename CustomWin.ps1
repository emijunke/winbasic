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
dWx0bywgY29uIHBhc3N3b3JkIGRlIGFjY2VzbyBkZXNhdGVuZGlkbyINCiRTY3JpcHQ6SXRlbV9BbnlkZXNrVW5pbnN0YWxsID0g
IkFueWRlc2sgVW5pbnN0YWxsIg0KJFNjcmlwdDpJdGVtX0ZpcmV3YWxsID0gIkRlc2hhYmlsaXRhciBlbCBGaXJld2FsbCBkZSBX
aW5kb3dzIGVuIHRvZGFzIGxhcyByZWRlcyINCiRTY3JpcHQ6SXRlbV9Fc2NyaXRvcmlvUmVtb3RvID0gIkhhYmlsaXRhciBFc2Ny
aXRvcmlvIHJlbW90byBzaW4gYXV0ZW50aWNhY2lvbiBkZSBuaXZlbCBkZSByZWQiDQokU2NyaXB0Okl0ZW1fSVB2NiA9ICJEZXNo
YWJpbGl0YXIgSVB2NiBlbiB0b2RvIGVsIHNpc3RlbWEiDQokU2NyaXB0Okl0ZW1fQnVzcXVlZGEgPSAiT2N1bHRhciBlbCBjYW1w
byBkZSBidXNxdWVkYSBkZSBsYSBiYXJyYSBkZSB0YXJlYXMiDQokU2NyaXB0Okl0ZW1fQmFycmFUYXJlYXMgPSAiQWxpbmVhciBs
b3MgaWNvbm9zIGRlIGxhIGJhcnJhIGRlIHRhcmVhcyBhIGxhIGl6cXVpZXJkYSINCg0KZnVuY3Rpb24gR2V0LUN1c3RvbVdpbkNo
b2ljZXMgew0KDQogICAgcmV0dXJuIEAoDQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJOb3RlcGFkKysiDQogICAgICAg
ICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX05vdGVwYWQNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0g
IjctWmlwIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV83WmlwDQogICAgICAgIH0sDQogICAgICAgIEB7DQogICAg
ICAgICAgICBJZCA9ICJGaXJlZm94Ig0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9GaXJlZm94DQogICAgICAgIH0s
DQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJHb29nbGUgQ2hyb21lIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6
SXRlbV9DaHJvbWUNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIlB1VFRZIg0KICAgICAgICAgICAg
VGV4dCA9ICRTY3JpcHQ6SXRlbV9QdVRUWQ0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiV2luU0NQ
Ig0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9XaW5TQ1ANCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAg
ICAgIElkID0gIlZNd2FyZSBUb29scyINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fVk13YXJlDQogICAgICAgIH0s
DQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJHaXQiDQogICAgICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX0dpdA0K
ICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiTW9iYVh0ZXJtIg0KICAgICAgICAgICAgVGV4dCA9ICRT
Y3JpcHQ6SXRlbV9Nb2JhWHRlcm0NCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIkNhbGMiDQogICAg
ICAgICAgICBUZXh0ID0gJFNjcmlwdDpJdGVtX0NhbGMNCiAgICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0g
Ik9mZmljZSINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fT2ZmaWNlDQogICAgICAgIH0sDQogICAgICAgIEB7DQog
ICAgICAgICAgICBJZCA9ICJQb3dlclNoZWxsIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9Qb3dlcnNoZWxsDQog
ICAgICAgIH0sDQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJBbnlEZXNrIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3Jp
cHQ6SXRlbV9BbnlEZXNrDQogICAgICAgIH0sDQogICAgICAgIEB7DQogICAgICAgICAgICBJZCA9ICJBbnlkZXNrVW5pbnN0YWxs
Ig0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9BbnlkZXNrVW5pbnN0YWxsDQogICAgICAgIH0sDQogICAgICAgIEB7
DQogICAgICAgICAgICBJZCA9ICJGaXJld2FsbCINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fRmlyZXdhbGwNCiAg
ICAgICAgfSwNCiAgICAgICAgQHsNCiAgICAgICAgICAgIElkID0gIlJkcCINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0
ZW1fRXNjcml0b3Jpb1JlbW90bw0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAiSVB2NiINCiAgICAg
ICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fSVB2Ng0KICAgICAgICB9LA0KICAgICAgICBAew0KICAgICAgICAgICAgSWQgPSAi
U2VhcmNoIg0KICAgICAgICAgICAgVGV4dCA9ICRTY3JpcHQ6SXRlbV9CdXNxdWVkYQ0KICAgICAgICB9LA0KICAgICAgICBAew0K
ICAgICAgICAgICAgSWQgPSAiVGFza2JhciINCiAgICAgICAgICAgIFRleHQgPSAkU2NyaXB0Okl0ZW1fQmFycmFUYXJlYXMNCiAg
ICAgICAgfQ0KICAgICkNCn0NCg0KDQoNCmZ1bmN0aW9uIFNob3ctQ3VzdG9tV2luQ29uc29sZSB7DQoNCiAgICAkQ2hvaWNlcyA9
IEAoR2V0LUN1c3RvbVdpbkNob2ljZXMpDQoNCiAgICAkQ2hlY2tlZCA9IEB7fQ0KDQoNCiAgICBmb3JlYWNoICgkQ2hvaWNlIGlu
ICRDaG9pY2VzKSB7DQoNCiAgICAgICAgJENoZWNrZWRbJENob2ljZS5JZF0gPSAkZmFsc2UNCiAgICB9DQoNCg0KICAgIHdoaWxl
ICgkdHJ1ZSkgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIiINCiAgICAgICAgV3JpdGUtSG9zdCAiTnVtZXJvOiB0aWxkYSBvIGRl
c3RpbGRhLiBBOiB0b2Rhcy4gTjogbmluZ3VuYS4gRW50ZXI6IGFwbGljYXIuIFE6IGNhbmNlbGFyLiINCiAgICAgICAgV3JpdGUt
SG9zdCAiIg0KDQoNCiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAkSW5kZXggLWx0ICRDaG9pY2VzLkNvdW50OyAkSW5kZXgrKykg
ew0KDQogICAgICAgICAgICAkTWFyayA9ICIgIg0KDQogICAgICAgICAgICBpZiAoJENoZWNrZWRbJENob2ljZXNbJEluZGV4XS5J
ZF0pIHsNCg0KICAgICAgICAgICAgICAgICRNYXJrID0gIlgiDQogICAgICAgICAgICB9DQoNCg0KICAgICAgICAgICAgV3JpdGUt
SG9zdCAoIlt7MH1dIHsxfS4gezJ9IiAtZiAkTWFyaywgKCRJbmRleCArIDEpLCAkQ2hvaWNlc1skSW5kZXhdLlRleHQpDQogICAg
ICAgIH0NCg0KDQogICAgICAgICRBbnN3ZXIgPSBSZWFkLUhvc3QgIk9wY2lvbiINCg0KDQogICAgICAgIGlmIChbc3RyaW5nXTo6
SXNOdWxsT3JXaGl0ZVNwYWNlKCRBbnN3ZXIpKSB7DQoNCiAgICAgICAgICAgICRQaWNrZWQgPSBAKA0KICAgICAgICAgICAgICAg
ICRDaG9pY2VzIHwNCiAgICAgICAgICAgICAgICAgICAgV2hlcmUtT2JqZWN0IHsgJENoZWNrZWRbJF8uSWRdIH0gfA0KICAgICAg
ICAgICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7ICRfLklkIH0NCiAgICAgICAgICAgICkNCg0KDQogICAgICAgICAgICBpZiAo
JFBpY2tlZC5Db3VudCAtZXEgMCkgew0KDQogICAgICAgICAgICAgICAgV3JpdGUtSG9zdCAiVGlsZGEgYWwgbWVub3MgdW5hIG9w
Y2lvbi4iDQoNCiAgICAgICAgICAgICAgICBjb250aW51ZQ0KICAgICAgICAgICAgfQ0KDQoNCiAgICAgICAgICAgIHJldHVybiAs
JFBpY2tlZA0KICAgICAgICB9DQoNCg0KICAgICAgICBpZiAoJEFuc3dlciAtZXEgIlEiIC1vciAkQW5zd2VyIC1lcSAicSIpIHsN
Cg0KICAgICAgICAgICAgcmV0dXJuICRudWxsDQogICAgICAgIH0NCg0KDQogICAgICAgIGlmICgkQW5zd2VyIC1lcSAiQSIgLW9y
ICRBbnN3ZXIgLWVxICJhIikgew0KDQogICAgICAgICAgICBmb3JlYWNoICgkQ2hvaWNlIGluICRDaG9pY2VzKSB7DQoNCiAgICAg
ICAgICAgICAgICAkQ2hlY2tlZFskQ2hvaWNlLklkXSA9ICR0cnVlDQogICAgICAgICAgICB9DQoNCiAgICAgICAgICAgIGNvbnRp
bnVlDQogICAgICAgIH0NCg0KDQogICAgICAgIGlmICgkQW5zd2VyIC1lcSAiTiIgLW9yICRBbnN3ZXIgLWVxICJuIikgew0KDQog
ICAgICAgICAgICBmb3JlYWNoICgkQ2hvaWNlIGluICRDaG9pY2VzKSB7DQoNCiAgICAgICAgICAgICAgICAkQ2hlY2tlZFskQ2hv
aWNlLklkXSA9ICRmYWxzZQ0KICAgICAgICAgICAgfQ0KDQogICAgICAgICAgICBjb250aW51ZQ0KICAgICAgICB9DQoNCg0KICAg
ICAgICAkTnVtYmVyID0gMA0KDQoNCiAgICAgICAgaWYgKA0KICAgICAgICAgICAgW2ludF06OlRyeVBhcnNlKCRBbnN3ZXIsIFty
ZWZdJE51bWJlcikgLWFuZA0KICAgICAgICAgICAgJE51bWJlciAtZ2UgMSAtYW5kDQogICAgICAgICAgICAkTnVtYmVyIC1sZSAk
Q2hvaWNlcy5Db3VudA0KICAgICAgICApIHsNCg0KICAgICAgICAgICAgJElkID0gJENob2ljZXNbJE51bWJlciAtIDFdLklkDQoN
CiAgICAgICAgICAgICRDaGVja2VkWyRJZF0gPSAtbm90ICRDaGVja2VkWyRJZF0NCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KDQoN
CmZ1bmN0aW9uIFNob3ctQ3VzdG9tV2luRm9ybSB7DQoNCiAgICBpZiAoLW5vdCAoIkN1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ci
IC1hcyBbdHlwZV0pKSB7DQoNCiAgICAgICAgQWRkLVR5cGUgLU5hbWVzcGFjZSBDdXN0b21XaW4gLU5hbWUgQ3VzdG9tV2luV2lu
ZG93IC1NZW1iZXJEZWZpbml0aW9uIEAiDQpbU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLkRsbEltcG9ydCgidXNlcjMy
LmRsbCIpXQ0KcHVibGljIHN0YXRpYyBleHRlcm4gYm9vbCBTZXRXaW5kb3dQb3MoU3lzdGVtLkludFB0ciBoV25kLCBTeXN0ZW0u
SW50UHRyIGhXbmRJbnNlcnRBZnRlciwgaW50IFgsIGludCBZLCBpbnQgY3gsIGludCBjeSwgdWludCB1RmxhZ3MpOw0KW1N5c3Rl
bS5SdW50aW1lLkludGVyb3BTZXJ2aWNlcy5EbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0NCnB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJv
b2wgU2V0Rm9yZWdyb3VuZFdpbmRvdyhTeXN0ZW0uSW50UHRyIGhXbmQpOw0KW1N5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNl
cy5EbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0NCnB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgQnJpbmdXaW5kb3dUb1RvcChTeXN0
ZW0uSW50UHRyIGhXbmQpOw0KW1N5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlcy5EbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0N
CnB1YmxpYyBzdGF0aWMgZXh0ZXJuIFN5c3RlbS5JbnRQdHIgR2V0Rm9yZWdyb3VuZFdpbmRvdygpOw0KW1N5c3RlbS5SdW50aW1l
LkludGVyb3BTZXJ2aWNlcy5EbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0NCnB1YmxpYyBzdGF0aWMgZXh0ZXJuIHVpbnQgR2V0V2lu
ZG93VGhyZWFkUHJvY2Vzc0lkKFN5c3RlbS5JbnRQdHIgaFduZCwgU3lzdGVtLkludFB0ciBQcm9jZXNzSWQpOw0KW1N5c3RlbS5S
dW50aW1lLkludGVyb3BTZXJ2aWNlcy5EbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIpXQ0KcHVibGljIHN0YXRpYyBleHRlcm4gdWlu
dCBHZXRDdXJyZW50VGhyZWFkSWQoKTsNCltTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXMuRGxsSW1wb3J0KCJ1c2VyMzIu
ZGxsIildDQpwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIEF0dGFjaFRocmVhZElucHV0KHVpbnQgaWRBdHRhY2gsIHVpbnQgaWRB
dHRhY2hUbywgYm9vbCBmQXR0YWNoKTsNCiJADQogICAgfQ0KDQoNCiAgICAkQ2hvaWNlcyA9IEAoR2V0LUN1c3RvbVdpbkNob2lj
ZXMpDQoNCiAgICAkQ2FudmFzID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMjQ0LCAyNDYsIDI0OCkNCg0KICAg
ICRJbmsgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigxNSwgMjMsIDQyKQ0KDQogICAgJE11dGVkID0gW1N5c3Rl
bS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoNzEsIDg1LCAxMDUpDQoNCiAgICAkQWNjZW50ID0gW1N5c3RlbS5EcmF3aW5nLkNv
bG9yXTo6RnJvbUFyZ2IoMzcsIDk5LCAyMzUpDQoNCiAgICAkQWNjZW50RGFyayA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZy
b21BcmdiKDI5LCA3OCwgMjE2KQ0KDQogICAgJExpbmUgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyMjYsIDIz
MiwgMjQwKQ0KDQogICAgJENhcmQgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpXaGl0ZQ0KDQoNCiAgICAkRm9ybSA9IE5ldy1P
YmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuRm9ybQ0KDQogICAgJEZvcm0uVGV4dCA9ICJDdXN0b21XaW4iDQoNCiAgICAkRm9y
bS5TdGFydFBvc2l0aW9uID0gIk1hbnVhbCINCg0KICAgICRGb3JtLkZvcm1Cb3JkZXJTdHlsZSA9ICJOb25lIg0KDQogICAgJEZv
cm0uV2luZG93U3RhdGUgPSAiTm9ybWFsIg0KDQogICAgJEZvcm0uS2V5UHJldmlldyA9ICR0cnVlDQoNCiAgICAkRm9ybS5TaG93
SW5UYXNrYmFyID0gJHRydWUNCg0KICAgICRTY3JlZW5Cb3VuZHMgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2NyZWVuXTo6UHJp
bWFyeVNjcmVlbi5Cb3VuZHMNCg0KICAgICRGb3JtLkJvdW5kcyA9ICRTY3JlZW5Cb3VuZHMNCg0KICAgICRGb3JtLkZvbnQgPSBO
ZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMTApDQoNCiAgICAkRm9ybS5CYWNrQ29sb3IgPSAkQ2Fu
dmFzDQoNCiAgICAkRm9ybS5Gb3JlQ29sb3IgPSAkSW5rDQoNCiAgICAkRm9ybS5Ub3BNb3N0ID0gJHRydWUNCg0KDQogICAgJEhl
YWRlciA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuUGFuZWwNCg0KICAgICRIZWFkZXIuTG9jYXRpb24gPSBOZXct
T2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50KDAsIDApDQoNCiAgICAkSGVhZGVyLlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5E
cmF3aW5nLlNpemUoNzAwLCAxMDgpDQoNCiAgICAkSGVhZGVyLkJhY2tDb2xvciA9ICRBY2NlbnQNCg0KICAgICRGb3JtLkNvbnRy
b2xzLkFkZCgkSGVhZGVyKQ0KDQoNCiAgICAkVGl0bGUgPSBOZXctT2JqZWN0IFN5c3RlbS5XaW5kb3dzLkZvcm1zLkxhYmVsDQoN
CiAgICAkVGl0bGUuVGV4dCA9ICItLSBTRUxFQ0NJT05BIFFVRSBRVUVSRVMgQVBMSUNBUiAtLSINCg0KICAgICRUaXRsZS5BdXRv
U2l6ZSA9ICRmYWxzZQ0KDQogICAgJFRpdGxlLlRleHRBbGlnbiA9IFtTeXN0ZW0uRHJhd2luZy5Db250ZW50QWxpZ25tZW50XTo6
TWlkZGxlQ2VudGVyDQoNCiAgICAkVGl0bGUuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NDAsIDM2KQ0K
DQogICAgJFRpdGxlLkZvbnQgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMjYsIFtTeXN0ZW0u
RHJhd2luZy5Gb250U3R5bGVdOjpCb2xkKQ0KDQogICAgJFRpdGxlLkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06
OldoaXRlDQoNCiAgICAkVGl0bGUuQmFja0NvbG9yID0gJEFjY2VudA0KDQogICAgJFRpdGxlLkxvY2F0aW9uID0gTmV3LU9iamVj
dCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgyOCwgMjYpDQoNCiAgICAkSGVhZGVyLkNvbnRyb2xzLkFkZCgkVGl0bGUpDQoNCg0KICAg
ICRIaW50ID0gTmV3LU9iamVjdCBTeXN0ZW0uV2luZG93cy5Gb3Jtcy5MYWJlbA0KDQogICAgJEhpbnQuVGV4dCA9ICJOYWRhIGVt
cGllemEgdGlsZGFkby4gTWFyY2EgbG8gcXVlIHF1ZXJlcyBhcGxpY2FyLiBMbyBkZW1hcyBubyBzZSBtb2RpZmljYS4iDQoNCiAg
ICAkSGludC5BdXRvU2l6ZSA9ICRmYWxzZQ0KDQogICAgJEhpbnQuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6
ZSg2NDAsIDI0KQ0KDQogICAgJEhpbnQuRm9udCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuRm9udCgiU2Vnb2UgVUkiLCAx
MCkNCg0KICAgICRIaW50LkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDIxOSwgMjM0LCAyNTQp
DQoNCiAgICAkSGludC5CYWNrQ29sb3IgPSAkQWNjZW50DQoNCiAgICAkSGludC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVt
LkRyYXdpbmcuUG9pbnQoMjgsIDY2KQ0KDQogICAgJEhlYWRlci5Db250cm9scy5BZGQoJEhpbnQpDQoNCg0KICAgICRMaXN0Q2Fy
ZCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuUGFuZWwNCg0KICAgICRMaXN0Q2FyZC5Mb2NhdGlvbiA9IE5ldy1P
YmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMjQsIDEyOCkNCg0KICAgICRMaXN0Q2FyZC5TaXplID0gTmV3LU9iamVjdCBTeXN0
ZW0uRHJhd2luZy5TaXplKDY1MiwgNDUyKQ0KDQogICAgJExpc3RDYXJkLkJhY2tDb2xvciA9ICRMaW5lDQoNCiAgICAkRm9ybS5D
b250cm9scy5BZGQoJExpc3RDYXJkKQ0KDQoNCiAgICAkTGlzdCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQ2hl
Y2tlZExpc3RCb3gNCg0KICAgICRMaXN0LkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgxLCAxKQ0K
DQogICAgJExpc3QuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NTAsIDQ1MCkNCg0KICAgICRMaXN0LkNo
ZWNrT25DbGljayA9ICR0cnVlDQoNCiAgICAkTGlzdC5Cb3JkZXJTdHlsZSA9ICJOb25lIg0KDQogICAgJExpc3QuSW50ZWdyYWxI
ZWlnaHQgPSAkZmFsc2UNCg0KICAgICRMaXN0LkRyYXdNb2RlID0gIk93bmVyRHJhd0ZpeGVkIg0KDQogICAgJExpc3QuSXRlbUhl
aWdodCA9IDQ0DQoNCiAgICAkTGlzdC5Gb250ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDEx
KQ0KDQogICAgJExpc3QuQmFja0NvbG9yID0gJENhcmQNCg0KICAgICRMaXN0LkZvcmVDb2xvciA9ICRJbmsNCg0KICAgICRzY3Jp
cHQ6Q3VzdG9tV2luSG92ZXJJbmRleCA9IC0xDQoNCg0KICAgICRMaXN0LkFkZF9EcmF3SXRlbSh7DQoNCiAgICAgICAgcGFyYW0o
JHNlbmRlciwgJGUpDQoNCiAgICAgICAgaWYgKCRlLkluZGV4IC1sdCAwKSB7IHJldHVybiB9DQoNCiAgICAgICAgJEdyYXBoaWNz
ID0gJGUuR3JhcGhpY3MNCg0KICAgICAgICAkR3JhcGhpY3MuU21vb3RoaW5nTW9kZSA9IFtTeXN0ZW0uRHJhd2luZy5EcmF3aW5n
MkQuU21vb3RoaW5nTW9kZV06OkFudGlBbGlhcw0KDQogICAgICAgICRCb3VuZHMgPSAkZS5Cb3VuZHMNCg0KICAgICAgICAkSXND
aGVja2VkID0gJExpc3QuR2V0SXRlbUNoZWNrZWQoJGUuSW5kZXgpDQoNCiAgICAgICAgJElzSG90ID0gJGUuSW5kZXggLWVxICRz
Y3JpcHQ6Q3VzdG9tV2luSG92ZXJJbmRleA0KDQogICAgICAgICRCYWNrID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUN
Cg0KICAgICAgICBpZiAoJElzQ2hlY2tlZCkgew0KDQogICAgICAgICAgICAkQmFjayA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06
OkZyb21BcmdiKDIzOSwgMjQ2LCAyNTUpDQoNCiAgICAgICAgfQ0KICAgICAgICBlbHNlaWYgKCRJc0hvdCkgew0KDQogICAgICAg
ICAgICAkQmFjayA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDI0OCwgMjUwLCAyNTIpDQogICAgICAgIH0NCg0K
ICAgICAgICAkQmFja0JydXNoID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Tb2xpZEJydXNoICRCYWNrDQoNCiAgICAgICAg
JEdyYXBoaWNzLkZpbGxSZWN0YW5nbGUoJEJhY2tCcnVzaCwgJEJvdW5kcykNCg0KICAgICAgICAkQmFja0JydXNoLkRpc3Bvc2Uo
KQ0KDQogICAgICAgICRCb3hUb3AgPSAkQm91bmRzLlkgKyBbaW50XSgoJEJvdW5kcy5IZWlnaHQgLSAxOCkgLyAyKQ0KDQogICAg
ICAgICRCb3ggPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlJlY3RhbmdsZSgoJEJvdW5kcy5YICsgMjIpLCAkQm94VG9wLCAx
OCwgMTgpDQoNCiAgICAgICAgJEJsdWUgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigzNywgOTksIDIzNSkNCg0K
ICAgICAgICBpZiAoJElzQ2hlY2tlZCkgew0KDQogICAgICAgICAgICAkRmlsbCA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcu
U29saWRCcnVzaCAkQmx1ZQ0KDQogICAgICAgICAgICAkR3JhcGhpY3MuRmlsbFJlY3RhbmdsZSgkRmlsbCwgJEJveCkNCg0KICAg
ICAgICAgICAgJEZpbGwuRGlzcG9zZSgpDQoNCiAgICAgICAgICAgICRNYXJrUGVuID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2lu
Zy5QZW4gKFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OldoaXRlKSwgMg0KDQogICAgICAgICAgICAkUG9pbnRzID0gTmV3LU9iamVj
dCAnU3lzdGVtLkRyYXdpbmcuUG9pbnRbXScgMw0KDQogICAgICAgICAgICAkUG9pbnRzWzBdID0gTmV3LU9iamVjdCBTeXN0ZW0u
RHJhd2luZy5Qb2ludCAoKCRCb3guWCArIDQpLCAoJEJveC5ZICsgOSkpDQoNCiAgICAgICAgICAgICRQb2ludHNbMV0gPSBOZXct
T2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50ICgoJEJveC5YICsgOCksICgkQm94LlkgKyAxMykpDQoNCiAgICAgICAgICAgICRQ
b2ludHNbMl0gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50ICgoJEJveC5YICsgMTQpLCAoJEJveC5ZICsgNSkpDQoN
CiAgICAgICAgICAgICRHcmFwaGljcy5EcmF3TGluZXMoJE1hcmtQZW4sICRQb2ludHMpDQoNCiAgICAgICAgICAgICRNYXJrUGVu
LkRpc3Bvc2UoKQ0KDQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQoNCiAgICAgICAgICAgICRCb3hQZW4gPSBOZXctT2JqZWN0
IFN5c3RlbS5EcmF3aW5nLlBlbiAoW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMTQ4LCAxNjMsIDE4NCkpDQoNCiAg
ICAgICAgICAgICRHcmFwaGljcy5EcmF3UmVjdGFuZ2xlKCRCb3hQZW4sICRCb3gpDQoNCiAgICAgICAgICAgICRCb3hQZW4uRGlz
cG9zZSgpDQogICAgICAgIH0NCg0KICAgICAgICAkVGV4dEJydXNoID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Tb2xpZEJy
dXNoIChbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigxNSwgMjMsIDQyKSkNCg0KICAgICAgICAkVGV4dFJlY3QgPSBO
ZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlJlY3RhbmdsZSgoJEJvdW5kcy5YICsgNDgpLCAkQm91bmRzLlksICgkQm91bmRzLldp
ZHRoIC0gNjApLCAkQm91bmRzLkhlaWdodCkNCg0KICAgICAgICAkRm9ybWF0ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5T
dHJpbmdGb3JtYXQNCg0KICAgICAgICAkRm9ybWF0LkxpbmVBbGlnbm1lbnQgPSBbU3lzdGVtLkRyYXdpbmcuU3RyaW5nQWxpZ25t
ZW50XTo6Q2VudGVyDQoNCiAgICAgICAgJEZvcm1hdC5UcmltbWluZyA9IFtTeXN0ZW0uRHJhd2luZy5TdHJpbmdUcmltbWluZ106
OkVsbGlwc2lzQ2hhcmFjdGVyDQoNCiAgICAgICAgJEZvcm1hdC5Gb3JtYXRGbGFncyA9IFtTeXN0ZW0uRHJhd2luZy5TdHJpbmdG
b3JtYXRGbGFnc106Ok5vV3JhcA0KDQogICAgICAgICRHcmFwaGljcy5EcmF3U3RyaW5nKFtzdHJpbmddJExpc3QuSXRlbXNbJGUu
SW5kZXhdLCAkZS5Gb250LCAkVGV4dEJydXNoLCAkVGV4dFJlY3QsICRGb3JtYXQpDQoNCiAgICAgICAgJFRleHRCcnVzaC5EaXNw
b3NlKCkNCg0KICAgICAgICAkRm9ybWF0LkRpc3Bvc2UoKQ0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoNCiAgICAkTGlzdC5B
ZGRfTW91c2VNb3ZlKHsNCg0KICAgICAgICBwYXJhbSgkc2VuZGVyLCAkZSkNCg0KICAgICAgICAkSW5kZXggPSAkTGlzdC5JbmRl
eEZyb21Qb2ludCgkZS5Mb2NhdGlvbikNCg0KICAgICAgICBpZiAoJEluZGV4IC1uZSAkc2NyaXB0OkN1c3RvbVdpbkhvdmVySW5k
ZXgpIHsNCg0KICAgICAgICAgICAgJHNjcmlwdDpDdXN0b21XaW5Ib3ZlckluZGV4ID0gJEluZGV4DQoNCiAgICAgICAgICAgICRM
aXN0LkludmFsaWRhdGUoKQ0KICAgICAgICB9DQoNCiAgICB9LkdldE5ld0Nsb3N1cmUoKSkNCg0KICAgICRMaXN0LkFkZF9Nb3Vz
ZUxlYXZlKHsNCg0KICAgICAgICAkc2NyaXB0OkN1c3RvbVdpbkhvdmVySW5kZXggPSAtMQ0KDQogICAgICAgICRMaXN0LkludmFs
aWRhdGUoKQ0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoNCg0KICAgIGZvcmVhY2ggKCRDaG9pY2UgaW4gJENob2ljZXMpIHsN
Cg0KICAgICAgICBbdm9pZF0kTGlzdC5JdGVtcy5BZGQoJENob2ljZS5UZXh0LCAkZmFsc2UpDQogICAgfQ0KDQoNCiAgICAkTGlz
dENhcmQuQ29udHJvbHMuQWRkKCRMaXN0KQ0KDQoNCiAgICAkTm90aWNlID0gTmV3LU9iamVjdCBTeXN0ZW0uV2luZG93cy5Gb3Jt
cy5MYWJlbA0KDQogICAgJE5vdGljZS5UZXh0ID0gIiINCg0KICAgICROb3RpY2UuQXV0b1NpemUgPSAkZmFsc2UNCg0KICAgICRO
b3RpY2UuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSg2NDAsIDIwKQ0KDQogICAgJE5vdGljZS5Gb250ID0g
TmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Gb250KCJTZWdvZSBVSSIsIDkpDQoNCiAgICAkTm90aWNlLkZvcmVDb2xvciA9IFtT
eXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDE4NSwgMjgsIDI4KQ0KDQogICAgJE5vdGljZS5CYWNrQ29sb3IgPSAkQ2Fu
dmFzDQoNCiAgICAkTm90aWNlLkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5Qb2ludCgyNCwgNTg4KQ0KDQog
ICAgJEZvcm0uQ29udHJvbHMuQWRkKCROb3RpY2UpDQoNCg0KICAgICRMaXN0LkFkZF9TZWxlY3RlZEluZGV4Q2hhbmdlZCh7DQoN
CiAgICAgICAgJE5vdGljZS5UZXh0ID0gIiINCg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQoNCiAgICBmdW5jdGlvbiBTZXQt
Q3VzdG9tV2luRmxhdEJ1dHRvbiB7DQoNCiAgICAgICAgcGFyYW0oDQogICAgICAgICAgICAkQnV0dG9uLA0KICAgICAgICAgICAg
W2Jvb2xdJFByaW1hcnkNCiAgICAgICAgKQ0KDQogICAgICAgICRCdXR0b24uRmxhdFN0eWxlID0gIkZsYXQiDQoNCiAgICAgICAg
JEJ1dHRvbi5DdXJzb3IgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuQ3Vyc29yc106OkhhbmQNCg0KICAgICAgICAkQnV0dG9uLkZv
bnQgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkZvbnQoIlNlZ29lIFVJIiwgMTApDQoNCiAgICAgICAgaWYgKCRQcmltYXJ5
KSB7DQoNCiAgICAgICAgICAgICRCdXR0b24uQmFja0NvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMzcs
IDk5LCAyMzUpDQoNCiAgICAgICAgICAgICRCdXR0b24uRm9yZUNvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUN
Cg0KICAgICAgICAgICAgJEJ1dHRvbi5GbGF0QXBwZWFyYW5jZS5Cb3JkZXJTaXplID0gMA0KDQogICAgICAgICAgICAkQnV0dG9u
LkZsYXRBcHBlYXJhbmNlLk1vdXNlT3ZlckJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDI5LCA3
OCwgMjE2KQ0KDQogICAgICAgICAgICAkQnV0dG9uLkZsYXRBcHBlYXJhbmNlLk1vdXNlRG93bkJhY2tDb2xvciA9IFtTeXN0ZW0u
RHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDMwLCA2NCwgMTc1KQ0KDQogICAgICAgICAgICByZXR1cm4NCiAgICAgICAgfQ0KDQog
ICAgICAgICRCdXR0b24uQmFja0NvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6V2hpdGUNCg0KICAgICAgICAkQnV0dG9u
LkZvcmVDb2xvciA9IFtTeXN0ZW0uRHJhd2luZy5Db2xvcl06OkZyb21BcmdiKDE1LCAyMywgNDIpDQoNCiAgICAgICAgJEJ1dHRv
bi5GbGF0QXBwZWFyYW5jZS5Cb3JkZXJTaXplID0gMQ0KDQogICAgICAgICRCdXR0b24uRmxhdEFwcGVhcmFuY2UuQm9yZGVyQ29s
b3IgPSBbU3lzdGVtLkRyYXdpbmcuQ29sb3JdOjpGcm9tQXJnYigyMDMsIDIxMywgMjI1KQ0KDQogICAgICAgICRCdXR0b24uRmxh
dEFwcGVhcmFuY2UuTW91c2VPdmVyQmFja0NvbG9yID0gW1N5c3RlbS5EcmF3aW5nLkNvbG9yXTo6RnJvbUFyZ2IoMjQxLCAyNDUs
IDI0OSkNCg0KICAgICAgICAkQnV0dG9uLkZsYXRBcHBlYXJhbmNlLk1vdXNlRG93bkJhY2tDb2xvciA9IFtTeXN0ZW0uRHJhd2lu
Zy5Db2xvcl06OkZyb21BcmdiKDIyNiwgMjMyLCAyNDApDQogICAgfQ0KDQoNCiAgICAkTWFya0FsbCA9IE5ldy1PYmplY3QgU3lz
dGVtLldpbmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAgICAkTWFya0FsbC5UZXh0ID0gIk1hcmNhciB0b2RvIg0KDQogICAgJE1hcmtB
bGwuTG9jYXRpb24gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50KDI0LCA2MTYpDQoNCiAgICAkTWFya0FsbC5TaXpl
ID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5TaXplKDEzMiwgNDApDQoNCiAgICBTZXQtQ3VzdG9tV2luRmxhdEJ1dHRvbiAt
QnV0dG9uICRNYXJrQWxsIC1QcmltYXJ5ICRmYWxzZQ0KDQogICAgJE1hcmtBbGwuQWRkX0NsaWNrKHsNCg0KICAgICAgICBmb3Ig
KCRJbmRleCA9IDA7ICRJbmRleCAtbHQgJExpc3QuSXRlbXMuQ291bnQ7ICRJbmRleCsrKSB7DQoNCiAgICAgICAgICAgICRMaXN0
LlNldEl0ZW1DaGVja2VkKCRJbmRleCwgJHRydWUpDQogICAgICAgIH0NCg0KICAgICAgICAkTm90aWNlLlRleHQgPSAiIg0KDQog
ICAgfS5HZXROZXdDbG9zdXJlKCkpDQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJE1hcmtBbGwpDQoNCg0KICAgICRDbGVhckFs
bCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAgICAkQ2xlYXJBbGwuVGV4dCA9ICJEZXNtYXJj
YXIgdG9kbyINCg0KICAgICRDbGVhckFsbC5Mb2NhdGlvbiA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuUG9pbnQoMTY0LCA2
MTYpDQoNCiAgICAkQ2xlYXJBbGwuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSgxNDgsIDQwKQ0KDQogICAg
U2V0LUN1c3RvbVdpbkZsYXRCdXR0b24gLUJ1dHRvbiAkQ2xlYXJBbGwgLVByaW1hcnkgJGZhbHNlDQoNCiAgICAkQ2xlYXJBbGwu
QWRkX0NsaWNrKHsNCg0KICAgICAgICBmb3IgKCRJbmRleCA9IDA7ICRJbmRleCAtbHQgJExpc3QuSXRlbXMuQ291bnQ7ICRJbmRl
eCsrKSB7DQoNCiAgICAgICAgICAgICRMaXN0LlNldEl0ZW1DaGVja2VkKCRJbmRleCwgJGZhbHNlKQ0KICAgICAgICB9DQoNCiAg
ICAgICAgJE5vdGljZS5UZXh0ID0gIiINCg0KICAgIH0uR2V0TmV3Q2xvc3VyZSgpKQ0KDQogICAgJEZvcm0uQ29udHJvbHMuQWRk
KCRDbGVhckFsbCkNCg0KDQogICAgJENhbmNlbCA9IE5ldy1PYmplY3QgU3lzdGVtLldpbmRvd3MuRm9ybXMuQnV0dG9uDQoNCiAg
ICAkQ2FuY2VsLlRleHQgPSAiQ2FuY2VsYXIiDQoNCiAgICAkQ2FuY2VsLkxvY2F0aW9uID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJh
d2luZy5Qb2ludCg0MDQsIDYxNikNCg0KICAgICRDYW5jZWwuU2l6ZSA9IE5ldy1PYmplY3QgU3lzdGVtLkRyYXdpbmcuU2l6ZSgx
MjAsIDQwKQ0KDQogICAgJENhbmNlbC5EaWFsb2dSZXN1bHQgPSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuRGlhbG9nUmVzdWx0XTo6
Q2FuY2VsDQoNCiAgICBTZXQtQ3VzdG9tV2luRmxhdEJ1dHRvbiAtQnV0dG9uICRDYW5jZWwgLVByaW1hcnkgJGZhbHNlDQoNCiAg
ICAkRm9ybS5DYW5jZWxCdXR0b24gPSAkQ2FuY2VsDQoNCiAgICAkRm9ybS5Db250cm9scy5BZGQoJENhbmNlbCkNCg0KDQogICAg
JEFwcGx5ID0gTmV3LU9iamVjdCBTeXN0ZW0uV2luZG93cy5Gb3Jtcy5CdXR0b24NCg0KICAgICRBcHBseS5UZXh0ID0gIkFwbGlj
YXIiDQoNCiAgICAkQXBwbHkuTG9jYXRpb24gPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlBvaW50KDUzNiwgNjE2KQ0KDQog
ICAgJEFwcGx5LlNpemUgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLlNpemUoMTQwLCA0MCkNCg0KICAgIFNldC1DdXN0b21X
aW5GbGF0QnV0dG9uIC1CdXR0b24gJEFwcGx5IC1QcmltYXJ5ICR0cnVlDQoNCiAgICAkQXBwbHkuQWRkX0NsaWNrKHsNCg0KICAg
ICAgICAkQW55Q2hlY2tlZCA9ICRmYWxzZQ0KDQoNCiAgICAgICAgZm9yICgkSW5kZXggPSAwOyAkSW5kZXggLWx0ICRMaXN0Lkl0
ZW1zLkNvdW50OyAkSW5kZXgrKykgew0KDQogICAgICAgICAgICBpZiAoJExpc3QuR2V0SXRlbUNoZWNrZWQoJEluZGV4KSkgew0K
DQogICAgICAgICAgICAgICAgJEFueUNoZWNrZWQgPSAkdHJ1ZQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQoNCg0KICAgICAg
ICBpZiAoLW5vdCAkQW55Q2hlY2tlZCkgew0KDQogICAgICAgICAgICAkTm90aWNlLlRleHQgPSAiVGlsZGEgYWwgbWVub3MgdW5h
IG9wY2lvbi4iDQoNCiAgICAgICAgICAgIHJldHVybg0KICAgICAgICB9DQoNCg0KICAgICAgICAkRm9ybS5EaWFsb2dSZXN1bHQg
PSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuRGlhbG9nUmVzdWx0XTo6T0sNCg0KICAgICAgICAkRm9ybS5DbG9zZSgpDQoNCiAgICB9
LkdldE5ld0Nsb3N1cmUoKSkNCg0KICAgICRGb3JtLkNvbnRyb2xzLkFkZCgkQXBwbHkpDQoNCiAgICAkRm9ybS5BY2NlcHRCdXR0
b24gPSAkQXBwbHkNCg0KDQogICAgJFVwZGF0ZUxheW91dCA9IHsNCg0KICAgICAgICAkV2lkdGggPSAkRm9ybS5DbGllbnRTaXpl
LldpZHRoDQoNCiAgICAgICAgJEhlaWdodCA9ICRGb3JtLkNsaWVudFNpemUuSGVpZ2h0DQoNCg0KICAgICAgICBpZiAoJFdpZHRo
IC1sdCA2NDAgLW9yICRIZWlnaHQgLWx0IDQ4MCkgew0KDQogICAgICAgICAgICByZXR1cm4NCiAgICAgICAgfQ0KDQoNCiAgICAg
ICAgJEhlYWRlckhlaWdodCA9IDE0OA0KDQogICAgICAgICRIZWFkZXIuU2V0Qm91bmRzKDAsIDAsICRXaWR0aCwgJEhlYWRlckhl
aWdodCkNCg0KDQogICAgICAgICRDb250ZW50V2lkdGggPSAkV2lkdGggLSAxMjANCg0KDQogICAgICAgIGlmICgkQ29udGVudFdp
ZHRoIC1ndCAxMDgwKSB7DQoNCiAgICAgICAgICAgICRDb250ZW50V2lkdGggPSAxMDgwDQogICAgICAgIH0NCg0KDQogICAgICAg
ICRMZWZ0ID0gW2ludF0oKCRXaWR0aCAtICRDb250ZW50V2lkdGgpIC8gMikNCg0KICAgICAgICAkVGl0bGUuU2V0Qm91bmRzKDAs
IDMyLCAkV2lkdGgsIDU2KQ0KDQogICAgICAgICRIaW50LlNldEJvdW5kcygkTGVmdCwgOTYsICRDb250ZW50V2lkdGgsIDI4KQ0K
DQoNCiAgICAgICAgJEJ1dHRvblRvcCA9ICRIZWlnaHQgLSA4OA0KDQogICAgICAgICROb3RpY2VUb3AgPSAkQnV0dG9uVG9wIC0g
MzINCg0KICAgICAgICAkTGlzdFRvcCA9ICRIZWFkZXJIZWlnaHQgKyAyOA0KDQogICAgICAgICRMaXN0SGVpZ2h0ID0gJE5vdGlj
ZVRvcCAtICRMaXN0VG9wIC0gMTYNCg0KDQogICAgICAgIGlmICgkTGlzdEhlaWdodCAtbHQgMTYwKSB7DQoNCiAgICAgICAgICAg
ICRMaXN0SGVpZ2h0ID0gMTYwDQogICAgICAgIH0NCg0KDQogICAgICAgICRMaXN0Q2FyZC5TZXRCb3VuZHMoJExlZnQsICRMaXN0
VG9wLCAkQ29udGVudFdpZHRoLCAkTGlzdEhlaWdodCkNCg0KICAgICAgICAkTGlzdC5TZXRCb3VuZHMoMSwgMSwgKCRDb250ZW50
V2lkdGggLSAyKSwgKCRMaXN0SGVpZ2h0IC0gMikpDQoNCiAgICAgICAgJE5vdGljZS5TZXRCb3VuZHMoJExlZnQsICROb3RpY2VU
b3AsICRDb250ZW50V2lkdGgsIDI0KQ0KDQoNCiAgICAgICAgJE1hcmtBbGwuU2V0Qm91bmRzKCRMZWZ0LCAkQnV0dG9uVG9wLCAx
NjAsIDUyKQ0KDQogICAgICAgICRDbGVhckFsbC5TZXRCb3VuZHMoKCRMZWZ0ICsgMTc2KSwgJEJ1dHRvblRvcCwgMTgwLCA1MikN
Cg0KICAgICAgICAkQXBwbHkuU2V0Qm91bmRzKCgkTGVmdCArICRDb250ZW50V2lkdGggLSAxODApLCAkQnV0dG9uVG9wLCAxODAs
IDUyKQ0KDQogICAgICAgICRDYW5jZWwuU2V0Qm91bmRzKCgkTGVmdCArICRDb250ZW50V2lkdGggLSAxODAgLSAxNiAtIDE1MCks
ICRCdXR0b25Ub3AsIDE1MCwgNTIpDQogICAgfS5HZXROZXdDbG9zdXJlKCkNCg0KDQogICAgJiAkVXBkYXRlTGF5b3V0DQoNCg0K
ICAgICRGb3JtLkFkZF9TaG93bih7DQoNCiAgICAgICAgJEZvcm0uQm91bmRzID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNjcmVl
bl06OlByaW1hcnlTY3JlZW4uQm91bmRzDQoNCiAgICAgICAgJEZvcm0uV2luZG93U3RhdGUgPSAiTm9ybWFsIg0KDQogICAgICAg
ICYgJFVwZGF0ZUxheW91dA0KDQogICAgICAgICRIYW5kbGUgPSAkRm9ybS5IYW5kbGUNCg0KICAgICAgICAkRmxhZ3MgPSBbdWlu
dDMyXSgweDAwMDEgLWJvciAweDAwMDIgLWJvciAweDAwNDApDQoNCiAgICAgICAgW3ZvaWRdW0N1c3RvbVdpbi5DdXN0b21XaW5X
aW5kb3ddOjpTZXRXaW5kb3dQb3MoDQogICAgICAgICAgICAkSGFuZGxlLA0KICAgICAgICAgICAgW0ludFB0cl0oLTEpLA0KICAg
ICAgICAgICAgMCwNCiAgICAgICAgICAgIDAsDQogICAgICAgICAgICAwLA0KICAgICAgICAgICAgMCwNCiAgICAgICAgICAgICRG
bGFncw0KICAgICAgICApDQoNCiAgICAgICAgJEZvcmVncm91bmQgPSBbQ3VzdG9tV2luLkN1c3RvbVdpbldpbmRvd106OkdldEZv
cmVncm91bmRXaW5kb3coKQ0KDQogICAgICAgICRGb3JlZ3JvdW5kVGhyZWFkID0gW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3dd
OjpHZXRXaW5kb3dUaHJlYWRQcm9jZXNzSWQoDQogICAgICAgICAgICAkRm9yZWdyb3VuZCwNCiAgICAgICAgICAgIFtJbnRQdHJd
OjpaZXJvDQogICAgICAgICkNCg0KICAgICAgICAkQ3VycmVudFRocmVhZCA9IFtDdXN0b21XaW4uQ3VzdG9tV2luV2luZG93XTo6
R2V0Q3VycmVudFRocmVhZElkKCkNCg0KDQogICAgICAgIGlmICgkRm9yZWdyb3VuZFRocmVhZCAtbmUgJEN1cnJlbnRUaHJlYWQp
IHsNCg0KICAgICAgICAgICAgW3ZvaWRdW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpBdHRhY2hUaHJlYWRJbnB1dCgNCiAg
ICAgICAgICAgICAgICAkRm9yZWdyb3VuZFRocmVhZCwNCiAgICAgICAgICAgICAgICAkQ3VycmVudFRocmVhZCwNCiAgICAgICAg
ICAgICAgICAkdHJ1ZQ0KICAgICAgICAgICAgKQ0KICAgICAgICB9DQoNCg0KICAgICAgICBbdm9pZF1bQ3VzdG9tV2luLkN1c3Rv
bVdpbldpbmRvd106OkJyaW5nV2luZG93VG9Ub3AoJEhhbmRsZSkNCg0KICAgICAgICBbdm9pZF1bQ3VzdG9tV2luLkN1c3RvbVdp
bldpbmRvd106OlNldEZvcmVncm91bmRXaW5kb3coJEhhbmRsZSkNCg0KDQogICAgICAgIGlmICgkRm9yZWdyb3VuZFRocmVhZCAt
bmUgJEN1cnJlbnRUaHJlYWQpIHsNCg0KICAgICAgICAgICAgW3ZvaWRdW0N1c3RvbVdpbi5DdXN0b21XaW5XaW5kb3ddOjpBdHRh
Y2hUaHJlYWRJbnB1dCgNCiAgICAgICAgICAgICAgICAkRm9yZWdyb3VuZFRocmVhZCwNCiAgICAgICAgICAgICAgICAkQ3VycmVu
dFRocmVhZCwNCiAgICAgICAgICAgICAgICAkZmFsc2UNCiAgICAgICAgICAgICkNCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJEZv
cm0uVG9wTW9zdCA9ICR0cnVlDQoNCiAgICAgICAgJEZvcm0uQWN0aXZhdGUoKQ0KDQogICAgfS5HZXROZXdDbG9zdXJlKCkpDQoN
Cg0KICAgICRGb3JtLlRvcE1vc3QgPSAkdHJ1ZQ0KDQogICAgJFJlc3VsdCA9ICRGb3JtLlNob3dEaWFsb2coKQ0KDQogICAgJFBp
Y2tlZCA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddDQoNCg0KICAgIGlmICgkUmVz
dWx0IC1lcSBbU3lzdGVtLldpbmRvd3MuRm9ybXMuRGlhbG9nUmVzdWx0XTo6T0spIHsNCg0KICAgICAgICBmb3IgKCRJbmRleCA9
IDA7ICRJbmRleCAtbHQgJENob2ljZXMuQ291bnQ7ICRJbmRleCsrKSB7DQoNCiAgICAgICAgICAgIGlmICgkTGlzdC5HZXRJdGVt
Q2hlY2tlZCgkSW5kZXgpKSB7DQoNCiAgICAgICAgICAgICAgICAkUGlja2VkLkFkZCgkQ2hvaWNlc1skSW5kZXhdLklkKQ0KICAg
ICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KDQoNCiAgICAkRm9ybS5EaXNwb3NlKCkNCg0KDQogICAgaWYgKCRSZXN1bHQg
LW5lIFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5EaWFsb2dSZXN1bHRdOjpPSyAtb3IgJFBpY2tlZC5Db3VudCAtZXEgMCkgew0KDQog
ICAgICAgIHJldHVybiAkbnVsbA0KICAgIH0NCg0KDQogICAgcmV0dXJuICwkUGlja2VkLlRvQXJyYXkoKQ0KfQ0KDQoNCg0KZnVu
Y3Rpb24gUmVhZC1DdXN0b21XaW5TZWxlY3Rpb24gew0KDQogICAgJEFwYXJ0bWVudCA9IFtUaHJlYWRpbmcuVGhyZWFkXTo6Q3Vy
cmVudFRocmVhZC5BcGFydG1lbnRTdGF0ZQ0KDQoNCiAgICBpZiAoIiRBcGFydG1lbnQiIC1lcSAiU1RBIikgew0KDQogICAgICAg
IHRyeSB7DQoNCiAgICAgICAgICAgIEFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLldpbmRvd3MuRm9ybXMNCg0KICAgICAg
ICAgICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uRHJhd2luZw0KDQogICAgICAgICAgICBbU3lzdGVtLldpbmRvd3Mu
Rm9ybXMuQXBwbGljYXRpb25dOjpFbmFibGVWaXN1YWxTdHlsZXMoKQ0KDQogICAgICAgICAgICAkUGlja2VkID0gU2hvdy1DdXN0
b21XaW5Gb3JtDQoNCg0KICAgICAgICAgICAgaWYgKCRudWxsIC1lcSAkUGlja2VkKSB7DQoNCiAgICAgICAgICAgICAgICByZXR1
cm4gJG51bGwNCiAgICAgICAgICAgIH0NCg0KDQogICAgICAgICAgICByZXR1cm4gLCRQaWNrZWQNCiAgICAgICAgfQ0KICAgICAg
ICBjYXRjaCB7DQoNCiAgICAgICAgICAgIFdyaXRlLUxvZyAiTm8gc2UgcHVkbyBhYnJpciBsYSB2ZW50YW5hIGRlIHNlbGVjY2lv
bjogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiICJXQVJOIg0KICAgICAgICB9DQogICAgfQ0KDQoNCiAgICAkUGlja2VkID0gU2hv
dy1DdXN0b21XaW5Db25zb2xlDQoNCg0KICAgIGlmICgkbnVsbCAtZXEgJFBpY2tlZCkgew0KDQogICAgICAgIHJldHVybiAkbnVs
bA0KICAgIH0NCg0KDQogICAgcmV0dXJuICwkUGlja2VkDQp9DQoNCg0KV3JpdGUtTG9nICJNZW51OiAyMDI2MTAyNmEiDQoNCg0K
JFNlbGVjdGVkID0gUmVhZC1DdXN0b21XaW5TZWxlY3Rpb24NCg0KDQppZiAoJG51bGwgLWVxICRTZWxlY3RlZCkgew0KDQogICAg
V3JpdGUtSG9zdCAiIg0KICAgIFdyaXRlLUhvc3QgIkNhbmNlbGFkby4gTm8gc2UgbW9kaWZpY28gbmFkYS4iDQogICAgV3JpdGUt
SG9zdCAiIg0KDQogICAgV3JpdGUtTG9nICJFbCB1c3VhcmlvIGNhbmNlbG8gbGEgc2VsZWNjaW9uLiIgIldBUk4iDQoNCiAgICBT
dG9wLUN1c3RvbVdpbiAtQ29kZSAwDQp9DQoNCg0KJFNlbGVjdGVkID0gQCgkU2VsZWN0ZWQpDQoNCldyaXRlLUxvZyAoIk9wY2lv
bmVzIGVsZWdpZGFzOiAiICsgKCRTZWxlY3RlZCAtam9pbiAiLCAiKSkNCg0KDQokQXJjaGl0ZWN0dXJlID0gR2V0LU9zQXJjaGl0
ZWN0dXJlDQoNCldyaXRlLUxvZyAiQXJxdWl0ZWN0dXJhOiAkQXJjaGl0ZWN0dXJlIg0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRh
aW5zICJBbnlEZXNrIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBJbnN0YWxsLVVuYXR0ZW5kZWRBbnlEZXNrDQoNCg0KICAg
ICAgICBpZiAoW2ludF0kc2NyaXB0OkFueURlc2tFeGl0Q29kZSAtbmUgMCkgew0KDQogICAgICAgICAgICBBZGQtRGVwbG95RmFp
bHVyZSAiQW55RGVzazogbm8gc2UgY29tcGxldG8uIENvZGlnbyAkKCRzY3JpcHQ6QW55RGVza0V4aXRDb2RlKS4iDQogICAgICAg
IH0NCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlvbkluZm8uU2NyaXB0TGlu
ZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJBbnlEZXNrIChsaW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhj
ZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQW55ZGVza1VuaW5zdGFsbCIp
IHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgSW52b2tlLUJpblNjcmlwdCAtTmFtZSAidW5pbnN0YWxsYW55ZGVzayINCg0KICAg
IH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlvbkluZm8uU2NyaXB0TGluZU51bWJlcg0K
DQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJBbnlkZXNrIFVuaW5zdGFsbCAobGluZWEgJHtGYWlsTGluZX0pOiAkKCRfLkV4
Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KJEFwcE5hbWVzID0gQCgNCiAgICAkU2VsZWN0ZWQgfCBXaGVyZS1PYmpl
Y3Qgew0KICAgICAgICAkXyAtaW4gQCgiTm90ZXBhZCsrIiwgIjctWmlwIiwgIkZpcmVmb3giLCAiR29vZ2xlIENocm9tZSIsICJQ
dVRUWSIsICJXaW5TQ1AiLCAiVk13YXJlIFRvb2xzIikNCiAgICB9DQopDQoNCg0KaWYgKCRBcHBOYW1lcy5Db3VudCAtZ3QgMCkg
ew0KDQogICAgSW5zdGFsbC1CYXNpY0FwcGxpY2F0aW9ucyAtQXJjaGl0ZWN0dXJlICRBcmNoaXRlY3R1cmUgLU5hbWVzICRBcHBO
YW1lcw0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJHaXQiKSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIEludm9r
ZS1CaW5TY3JpcHQgLU5hbWUgIkdpdCINCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52
b2NhdGlvbkluZm8uU2NyaXB0TGluZU51bWJlcg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJHaXQgKGxpbmVhICR7RmFp
bExpbmV9KTogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJN
b2JhWHRlcm0iKSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIEludm9rZS1CaW5TY3JpcHQgLU5hbWUgIk1vYmFYdGVybSINCg0K
ICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgJEZhaWxMaW5lID0gJF8uSW52b2NhdGlvbkluZm8uU2NyaXB0TGluZU51bWJl
cg0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJNb2JhWHRlcm0gKGxpbmVhICR7RmFpbExpbmV9KTogJCgkXy5FeGNlcHRp
b24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJDYWxjIikgew0KDQogICAgdHJ5IHsN
Cg0KICAgICAgICBJbnZva2UtQmluU2NyaXB0IC1OYW1lICJDYWxjIg0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAk
RmFpbExpbmUgPSAkXy5JbnZvY2F0aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUg
IkNhbGN1bGFkb3JhIChsaW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQpp
ZiAoJFNlbGVjdGVkIC1jb250YWlucyAiT2ZmaWNlIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBJbnN0YWxsLU9mZmljZTIw
MjRMdHNjIC1BcmNoaXRlY3R1cmUgJEFyY2hpdGVjdHVyZQ0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExp
bmUgPSAkXy5JbnZvY2F0aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIk9mZmlj
ZSAyMDI0IExUU0MgKGxpbmVhICR7RmFpbExpbmV9KTogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCmlm
ICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJQb3dlclNoZWxsIikgew0KDQogICAgdHJ5IHsNCg0KICAgICAgICBXcml0ZS1Mb2cgIkVq
ZWN1dGFuZG8gQ29ycmVyIFBvd2Vyc2hlbGwuIg0KDQogICAgICAgIFtOZXQuU2VydmljZVBvaW50TWFuYWdlcl06OlNlY3VyaXR5
UHJvdG9jb2wgPSBbTmV0LlNlY3VyaXR5UHJvdG9jb2xUeXBlXTo6VGxzMTINCg0KICAgICAgICAkUG93ZXJTaGVsbFNjcmlwdCA9
IEludm9rZS1SZXN0TWV0aG9kIGANCiAgICAgICAgICAgIC1VcmkgImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS9l
bWlqdW5rZS93aW5iYXNpYy9tYWluL3BzLnBzMSIgYA0KICAgICAgICAgICAgLVVzZUJhc2ljUGFyc2luZw0KDQogICAgICAgIGlm
ICgkUG93ZXJTaGVsbFNjcmlwdCAtaXMgW1N5c3RlbS5BcnJheV0pIHsNCg0KICAgICAgICAgICAgJFBvd2VyU2hlbGxTY3JpcHQg
PSAkUG93ZXJTaGVsbFNjcmlwdCAtam9pbiAiYG4iDQogICAgICAgIH0NCiAgICAgICAgZWxzZWlmICgkUG93ZXJTaGVsbFNjcmlw
dCAtaXNub3QgW3N0cmluZ10pIHsNCg0KICAgICAgICAgICAgJFBvd2VyU2hlbGxTY3JpcHQgPSBbc3RyaW5nXSRQb3dlclNoZWxs
U2NyaXB0DQogICAgICAgIH0NCg0KDQogICAgICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRQb3dlclNoZWxs
U2NyaXB0KSkgew0KDQogICAgICAgICAgICB0aHJvdyAicHMucHMxIGxsZWdvIHZhY2lvLiINCiAgICAgICAgfQ0KDQoNCiAgICAg
ICAgaWYgKCRQb3dlclNoZWxsU2NyaXB0LkNvbnRhaW5zKCJsaW5lcyBjb2xsYXBzZWQiKSkgew0KDQogICAgICAgICAgICB0aHJv
dyAicHMucHMxIG5vIHNlIHB1ZWRlIGVqZWN1dGFyOiBlbCBhcmNoaXZvIHN1YmlkbyBlc3RhIGNvbGFwc2Fkby4iDQogICAgICAg
IH0NCg0KDQogICAgICAgIEludm9rZS1FeHByZXNzaW9uICRQb3dlclNoZWxsU2NyaXB0DQoNCiAgICAgICAgV3JpdGUtTG9nICJD
b3JyZXIgUG93ZXJzaGVsbCB0ZXJtaW5vLiIgIk9LIg0KDQogICAgfQ0KICAgIGNhdGNoIHsNCg0KICAgICAgICAkRmFpbExpbmUg
PSAkXy5JbnZvY2F0aW9uSW5mby5TY3JpcHRMaW5lTnVtYmVyDQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkNvcnJlciBQ
b3dlcnNoZWxsIChsaW5lYSAke0ZhaWxMaW5lfSk6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgIH0NCn0NCg0KDQppZiAo
JFNlbGVjdGVkIC1jb250YWlucyAiRmlyZXdhbGwiKSB7DQoNCiAgICB0cnkgew0KDQogICAgICAgIERpc2FibGUtV2luZG93c0Zp
cmV3YWxsUGVybWFuZW50bHkNCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkZpcmV3
YWxsOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KaWYgKCRTZWxlY3RlZCAtY29udGFpbnMgIlJkcCIp
IHsNCg0KICAgIHRyeSB7DQoNCiAgICAgICAgRW5hYmxlLVJlbW90ZURlc2t0b3BXaXRob3V0TmxhDQoNCiAgICB9DQogICAgY2F0
Y2ggew0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJlICJFc2NyaXRvcmlvIHJlbW90bzogJCgkXy5FeGNlcHRpb24uTWVzc2Fn
ZSkiDQogICAgfQ0KfQ0KDQoNCmlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJJUHY2Iikgew0KDQogICAgdHJ5IHsNCg0KICAgICAg
ICBEaXNhYmxlLUlQdjZDb21wbGV0ZWx5DQoNCiAgICB9DQogICAgY2F0Y2ggew0KDQogICAgICAgIEFkZC1EZXBsb3lGYWlsdXJl
ICJJUHY2OiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSINCiAgICB9DQp9DQoNCg0KJFNjcmlwdDpIaWRlU2VhcmNoID0gJFNlbGVj
dGVkIC1jb250YWlucyAiU2VhcmNoIg0KDQokU2NyaXB0OkFsaWduTGVmdCA9ICRTZWxlY3RlZCAtY29udGFpbnMgIlRhc2tiYXIi
DQoNCg0KaWYgKCRTY3JpcHQ6SGlkZVNlYXJjaCAtb3IgJFNjcmlwdDpBbGlnbkxlZnQpIHsNCg0KICAgIHRyeSB7DQoNCiAgICAg
ICAgU2V0LVRhc2tiYXJMYXlvdXQNCg0KICAgIH0NCiAgICBjYXRjaCB7DQoNCiAgICAgICAgQWRkLURlcGxveUZhaWx1cmUgIkJh
cnJhIGRlIHRhcmVhczogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiDQogICAgfQ0KfQ0KDQoNCkdldC1DaGlsZEl0ZW0gLUxpdGVy
YWxQYXRoICRUZW1wRGlyIC1GaWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIHwNCiAgICBSZW1vdmUtSXRlbSAtRm9y
Y2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUNCg0KDQpXcml0ZS1Ib3N0ICIiDQpXcml0ZS1Ib3N0ICI9PT09PT09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iDQpXcml0ZS1Ib3N0ICIgUkVTVUxUQURP
Ig0KV3JpdGUtSG9zdCAiPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09
Ig0KV3JpdGUtSG9zdCAiIg0KV3JpdGUtSG9zdCAiTG9nOiAkTG9nRmlsZSINCldyaXRlLUhvc3QgIiINCg0KDQppZiAoJFNjcmlw
dDpGYWlsdXJlcy5Db3VudCAtZXEgMCkgew0KDQogICAgaWYgKCRBcHBOYW1lcy5Db3VudCAtZ3QgMCkgew0KDQogICAgICAgIFdy
aXRlLUhvc3QgIlByb2dyYW1hcyBlbGVnaWRvcyAgICAgICAgICAgICAgIDogSU5TVEFMQURPUyBPIFlBIFBSRVNFTlRFUyINCiAg
ICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJBbnlEZXNrIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkFu
eURlc2sgICAgICAgICAgICAgICAgICAgICAgICAgOiBJTlNUQUxBRE8iDQoNCiAgICAgICAgaWYgKCRTY3JpcHQ6TmV3SUQpIHsN
Cg0KICAgICAgICAgICAgV3JpdGUtSG9zdCAiQW55RGVzayBJRCAgICAgICAgICAgICAgICAgICAgICA6ICRTY3JpcHQ6TmV3SUQi
DQogICAgICAgIH0NCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJBbnlkZXNrVW5pbnN0YWxsIikgew0K
DQogICAgICAgIFdyaXRlLUhvc3QgIkFueWRlc2sgVW5pbnN0YWxsICAgICAgICAgICAgICAgOiBFSkVDVVRBRE8iDQogICAgfQ0K
DQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiR2l0Iikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkdpdCAgICAgICAg
ICAgICAgICAgICAgICAgICAgICAgOiBJTlNUQUxBRE8gTyBZQSBQUkVTRU5URSINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0
ZWQgLWNvbnRhaW5zICJNb2JhWHRlcm0iKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiTW9iYVh0ZXJtICAgICAgICAgICAgICAg
ICAgICAgICA6IENPUElBRE8iDQogICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiQ2FsYyIpIHsNCg0KICAg
ICAgICBXcml0ZS1Ib3N0ICJDYWxjdWxhZG9yYSAgICAgICAgICAgICAgICAgICAgIDogQUJJRVJUQSINCiAgICB9DQoNCg0KICAg
IGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJPZmZpY2UiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiT2ZmaWNlIDIwMjQgTFRT
QyAgICAgICAgICAgICAgICA6IElOU1RBTEFETyINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJQb3dl
clNoZWxsIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkNvcnJlciBQb3dlcnNoZWxsICAgICAgICAgICAgICAgOiBFSkVDVVRB
RE8iDQogICAgfQ0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250YWlucyAiRmlyZXdhbGwiKSB7DQoNCiAgICAgICAgV3JpdGUt
SG9zdCAiRmlyZXdhbGwgZGUgV2luZG93cyAgICAgICAgICAgICA6IERFU0hBQklMSVRBRE8iDQogICAgfQ0KDQoNCiAgICBpZiAo
JFNlbGVjdGVkIC1jb250YWlucyAiUmRwIikgew0KDQogICAgICAgIFdyaXRlLUhvc3QgIkVzY3JpdG9yaW8gcmVtb3RvICAgICAg
ICAgICAgICAgOiBIQUJJTElUQURPIg0KICAgICAgICBXcml0ZS1Ib3N0ICJBdXRlbnRpY2FjaW9uIGEgbml2ZWwgZGUgcmVkICAg
IDogREVTTUFSQ0FEQSINCiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJJUHY2Iikgew0KDQogICAgICAg
IFdyaXRlLUhvc3QgIklQdjYgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBERVNIQUJJTElUQURPIEFMIFJFSU5JQ0lBUiIN
CiAgICB9DQoNCg0KICAgIGlmICgkU2VsZWN0ZWQgLWNvbnRhaW5zICJTZWFyY2giKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAi
QnVzcXVlZGEgZW4gbGEgYmFycmEgZGUgdGFyZWFzIDogT0NVTFRBIg0KICAgIH0NCg0KDQogICAgaWYgKCRTZWxlY3RlZCAtY29u
dGFpbnMgIlRhc2tiYXIiKSB7DQoNCiAgICAgICAgV3JpdGUtSG9zdCAiQWxpbmVhY2lvbiBkZSBsYSBiYXJyYSAgICAgICAgIDog
SVpRVUlFUkRBIg0KICAgIH0NCg0KDQogICAgV3JpdGUtSG9zdCAiIg0KICAgIFdyaXRlLUhvc3QgIkNVU1RPTVdJTiBGSU5BTEla
QURPIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuDQogICAgV3JpdGUtSG9zdCAiIg0KDQoNCiAgICBpZiAoJFNlbGVjdGVkIC1jb250
YWlucyAiSVB2NiIpIHsNCg0KICAgICAgICBXcml0ZS1Ib3N0ICJSZWluaWNpZSBlbCBlcXVpcG8gcGFyYSBjb21wbGV0YXIgbGEg
ZGVzaGFiaWxpdGFjaW9uIGRlIElQdjYuIg0KICAgICAgICBXcml0ZS1Ib3N0ICIiDQogICAgfQ0KDQoNCiAgICBXcml0ZS1Mb2cg
IkN1c3RvbVdpbiBmaW5hbGl6YWRvLiIgIk9LIg0KDQogICAgU3RvcC1DdXN0b21XaW4gLUNvZGUgMA0KfQ0KDQoNCldyaXRlLUhv
c3QgIkNVU1RPTVdJTiBGSU5BTElaQURPIENPTiBFUlJPUkVTIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdw0KDQpXcml0ZS1Ib3N0
ICIiDQoNCmZvcmVhY2ggKCRGYWlsdXJlIGluICRTY3JpcHQ6RmFpbHVyZXMpIHsNCg0KICAgIFdyaXRlLUhvc3QgIiAtICRGYWls
dXJlIg0KfQ0KDQpXcml0ZS1Ib3N0ICIiDQpXcml0ZS1Ib3N0ICJSZXZpc2U6ICRMb2dGaWxlIg0KV3JpdGUtSG9zdCAiIg0KDQpX
cml0ZS1Mb2cgIkN1c3RvbVdpbiBmaW5hbGl6YWRvIGNvbiBlcnJvcmVzLiIgIldBUk4iDQoNClN0b3AtQ3VzdG9tV2luIC1Db2Rl
IDENCg0KDQojIEZpbiBkZWwgc2NyaXB0Lg0K
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

    Write-Log "Revision: 20261026a"

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
