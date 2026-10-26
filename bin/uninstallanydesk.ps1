# Anydesk Uninstall.
# CustomWin lo ejecuta cuando se tilda esa opcion.
# No lleva directiva de version ni parametros de script: tiene que funcionar con irm | iex.

$ProgressPreference = "SilentlyContinue"


function Write-AnydeskUninstallLog {

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



Write-AnydeskUninstallLog "Revision uninstallanydesk: 20261026a"

Write-AnydeskUninstallLog "Inicio de Anydesk Uninstall."

Write-AnydeskUninstallLog "Anydesk Uninstall todavia no tiene pasos de desinstalacion." "WARN"

# Fin del script.
