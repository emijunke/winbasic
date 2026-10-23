# Copia portable de MobaXterm.
# CustomWin lo ejecuta cuando se tilda MobaXterm.
# Baja el contenido de emijunke/winbasic/mobaxterm a C:\MobaXterm
# y crea el acceso directo en el escritorio de todos los usuarios.
# No lleva directiva de version ni parametros de script: tiene que funcionar con irm | iex.

$ProgressPreference = "SilentlyContinue"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


function Write-MobaLog {

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



function Test-MobaAdministrator {

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}



function Save-MobaXtermFolder {

    param (
        [Parameter(Mandatory = $true)]
        [string]$DestDir
    )


    $Api = "https://api.github.com/repos/emijunke/winbasic/git/trees/main?recursive=1"

    Write-MobaLog "Leyendo la lista de archivos de mobaxterm."


    $Page = Invoke-WebRequest `
        -Uri $Api `
        -Headers @{ "User-Agent" = "Install-Win-Basic" } `
        -UseBasicParsing


    $Pattern = '"path":"(mobaxterm/[^"]+)","mode":"[^"]+","type":"blob","sha":"[^"]+","size":(\d+)'

    $Found = [regex]::Matches([string]$Page.Content, $Pattern)


    if ($Found.Count -eq 0) {

        throw "No se encontraron archivos en la carpeta mobaxterm del repositorio."
    }


    Write-MobaLog ("Archivos a copiar: {0}" -f $Found.Count)


    if (-not (Test-Path -LiteralPath $DestDir)) {

        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }


    foreach ($Match in $Found) {

        $RepoFile = [string]$Match.Groups[1].Value

        $Expected = [int64]$Match.Groups[2].Value

        $Relative = $RepoFile.Substring("mobaxterm/".Length)

        $Parts = @($Relative -split "[\\/]")


        if (
            [string]::IsNullOrWhiteSpace($Relative) -or
            $Relative.StartsWith("/") -or
            $Relative.StartsWith("\") -or
            $Parts -contains ".." -or
            $Parts -contains "."
        ) {

            throw "Ruta no valida: $RepoFile"
        }


        $Target = Join-Path $DestDir ($Relative -replace "/", "\")

        $Parent = Split-Path -Parent $Target


        if (-not (Test-Path -LiteralPath $Parent)) {

            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }


        $Url = "https://raw.githubusercontent.com/emijunke/winbasic/main/$RepoFile"


        if ((Test-Path -LiteralPath $Target) -and $Expected -gt 0) {

            $Current = (Get-Item -LiteralPath $Target).Length


            if ($Current -eq $Expected) {

                Write-MobaLog "$Relative ya esta en $Target. Se omite." "OK"

                continue
            }
        }


        Write-MobaLog "Descargando $Relative..."

        Write-MobaLog "Origen: $Url"


        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $Target `
            -UseBasicParsing


        if (-not (Test-Path -LiteralPath $Target)) {

            throw "No se encontro $Relative despues de descargarlo."
        }


        $Size = (Get-Item -LiteralPath $Target).Length


        if ($Expected -gt 0 -and $Size -ne $Expected) {

            throw "$Relative quedo incompleto. Esperado: $Expected bytes. Recibido: $Size bytes."
        }


        Write-MobaLog ("{0} copiado. Tamano: {1:N1} MB" -f $Relative, ($Size / 1MB)) "OK"
    }
}



function New-MobaXtermShortcut {

    param (
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )


    $Desktop = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::CommonDesktopDirectory
    )


    if ([string]::IsNullOrWhiteSpace($Desktop)) {

        $Desktop = Join-Path $env:PUBLIC "Desktop"
    }


    if (-not (Test-Path -LiteralPath $Desktop)) {

        New-Item -ItemType Directory -Path $Desktop -Force | Out-Null
    }


    $LinkPath = Join-Path $Desktop "MobaXterm.lnk"

    $Shell = New-Object -ComObject WScript.Shell

    $Shortcut = $Shell.CreateShortcut($LinkPath)

    $Shortcut.TargetPath = $ExePath

    $Shortcut.WorkingDirectory = "C:\MobaXterm"

    $Shortcut.Description = "MobaXterm"

    $Shortcut.IconLocation = "$ExePath,0"

    $Shortcut.Save()


    if (-not (Test-Path -LiteralPath $LinkPath)) {

        throw "No se pudo crear el acceso directo en $LinkPath."
    }


    Write-MobaLog "Acceso directo creado para todos los usuarios: $LinkPath" "OK"
}



function Install-MobaXtermPortable {

    Write-MobaLog "Revision MobaXterm: 20261023b"


    if (-not (Test-MobaAdministrator)) {

        throw "PowerShell no esta ejecutandose como Administrador."
    }


    $DestRoot = "C:\MobaXterm"

    Write-MobaLog "Copiando MobaXterm a $DestRoot."

    Save-MobaXtermFolder -DestDir $DestRoot


    $ExePath = Join-Path $DestRoot "MobaXterm.exe"


    if (-not (Test-Path -LiteralPath $ExePath)) {

        throw "No se encontro MobaXterm.exe en $DestRoot."
    }


    New-MobaXtermShortcut -ExePath $ExePath

    Write-MobaLog "MobaXterm listo en $DestRoot." "OK"
}



Install-MobaXtermPortable

# Fin del script.
