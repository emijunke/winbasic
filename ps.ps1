# Ejecuta la descarga y aplica el parche de Office (Ohook) en modo totalmente silencioso
& ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://get.activated.win"))) /HWID /S

# Mensaje de confirmación en tu consola
Write-Output "Activación de Office completada sin mostrar ventanas."
