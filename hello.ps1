Write-Host "Hello from my script!"
Get-ComputerInfo | Select-Object CsName, OsName, OsVersion
