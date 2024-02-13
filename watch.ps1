<#
.SYNOPSIS
    This script watches a specified directory for new files and copies them to another directory.

.DESCRIPTION
    The script sets up a FileSystemWatcher on a specified directory. When a new file is created in the watched directory, 
    the script copies the file to another directory and renames it with a unique identifier. The script also logs events 
    and errors to a log file in the destination directory.

    The script is designed to be resilient, with error handling and retry logic for the file copy operation. It also validates 
    the watched and destination directories at the start of the script.

    The script is started in a new elevated PowerShell process with the Bypass execution policy.

.AUTHOR
    Chris Mills

.DATE
    February 2024
#>

Add-Type -AssemblyName System.Windows.Forms


## INTRO MESSAGE

$Host.UI.RawUI.WindowTitle = "Powershell Watch & Copy"
$result = [System.Windows.Forms.MessageBox]::Show(
    "This script watches a specified directory for new files and copies them to another directory, with a unique filename. Please press OK to continue.", 
    "Watch & Copy", 
    [System.Windows.Forms.MessageBoxButtons]::OKCancel,
    [System.Windows.Forms.MessageBoxIcon]::Information
)
if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) { exit }

# $scriptDirectory = Get-Location
$scriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent


## CREATE LOG FILE

$logFilename = 'watch_log.txt'
$logPath = Join-Path -Path $scriptDirectory -ChildPath $logFilename
if (-not (Test-Path $logPath)) {
    New-Item -ItemType File -Path $logPath | Out-Null
    Invoke-Expression -Command "attrib +h `"$logPath`""
    Write-Host "New log file was created."
}

function Write-Report {
    param (
        [Parameter(Mandatory=$true)]
        [string]$message
    )

    $timestamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Host $logMessage
    if (Test-Path $logPath -PathType Leaf) {
        Add-Content -Path $logPath -Value $logMessage
    }
}

function Show-Error {
    param (
        [Parameter(Mandatory=$true)]
        [string]$message
    )
    Write-Report $message
    [System.Windows.Forms.MessageBox]::Show(
        $message, 
        "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Error
    )

}


## READ CONFIGURATION FILE

$configFilename = 'watch_config.json'
$configPath = Join-Path -Path $scriptDirectory -ChildPath $configFilename
$global:config = @{ 
    # default folder paths
    SourceFolderPath = $null; 
    DestinationFolderPath = $null 

    # default watch settings
    WatchCreated = $true
    WatchChanged = $false
    WatchRenamed = $true
    WatchDeleted = $false
    IncludeSubdirectories = $false
    ImageFilterEnabled = $true
}

Function Merge-Hashtables {
    $Output = @{}
    ForEach ($Hashtable in ($Input + $Args)) {
        If ($Hashtable -is [Hashtable]) {
            ForEach ($Key in $Hashtable.Keys) {$Output.$Key = $Hashtable.$Key}
        }
    }
    $Output
}

function Merge-Config {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$newConfig
    )
    $global:config = Merge-Hashtables $global:config $newConfig
}

function Write-ConfigFile {
    param (
        [switch]$Quiet = $false
    )
    try {
        $global:config | ConvertTo-Json | Set-Content -Path $configPath
        Invoke-Expression -Command "attrib +h `"$configPath`""
        if (-not $Quiet) {
            Write-Report "Saved the configuration to a hidden file at '$configPath'"
        }
    } catch {
        Write-Report "Failed to save the configuration to '$configPath': $_"
    }
}

function Read-ConfigFile {
    param(
        [switch]$Merge = $false
    )
    if (Test-Path -Path $configPath) {
        $savedConfig = @{}
        $savedConfigRaw = Get-Content -Path $configPath | ConvertFrom-Json
        $savedConfigRaw.psobject.properties | ForEach-Object { $savedConfig[$_.Name] = $_.Value }
        if ($Merge) {
            Merge-Config $savedConfig
        }
    } else {
        Write-Report "Configuration file '$configPath' does not exist"
        return $null
    }
    return $global:config
}

function Get-Config {
    return $global:config
}

Read-ConfigFile -Merge | Out-Null


## PICK FOLDERS

$pickNewFolders = $true # default

if ($null -ne $global:config.SourceFolderPath -and $null -ne $global:config.DestinationFolderPath) {
    $mess = "I found a saved configuration file!`n`n" +
            "Do you want to use the paths from last time?`n`n" +
            "Source:`n$($global:config.SourceFolderPath)`n`n" +
            "Destination:`n$($global:config.DestinationFolderPath)"
    $result = [System.Windows.Forms.MessageBox]::Show(
        $mess, 
        "Reuse Previous Watch Folders?", 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -eq "Yes") {
        if (-not (Test-Path $global:config.SourceFolderPath -PathType Container) -and 
            -not (Test-Path $global:config.DestinationFolderPath -PathType Container)) {
            Show-Error "One or both of the saved folders do not exist or are not directories. Please select new folders."
            $pickNewFolders = $true
        } else {
            Write-Report "Using the saved folder paths."
            $pickNewFolders = $false
        }
    }
}

if ($pickNewFolders -eq $true) {
    $folderConfig = @{
        SourceFolderPath = $null
        DestinationFolderPath = $null
    }
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

    # Ask for the source/watch folder
    $folderBrowser.Description = "Select the source/watch folder:"
    $dialogResult = $folderBrowser.ShowDialog()

    if ($dialogResult -eq "OK") {
        $folderConfig.SourceFolderPath = $folderBrowser.SelectedPath
        Write-Report "You selected the source/watch folder: $($folderConfig.SourceFolderPath)"
    } else {
        Show-Error "No source/watch folder was selected."
        exit
    }

    # Ask for the destination folder
    $folderBrowser.Description = "Select the destination folder:"
    $dialogResult = $folderBrowser.ShowDialog()

    if ($dialogResult -eq "OK") {
        $folderConfig.DestinationFolderPath = $folderBrowser.SelectedPath
        Write-Report "You selected the destination folder: $($folderConfig.DestinationFolderPath)"
    } else {
        Show-Error "No destination folder was selected."
        exit
    } 

    # Store the folder paths
    Merge-Config $folderConfig
}


## VALIDATE

$s = "does not exist or is not a directory. Try again. If you reused past settings, re-select your folder manually."
if (-not (Test-Path $global:config.SourceFolderPath -PathType Container)) {
    Show-Error "Watched folder `"$($global:config.SourceFolderPath)`" $s"
    exit
}
if (-not (Test-Path $global:config.DestinationFolderPath -PathType Container)) {
    Show-Error "Destination folder `"$($global:config.DestinationFolderPath)`" $s"
    exit
}


## Ask for watch events

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Watch Settings'
$form.Size = New-Object System.Drawing.Size(300,360) # Adjust form size
$form.StartPosition = 'CenterScreen' # Start the form at the center of the screen
$font = 'Microsoft Sans Serif,10' # Adjust font

$label = New-Object System.Windows.Forms.Label
$label.Text = 'Please select the file events you want to watch:'
$label.AutoSize = $false
$label.Top = 20
$label.Left = 20
$label.Width = 250
$label.Height = 40
$label.Font = $font
$form.Controls.Add($label)

$createdCB = New-Object System.Windows.Forms.CheckBox
$createdCB.Text = 'Created'
$createdCB.Top = 60
$createdCB.Left = 20
$createdCB.Font = $font
$createdCB.Checked = $global:config.WatchCreated
$form.Controls.Add($createdCB)

$changedCB = New-Object System.Windows.Forms.CheckBox
$changedCB.Text = 'Changed'
$changedCB.Top = 90
$changedCB.Left = 20
$changedCB.Font = $font
$changedCB.Checked = $global:config.WatchChanged
$form.Controls.Add($changedCB)

$renamedCB = New-Object System.Windows.Forms.CheckBox
$renamedCB.Text = 'Renamed'
$renamedCB.Top = 120
$renamedCB.Left = 20
$renamedCB.Font = $font
$renamedCB.Checked = $global:config.WatchRenamed
$form.Controls.Add($renamedCB)

$deletedCB = New-Object System.Windows.Forms.CheckBox
$deletedCB.Text = 'Deleted'
$deletedCB.Top = 150
$deletedCB.Left = 20
$deletedCB.Font = $font
$deletedCB.Checked = $global:config.WatchDeleted
$deletedCB.Enabled = $false
$form.Controls.Add($deletedCB)

$subdirCB = New-Object System.Windows.Forms.CheckBox
$subdirCB.Text = 'Include Subdirectories'
$subdirCB.AutoSize = $true
$subdirCB.Top = 190
$subdirCB.Left = 20
$subdirCB.Font = $font
$subdirCB.Checked = $global:config.IncludeSubdirectories
$form.Controls.Add($subdirCB)

$imageFilterCB = New-Object System.Windows.Forms.CheckBox
$imageFilterCB.Text = 'Filter images only'
$imageFilterCB.AutoSize = $true
$imageFilterCB.Top = 220
$imageFilterCB.Left = 20
$imageFilterCB.Font = $font
$imageFilterCB.Checked = $global:config.ImageFilterEnabled
$form.Controls.Add($imageFilterCB)

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = 'OK'
$okButton.Top = 260
$okButton.Left = 20
$okButton.Font = $font
$okButton.Add_Click({
    if (-not ($createdCB.Checked -or $deletedCheckbox.Checked -or $changedCB.Checked -or $renamedCB.Checked)) {
        [System.Windows.Forms.MessageBox]::Show('Please select at least one event to watch.', 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    } else {
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
})
$form.Controls.Add($okButton)
$okButton.Select() # Set the OK button as the default button
$form.AcceptButton = $okButton

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Show-Error "The watch settings form was exited or canceled."
    return
}

$watchSettingsConfig = @{
    WatchCreated = $createdCB.Checked
    WatchChanged = $changedCB.Checked
    WatchRenamed = $renamedCB.Checked
    WatchDeleted = $deletedCB.Checked
    IncludeSubdirectories = $subdirCB.Checked
    ImageFilterEnabled = $imageFilterCB.Checked
}
Merge-Config $watchSettingsConfig


## SAVE CONFIGURATION

Write-ConfigFile
$c = Get-Config # shorthand for the global config


## INITIALIZE WATCHER

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $c.SourceFolderPath
$watcher.IncludeSubdirectories = $global:config.IncludeSubdirectories
$watcher.EnableRaisingEvents = $true

$Action = {
    $details = $event.SourceEventArgs

    # check the extension
    $extension = [System.IO.Path]::GetExtension($details.Name).ToLower()
    $tempFilesFilterEnabled = $true
    $tempFilesExtensions = @(".ini", ".db", ".tmp", ".crdownload", ".part", ".tmp", ".temp" )
    if ($tempFilesFilterEnabled -and $tempFilesExtensions -icontains $extension) {
        # Write-Report "[Ignored] System/partial file. ($extension)"
        return
    }
    # TODO: add option to enable/disable this
    $imageFilterEnabled = $c.ImageFilterEnabled
    $allowedExtensions = @(".jfif", ".jpeg", ".jpg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".heif", ".webp")
    if ($imageFilterEnabled -and $allowedExtensions -inotcontains $extension) {
        Write-Report "[Ignored] Not an image I recognize! ($extension)"
        return
    }

    # report the event
    if ($details.ChangeType -eq "Renamed") {
        Write-Report ("[{0}] `"{1}`" -> `"{2}`"" -f $details.ChangeType, $details.OldName, $details.Name)
    } else {
        Write-Report ("[{0}] `"{1}`"" -f $details.ChangeType, $details.Name)
    }

    switch ($details.ChangeType) {
        {'Created', 'Changed', 'Renamed', 'Deleted'} {
            Copy-Image $event
        }
        default {
            Write-Report "[Unknown] Event type: $($details.ChangeType)`n$_"
        }
    }
}

function Copy-Image
{
    param (
        [System.Management.Automation.PSEventArgs]$e
    )
    try {
        $sourceFileName = $e.SourceEventArgs.Name
        $sourceFilePath = $e.SourceEventArgs.FullPath
        $timeStamp = $e.TimeGenerated
        $formattedDate = $timeStamp.ToString("yyyyMMddHHmmss")
        $extension = [System.IO.Path]::GetExtension($e.SourceEventArgs.Name).ToLower()

        # generate an MD5 hash of the file
        $hash = Get-FileHash -Path $sourceFilePath -Algorithm MD5
        if (-not $hash) {
            Write-Report "Failed to generate hash. Perhaps empty file? `"$sourceFileName`""
            return
        }

        # TODO compare hash with existing files in destination folder
        
        # give a new name
        $newname = "${formattedDate}_$($hash.Hash)$extension"

        # copy the file
        $destinationFilePath = Join-Path -Path $c.DestinationFolderPath -ChildPath $newname

        # copy the file with retry logic
        $maxRetryCount = 3
        $retryCount = 0
        while ($true) {
            try {
                Copy-Item -Path $sourceFilePath -Destination $destinationFilePath
                Write-Report "Copied as `"$newname`""
                break
            }
            catch {
                if (++$retryCount -eq $maxRetryCount) {
                    Write-Report "Failed to copy file after $maxRetryCount attempts"
                    throw 
                }
                $t = 2 * $retryCount
                Write-Report "Attempt $($retryCount) failed, retrying in $t seconds"
                Start-Sleep -Seconds $t
            }
        }
    }
    catch {
        Write-Report "An error occurred: $_"
    }
}

$eventName = @( 'Created', 'Changed', 'Renamed', 'Deleted' )
$active = @( $c.WatchCreated, $c.WatchChanged, $c.WatchRenamed, $c.WatchDeleted )
$handlers = . {
    $activeEventNames = @()

    foreach ($i in 0..($eventName.Length - 1)) {
        $identifier = "File.$($eventName[$i])"
        ## if the subcscriber already exists, remove it
        if (Get-EventSubscriber -SourceIdentifier $identifier -ErrorAction SilentlyContinue) {
            Write-Host "Unregistering event $identifier"
            Unregister-Event -SourceIdentifier $identifier
        }
        if ($active[$i]) {
            Register-ObjectEvent -InputObject $watcher -EventName $eventName[$i] -SourceIdentifier $identifier -Action $Action | Out-Null
            $activeEventNames += $eventName[$i]
        }
    }

    $eventList = [string]::Join(', ', $ActiveEventNames)
    $subdirText = if ($c.IncludeSubdirectories) { " and subdirectories." } else { "" }
    Write-Report "File watcher started for $eventList events in `"$($c.SourceFolderPath)`"$subdirText"
    Write-Host "`nKeep this terminal window open to continue watching/copying operations!" -BackgroundColor Red -ForegroundColor White
    Write-Host ""
}

function Unregister-Watcher {
    # Unregister the events
    foreach ($i in 0..($eventName.Length - 1)) {
        $identifier = "File.$($eventName[$i])"
        if (Get-EventSubscriber -SourceIdentifier $identifier -ErrorAction SilentlyContinue) {
            Unregister-Event -SourceIdentifier $identifier
            # Write-Host "Unregistered event $identifier"
        }
    }

    # Remove background jobs
    $handlers | Remove-Job

    # Stop and dispose the watcher
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()

    Write-Report "File watcher and events stopped."
}

## INITIALIZE TIMER

# $timer = New-Object Timers.Timer
# $timer.Interval = 30000

# Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier Timer.Elapsed -Action {
#     if (-not (Test-Path $c.SourceFolderPath -PathType Container)) {
#         Unregister-Watcher
#         $timer.Stop() 
#         Show-Error "Watched folder '$c.SourceFolderPath' does not exist or is not a directory"
#         exit
#     }
# } | Out-Null

# $timer.Start() # Start the timer

try {
    do {
        Wait-Event -Timeout 1
    } while ($true)
} finally {
    # this gets executed when user presses CTRL+C
    Unregister-Watcher
    Pause
}
