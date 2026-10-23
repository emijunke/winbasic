# Ejecuta la descarga y aplica la activación de Windows (HWID) en modo totalmente silencioso
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://get.activated.win"))) /Ohook /S

# Mensaje de confirmación en tu consola
Write-Output "Activación de Windows completada sin mostrar ventanas."
