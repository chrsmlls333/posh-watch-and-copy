<#
.SYNOPSIS
    Launches the main watch script.

.DESCRIPTION
    This script is used to launch the accompanying "watch.ps1" script in a new powershell window. 
    This is necessary to persist FileSystemWatcher, I don't know why.
#>

$Host.UI.RawUI.WindowTitle = "Powershell Watch & Copy Launcher"

$scriptPath = Join-Path $PSScriptRoot "watch.ps1"
Start-Process powershell -ArgumentList "-NoLogo -ExecutionPolicy Bypass -File `"$scriptPath`""
