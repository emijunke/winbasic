# Menu de CustomWin.
# Lo llama CustomWin.ps1. No hace falta ejecutarlo solo.
# Aca estan los nombres, la ventana y la invocacion de cada opcion.
# No lleva directiva de version ni parametros de script: tiene que
# funcionar cuando CustomWin lo ejecuta con irm | iex.

# ============================================================
# Nombres que aparecen en la ventana.
# Cambie solo el texto entre comillas.
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


        if ([string]::IsNullOrWhiteSpace($Answer)) {

            $Picked = @(
                $Choices |
                    Where-Object { $Checked[$_.Id] } |
                    ForEach-Object { $_.Id }
            )


            if ($Picked.Count -eq 0) {

                Write-Host "Tilda al menos una opcion."

                continue
            }


            return ,$Picked
        }


        if ($Answer -eq "Q" -or $Answer -eq "q") {

            return $null
        }


        if ($Answer -eq "A" -or $Answer -eq "a") {

            foreach ($Choice in $Choices) {

                $Checked[$Choice.Id] = $true
            }

            continue
        }


        if ($Answer -eq "N" -or $Answer -eq "n") {

            foreach ($Choice in $Choices) {

                $Checked[$Choice.Id] = $false
            }

            continue
        }


        $Number = 0


        if (
            [int]::TryParse($Answer, [ref]$Number) -and
            $Number -ge 1 -and
            $Number -le $Choices.Count
        ) {

            $Id = $Choices[$Number - 1].Id

            $Checked[$Id] = -not $Checked[$Id]
        }
    }
}



function Show-CustomWinForm {

    if (-not ("CustomWin.CustomWinWindow" -as [type])) {

        Add-Type -Namespace CustomWin -Name CustomWinWindow -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool BringWindowToTop(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, System.IntPtr ProcessId);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint GetCurrentThreadId();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
"@
    }


    $Choices = @(Get-CustomWinChoices)

    $Canvas = [System.Drawing.Color]::FromArgb(244, 246, 248)

    $Ink = [System.Drawing.Color]::FromArgb(15, 23, 42)

    $Muted = [System.Drawing.Color]::FromArgb(71, 85, 105)

    $Accent = [System.Drawing.Color]::FromArgb(37, 99, 235)

    $AccentDark = [System.Drawing.Color]::FromArgb(29, 78, 216)

    $Line = [System.Drawing.Color]::FromArgb(226, 232, 240)

    $Card = [System.Drawing.Color]::White


    $Form = New-Object System.Windows.Forms.Form

    $Form.Text = "CustomWin"

    $Form.StartPosition = "Manual"

    $Form.FormBorderStyle = "None"

    $Form.WindowState = "Normal"

    $Form.KeyPreview = $true

    $Form.ShowInTaskbar = $true

    $ScreenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    $Form.Bounds = $ScreenBounds

    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $Form.BackColor = $Canvas

    $Form.ForeColor = $Ink

    $Form.TopMost = $true


    $Header = New-Object System.Windows.Forms.Panel

    $Header.Location = New-Object System.Drawing.Point(0, 0)

    $Header.Size = New-Object System.Drawing.Size(700, 108)

    $Header.BackColor = $Accent

    $Form.Controls.Add($Header)


    $Title = New-Object System.Windows.Forms.Label

    $Title.Text = "Elegi que queres aplicar"

    $Title.AutoSize = $false

    $Title.Size = New-Object System.Drawing.Size(640, 36)

    $Title.Font = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)

    $Title.ForeColor = [System.Drawing.Color]::White

    $Title.BackColor = $Accent

    $Title.Location = New-Object System.Drawing.Point(28, 26)

    $Header.Controls.Add($Title)


    $Hint = New-Object System.Windows.Forms.Label

    $Hint.Text = "Nada empieza tildado. Marca lo que queres aplicar. Lo demas no se modifica."

    $Hint.AutoSize = $false

    $Hint.Size = New-Object System.Drawing.Size(640, 24)

    $Hint.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $Hint.ForeColor = [System.Drawing.Color]::FromArgb(219, 234, 254)

    $Hint.BackColor = $Accent

    $Hint.Location = New-Object System.Drawing.Point(28, 66)

    $Header.Controls.Add($Hint)


    $ListCard = New-Object System.Windows.Forms.Panel

    $ListCard.Location = New-Object System.Drawing.Point(24, 128)

    $ListCard.Size = New-Object System.Drawing.Size(652, 452)

    $ListCard.BackColor = $Line

    $Form.Controls.Add($ListCard)


    $List = New-Object System.Windows.Forms.CheckedListBox

    $List.Location = New-Object System.Drawing.Point(1, 1)

    $List.Size = New-Object System.Drawing.Size(650, 450)

    $List.CheckOnClick = $true

    $List.BorderStyle = "None"

    $List.IntegralHeight = $false

    $List.DrawMode = "OwnerDrawFixed"

    $List.ItemHeight = 44

    $List.Font = New-Object System.Drawing.Font("Segoe UI", 11)

    $List.BackColor = $Card

    $List.ForeColor = $Ink

    $script:CustomWinHoverIndex = -1


    $List.Add_DrawItem({

        param($sender, $e)

        if ($e.Index -lt 0) { return }

        $Graphics = $e.Graphics

        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $Bounds = $e.Bounds

        $IsChecked = $List.GetItemChecked($e.Index)

        $IsHot = $e.Index -eq $script:CustomWinHoverIndex

        $Back = [System.Drawing.Color]::White

        if ($IsChecked) {

            $Back = [System.Drawing.Color]::FromArgb(239, 246, 255)

        }
        elseif ($IsHot) {

            $Back = [System.Drawing.Color]::FromArgb(248, 250, 252)
        }

        $BackBrush = New-Object System.Drawing.SolidBrush $Back

        $Graphics.FillRectangle($BackBrush, $Bounds)

        $BackBrush.Dispose()

        $BoxTop = $Bounds.Y + [int](($Bounds.Height - 18) / 2)

        $Box = New-Object System.Drawing.Rectangle(($Bounds.X + 22), $BoxTop, 18, 18)

        $Blue = [System.Drawing.Color]::FromArgb(37, 99, 235)

        if ($IsChecked) {

            $Fill = New-Object System.Drawing.SolidBrush $Blue

            $Graphics.FillRectangle($Fill, $Box)

            $Fill.Dispose()

            $MarkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2

            $Points = New-Object 'System.Drawing.Point[]' 3

            $Points[0] = New-Object System.Drawing.Point (($Box.X + 4), ($Box.Y + 9))

            $Points[1] = New-Object System.Drawing.Point (($Box.X + 8), ($Box.Y + 13))

            $Points[2] = New-Object System.Drawing.Point (($Box.X + 14), ($Box.Y + 5))

            $Graphics.DrawLines($MarkPen, $Points)

            $MarkPen.Dispose()

        }
        else {

            $BoxPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(148, 163, 184))

            $Graphics.DrawRectangle($BoxPen, $Box)

            $BoxPen.Dispose()
        }

        $TextBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(15, 23, 42))

        $TextRect = New-Object System.Drawing.Rectangle(($Bounds.X + 48), $Bounds.Y, ($Bounds.Width - 60), $Bounds.Height)

        $Format = New-Object System.Drawing.StringFormat

        $Format.LineAlignment = [System.Drawing.StringAlignment]::Center

        $Format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter

        $Format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

        $Graphics.DrawString([string]$List.Items[$e.Index], $e.Font, $TextBrush, $TextRect, $Format)

        $TextBrush.Dispose()

        $Format.Dispose()

    }.GetNewClosure())

    $List.Add_MouseMove({

        param($sender, $e)

        $Index = $List.IndexFromPoint($e.Location)

        if ($Index -ne $script:CustomWinHoverIndex) {

            $script:CustomWinHoverIndex = $Index

            $List.Invalidate()
        }

    }.GetNewClosure())

    $List.Add_MouseLeave({

        $script:CustomWinHoverIndex = -1

        $List.Invalidate()

    }.GetNewClosure())


    foreach ($Choice in $Choices) {

        [void]$List.Items.Add($Choice.Text, $false)
    }


    $ListCard.Controls.Add($List)


    $Notice = New-Object System.Windows.Forms.Label

    $Notice.Text = ""

    $Notice.AutoSize = $false

    $Notice.Size = New-Object System.Drawing.Size(640, 20)

    $Notice.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $Notice.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)

    $Notice.BackColor = $Canvas

    $Notice.Location = New-Object System.Drawing.Point(24, 588)

    $Form.Controls.Add($Notice)


    $List.Add_SelectedIndexChanged({

        $Notice.Text = ""

    }.GetNewClosure())


    function Set-CustomWinFlatButton {

        param(
            $Button,
            [bool]$Primary
        )

        $Button.FlatStyle = "Flat"

        $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

        $Button.Font = New-Object System.Drawing.Font("Segoe UI", 10)

        if ($Primary) {

            $Button.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)

            $Button.ForeColor = [System.Drawing.Color]::White

            $Button.FlatAppearance.BorderSize = 0

            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)

            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(30, 64, 175)

            return
        }

        $Button.BackColor = [System.Drawing.Color]::White

        $Button.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)

        $Button.FlatAppearance.BorderSize = 1

        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(203, 213, 225)

        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)

        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    }


    $MarkAll = New-Object System.Windows.Forms.Button

    $MarkAll.Text = "Marcar todo"

    $MarkAll.Location = New-Object System.Drawing.Point(24, 616)

    $MarkAll.Size = New-Object System.Drawing.Size(132, 40)

    Set-CustomWinFlatButton -Button $MarkAll -Primary $false

    $MarkAll.Add_Click({

        for ($Index = 0; $Index -lt $List.Items.Count; $Index++) {

            $List.SetItemChecked($Index, $true)
        }

        $Notice.Text = ""

    }.GetNewClosure())

    $Form.Controls.Add($MarkAll)


    $ClearAll = New-Object System.Windows.Forms.Button

    $ClearAll.Text = "Desmarcar todo"

    $ClearAll.Location = New-Object System.Drawing.Point(164, 616)

    $ClearAll.Size = New-Object System.Drawing.Size(148, 40)

    Set-CustomWinFlatButton -Button $ClearAll -Primary $false

    $ClearAll.Add_Click({

        for ($Index = 0; $Index -lt $List.Items.Count; $Index++) {

            $List.SetItemChecked($Index, $false)
        }

        $Notice.Text = ""

    }.GetNewClosure())

    $Form.Controls.Add($ClearAll)


    $Cancel = New-Object System.Windows.Forms.Button

    $Cancel.Text = "Cancelar"

    $Cancel.Location = New-Object System.Drawing.Point(404, 616)

    $Cancel.Size = New-Object System.Drawing.Size(120, 40)

    $Cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    Set-CustomWinFlatButton -Button $Cancel -Primary $false

    $Form.CancelButton = $Cancel

    $Form.Controls.Add($Cancel)


    $Apply = New-Object System.Windows.Forms.Button

    $Apply.Text = "Aplicar"

    $Apply.Location = New-Object System.Drawing.Point(536, 616)

    $Apply.Size = New-Object System.Drawing.Size(140, 40)

    Set-CustomWinFlatButton -Button $Apply -Primary $true

    $Apply.Add_Click({

        $AnyChecked = $false


        for ($Index = 0; $Index -lt $List.Items.Count; $Index++) {

            if ($List.GetItemChecked($Index)) {

                $AnyChecked = $true
            }
        }


        if (-not $AnyChecked) {

            $Notice.Text = "Tilda al menos una opcion."

            return
        }


        $Form.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $Form.Close()

    }.GetNewClosure())

    $Form.Controls.Add($Apply)

    $Form.AcceptButton = $Apply


    $UpdateLayout = {

        $Width = $Form.ClientSize.Width

        $Height = $Form.ClientSize.Height


        if ($Width -lt 640 -or $Height -lt 480) {

            return
        }


        $HeaderHeight = 148

        $Header.SetBounds(0, 0, $Width, $HeaderHeight)


        $ContentWidth = $Width - 120


        if ($ContentWidth -gt 1080) {

            $ContentWidth = 1080
        }


        $Left = [int](($Width - $ContentWidth) / 2)

        $Title.SetBounds($Left, 40, $ContentWidth, 48)

        $Hint.SetBounds($Left, 96, $ContentWidth, 28)


        $ButtonTop = $Height - 88

        $NoticeTop = $ButtonTop - 32

        $ListTop = $HeaderHeight + 28

        $ListHeight = $NoticeTop - $ListTop - 16


        if ($ListHeight -lt 160) {

            $ListHeight = 160
        }


        $ListCard.SetBounds($Left, $ListTop, $ContentWidth, $ListHeight)

        $List.SetBounds(1, 1, ($ContentWidth - 2), ($ListHeight - 2))

        $Notice.SetBounds($Left, $NoticeTop, $ContentWidth, 24)


        $MarkAll.SetBounds($Left, $ButtonTop, 160, 52)

        $ClearAll.SetBounds(($Left + 176), $ButtonTop, 180, 52)

        $Apply.SetBounds(($Left + $ContentWidth - 180), $ButtonTop, 180, 52)

        $Cancel.SetBounds(($Left + $ContentWidth - 180 - 16 - 150), $ButtonTop, 150, 52)
    }.GetNewClosure()


    & $UpdateLayout


    $Form.Add_Shown({

        $Form.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

        $Form.WindowState = "Normal"

        & $UpdateLayout

        $Handle = $Form.Handle

        $Flags = [uint32](0x0001 -bor 0x0002 -bor 0x0040)

        [void][CustomWin.CustomWinWindow]::SetWindowPos(
            $Handle,
            [IntPtr](-1),
            0,
            0,
            0,
            0,
            $Flags
        )

        $Foreground = [CustomWin.CustomWinWindow]::GetForegroundWindow()

        $ForegroundThread = [CustomWin.CustomWinWindow]::GetWindowThreadProcessId(
            $Foreground,
            [IntPtr]::Zero
        )

        $CurrentThread = [CustomWin.CustomWinWindow]::GetCurrentThreadId()


        if ($ForegroundThread -ne $CurrentThread) {

            [void][CustomWin.CustomWinWindow]::AttachThreadInput(
                $ForegroundThread,
                $CurrentThread,
                $true
            )
        }


        [void][CustomWin.CustomWinWindow]::BringWindowToTop($Handle)

        [void][CustomWin.CustomWinWindow]::SetForegroundWindow($Handle)


        if ($ForegroundThread -ne $CurrentThread) {

            [void][CustomWin.CustomWinWindow]::AttachThreadInput(
                $ForegroundThread,
                $CurrentThread,
                $false
            )
        }


        $Form.TopMost = $true

        $Form.Activate()

    }.GetNewClosure())


    $Form.TopMost = $true

    $Result = $Form.ShowDialog()

    $Picked = New-Object System.Collections.Generic.List[string]


    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {

        for ($Index = 0; $Index -lt $Choices.Count; $Index++) {

            if ($List.GetItemChecked($Index)) {

                $Picked.Add($Choices[$Index].Id)
            }
        }
    }


    $Form.Dispose()


    if ($Result -ne [System.Windows.Forms.DialogResult]::OK -or $Picked.Count -eq 0) {

        return $null
    }


    return ,$Picked.ToArray()
}



function Read-CustomWinSelection {

    $Apartment = [Threading.Thread]::CurrentThread.ApartmentState


    if ("$Apartment" -eq "STA") {

        try {

            Add-Type -AssemblyName System.Windows.Forms

            Add-Type -AssemblyName System.Drawing

            [System.Windows.Forms.Application]::EnableVisualStyles()

            $Picked = Show-CustomWinForm


            if ($null -eq $Picked) {

                return $null
            }


            return ,$Picked
        }
        catch {

            Write-Log "No se pudo abrir la ventana de seleccion: $($_.Exception.Message)" "WARN"
        }
    }


    $Picked = Show-CustomWinConsole


    if ($null -eq $Picked) {

        return $null
    }


    return ,$Picked
}


Write-Log "Menu: 20261023h"


$Selected = Read-CustomWinSelection


if ($null -eq $Selected) {

    Write-Host ""
    Write-Host "Cancelado. No se modifico nada."
    Write-Host ""

    Write-Log "El usuario cancelo la seleccion." "WARN"

    Stop-CustomWin -Code 0
}


$Selected = @($Selected)

Write-Log ("Opciones elegidas: " + ($Selected -join ", "))


$Architecture = Get-OsArchitecture

Write-Log "Arquitectura: $Architecture"


if ($Selected -contains "AnyDesk") {

    try {

        Install-UnattendedAnyDesk


        if ([int]$script:AnyDeskExitCode -ne 0) {

            Add-DeployFailure "AnyDesk: no se completo. Codigo $($script:AnyDeskExitCode)."
        }

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "AnyDesk (linea ${FailLine}): $($_.Exception.Message)"
    }
}


$AppNames = @(
    $Selected | Where-Object {
        $_ -in @("Notepad++", "7-Zip", "Firefox", "Google Chrome", "PuTTY", "WinSCP", "VMware Tools")
    }
)


if ($AppNames.Count -gt 0) {

    Install-BasicApplications -Architecture $Architecture -Names $AppNames
}


if ($Selected -contains "Git") {

    try {

        Invoke-BinScript -Name "Git"

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "Git (linea ${FailLine}): $($_.Exception.Message)"
    }
}


if ($Selected -contains "MobaXterm") {

    try {

        Invoke-BinScript -Name "MobaXterm"

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "MobaXterm (linea ${FailLine}): $($_.Exception.Message)"
    }
}


if ($Selected -contains "Calc") {

    try {

        Invoke-BinScript -Name "Calc"

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "Calculadora (linea ${FailLine}): $($_.Exception.Message)"
    }
}


if ($Selected -contains "Office") {

    try {

        Install-Office2024Ltsc -Architecture $Architecture

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "Office 2024 LTSC (linea ${FailLine}): $($_.Exception.Message)"
    }
}


if ($Selected -contains "PowerShell") {

    try {

        Write-Log "Ejecutando Correr Powershell."

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $PowerShellScript = Invoke-RestMethod `
            -Uri "https://raw.githubusercontent.com/emijunke/winbasic/main/ps.ps1" `
            -UseBasicParsing

        if ($PowerShellScript -is [System.Array]) {

            $PowerShellScript = $PowerShellScript -join "`n"
        }
        elseif ($PowerShellScript -isnot [string]) {

            $PowerShellScript = [string]$PowerShellScript
        }


        if ([string]::IsNullOrWhiteSpace($PowerShellScript)) {

            throw "ps.ps1 llego vacio."
        }


        if ($PowerShellScript.Contains("lines collapsed")) {

            throw "ps.ps1 no se puede ejecutar: el archivo subido esta colapsado."
        }


        Invoke-Expression $PowerShellScript

        Write-Log "Correr Powershell termino." "OK"

    }
    catch {

        $FailLine = $_.InvocationInfo.ScriptLineNumber

        Add-DeployFailure "Correr Powershell (linea ${FailLine}): $($_.Exception.Message)"
    }
}


if ($Selected -contains "Firewall") {

    try {

        Disable-WindowsFirewallPermanently

    }
    catch {

        Add-DeployFailure "Firewall: $($_.Exception.Message)"
    }
}


if ($Selected -contains "Rdp") {

    try {

        Enable-RemoteDesktopWithoutNla

    }
    catch {

        Add-DeployFailure "Escritorio remoto: $($_.Exception.Message)"
    }
}


if ($Selected -contains "IPv6") {

    try {

        Disable-IPv6Completely

    }
    catch {

        Add-DeployFailure "IPv6: $($_.Exception.Message)"
    }
}


$Script:HideSearch = $Selected -contains "Search"

$Script:AlignLeft = $Selected -contains "Taskbar"


if ($Script:HideSearch -or $Script:AlignLeft) {

    try {

        Set-TaskbarLayout

    }
    catch {

        Add-DeployFailure "Barra de tareas: $($_.Exception.Message)"
    }
}


Get-ChildItem -LiteralPath $TempDir -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue


Write-Host ""
Write-Host "============================================================"
Write-Host " RESULTADO"
Write-Host "============================================================"
Write-Host ""
Write-Host "Log: $LogFile"
Write-Host ""


if ($Script:Failures.Count -eq 0) {

    if ($AppNames.Count -gt 0) {

        Write-Host "Programas elegidos               : INSTALADOS O YA PRESENTES"
    }


    if ($Selected -contains "AnyDesk") {

        Write-Host "AnyDesk                         : INSTALADO"

        if ($Script:NewID) {

            Write-Host "AnyDesk ID                      : $Script:NewID"
        }
    }


    if ($Selected -contains "Git") {

        Write-Host "Git                             : INSTALADO O YA PRESENTE"
    }


    if ($Selected -contains "MobaXterm") {

        Write-Host "MobaXterm                       : COPIADO"
    }


    if ($Selected -contains "Calc") {

        Write-Host "Calculadora                     : ABIERTA"
    }


    if ($Selected -contains "Office") {

        Write-Host "Office 2024 LTSC                : INSTALADO"
    }


    if ($Selected -contains "PowerShell") {

        Write-Host "Correr Powershell               : EJECUTADO"
    }


    if ($Selected -contains "Firewall") {

        Write-Host "Firewall de Windows             : DESHABILITADO"
    }


    if ($Selected -contains "Rdp") {

        Write-Host "Escritorio remoto               : HABILITADO"
        Write-Host "Autenticacion a nivel de red    : DESMARCADA"
    }


    if ($Selected -contains "IPv6") {

        Write-Host "IPv6                            : DESHABILITADO AL REINICIAR"
    }


    if ($Selected -contains "Search") {

        Write-Host "Busqueda en la barra de tareas : OCULTA"
    }


    if ($Selected -contains "Taskbar") {

        Write-Host "Alineacion de la barra         : IZQUIERDA"
    }


    Write-Host ""
    Write-Host "CUSTOMWIN FINALIZADO" -ForegroundColor Green
    Write-Host ""


    if ($Selected -contains "IPv6") {

        Write-Host "Reinicie el equipo para completar la deshabilitacion de IPv6."
        Write-Host ""
    }


    Write-Log "CustomWin finalizado." "OK"

    Stop-CustomWin -Code 0
}


Write-Host "CUSTOMWIN FINALIZADO CON ERRORES" -ForegroundColor Yellow

Write-Host ""

foreach ($Failure in $Script:Failures) {

    Write-Host " - $Failure"
}

Write-Host ""
Write-Host "Revise: $LogFile"
Write-Host ""

Write-Log "CustomWin finalizado con errores." "WARN"

Stop-CustomWin -Code 1


# Fin del script.
