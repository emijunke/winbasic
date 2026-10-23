
[6 lines collapsed]

# ============================================================
# Nombres que aparecen en la ventana.
# Cambie solo el texto entre comillas.
# Para agregar una opcion: sume una variable, un Id en
# Get-CustomWinChoices y un bloque que la invoque mas abajo.
# No borre ni renombre las variables.
# Para agregar una opcion: sume una variable aca, un Id en
# Get-CustomWinChoices y, mas abajo, el bloque que la invoca.
# ============================================================
$Script:Item_Notepad = "Notepad++ (ultima version, se omite si ya esta)"
$Script:Item_7Zip = "7-Zip (ultima version, se omite si ya esta)"
$Script:Item_Firefox = "Firefox (ultima version, se omite si ya esta)"
$Script:Item_Chrome = "Google Chrome (ultima version, se omite si ya esta)"
$Script:Item_PuTTY = "PuTTY (ultima version, se omite si ya esta)"
$Script:Item_WinSCP = "WinSCP (ultima version, se omite si ya esta)"
$Script:Item_VMware = "VMware Tools (ultima version, se omite si ya esta)"
$Script:Item_Git = "Git (ultima version, se omite si ya esta)"
$Script:Item_MobaXterm = "MobaXterm"
$Script:Item_Calc = "Calculadora"
$Script:Item_Office = "Office 2024 LTSC Professional Plus, espanol, sin Skype Empresarial ni OneDrive"
$Script:Item_Powershell = "Office 2024 LTSC Professional Plus (Activacion)"
$Script:Item_AnyDesk = "AnyDesk oculto, con password de acceso desatendido"
$Script:Item_Firewall = "Deshabilitar el Firewall de Windows en todas las redes"
$Script:Item_EscritorioRemoto = "Habilitar Escritorio remoto sin autenticacion de nivel de red"
$Script:Item_IPv6 = "Deshabilitar IPv6 en todo el sistema"
$Script:Item_Busqueda = "Ocultar el campo de busqueda de la barra de tareas"
$Script:Item_BarraTareas = "Alinear los iconos de la barra de tareas a la izquierda"
function Get-CustomWinChoices {
    return @(
        @{
            Id = "Notepad++"
            Text = $Script:Item_Notepad
        },
        @{
            Id = "7-Zip"
            Text = $Script:Item_7Zip
        },
        @{
            Id = "Firefox"
            Text = $Script:Item_Firefox
        },
        @{
            Id = "Google Chrome"
            Text = $Script:Item_Chrome
        },
        @{
            Id = "PuTTY"
            Text = $Script:Item_PuTTY
        },
        @{
            Id = "WinSCP"
            Text = $Script:Item_WinSCP
        },
        @{
            Id = "VMware Tools"
            Text = $Script:Item_VMware
        },
        @{
            Id = "Git"
            Text = $Script:Item_Git
        },
        @{
            Id = "MobaXterm"
            Text = $Script:Item_MobaXterm
        },
        @{
            Id = "Calc"
            Text = $Script:Item_Calc
        },
        @{
            Id = "Office"
            Text = $Script:Item_Office
        },
        @{
            Id = "PowerShell"
            Text = $Script:Item_Powershell
        },
        @{
            Id = "AnyDesk"
            Text = $Script:Item_AnyDesk
        },
        @{
            Id = "Firewall"
            Text = $Script:Item_Firewall
        },
        @{
            Id = "Rdp"
            Text = $Script:Item_EscritorioRemoto
        },
        @{
            Id = "IPv6"
            Text = $Script:Item_IPv6
        },
        @{
            Id = "Search"
            Text = $Script:Item_Busqueda
        },
        @{
            Id = "Taskbar"
            Text = $Script:Item_BarraTareas
        }
    )
}
function Show-CustomWinConsole {
    $Choices = @(Get-CustomWinChoices)
    $Checked = @{}
    foreach ($Choice in $Choices) {
        $Checked[$Choice.Id] = $false
    }
    while ($true) {
        Write-Host ""
        Write-Host "Numero: tilda o destilda. A: todas. N: ninguna. Enter: aplicar. Q: cancelar."
        Write-Host ""
        for ($Index = 0; $Index -lt $Choices.Count; $Index++) {
            $Mark = " "
            if ($Checked[$Choices[$Index].Id]) {
                $Mark = "X"
            }
            Write-Host ("[{0}] {1}. {2}" -f $Mark, ($Index + 1), $Choices[$Index].Text)
        }
        $Answer = Read-Host "Opcion"
