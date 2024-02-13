<#
.SYNOPSIS
    Launches the main watch script.

.DESCRIPTION
    This script is used to launch the accompanying "watch.ps1" script in a new powershell window. 
    This is necessary to persist FileSystemWatcher, I don't know why.
#>

$Host.UI.RawUI.WindowTitle = "Powershell Watch & Copy Launcher"

$scriptPath = Join-Path $PSScriptRoot "watch.ps1"
$windowsPowerShell = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("System"), "WindowsPowerShell", "v1.0", "powershell.exe")
Start-Process $windowsPowerShell -ArgumentList "-NoLogo -ExecutionPolicy Bypass -File `"$scriptPath`""

