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
    2024/02/08
#>

$block = {   

    Add-Type -AssemblyName System.Windows.Forms

    $result = [System.Windows.Forms.MessageBox]::Show(
        "This script watches a specified directory for new files and copies them to another directory, with a unique filename. Please press OK to continue.", 
        "Watch & Copy", 
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) { exit }

    $scriptDirectory = Get-Location

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
        Write-Host "`n$logMessage"
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

    if (Test-Path -Path $configPath) {
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $mess = "I found a saved configuration file!`n`n" +
                "Do you want to use the paths from last time?`n`n" +
                "Source:`n$($config.SourceFolderPath)`n`n" +
                "Destination:`n$($config.DestinationFolderPath)"
        $result = [System.Windows.Forms.MessageBox]::Show(
            $mess, 
            "Reuse Previous Watch Folders?", 
            [System.Windows.Forms.MessageBoxButtons]::YesNo, 
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
    
        if ($result -eq "Yes") {
            $sourceFolderPath = $config.SourceFolderPath
            $destinationFolderPath = $config.DestinationFolderPath
        }
    } else {
        Write-Report "Configuration file '$configPath' does not exist"
    }

    ## PICK NEW FOLDERS
    
    if ($null -eq $sourceFolderPath -or $null -eq $destinationFolderPath) {
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

        # Ask for the source/watch folder
        $folderBrowser.Description = "Select the source/watch folder:"
        $dialogResult = $folderBrowser.ShowDialog()

        if ($dialogResult -eq "OK") {
            $sourceFolderPath = $folderBrowser.SelectedPath
            Write-Report "You selected the source/watch folder: $sourceFolderPath"
        } else {
            Show-Error "No source/watch folder was selected."
            exit
        }

        # Ask for the destination folder
        $folderBrowser.Description = "Select the destination folder:"
        $dialogResult = $folderBrowser.ShowDialog()

        if ($dialogResult -eq "OK") {
            $destinationFolderPath = $folderBrowser.SelectedPath
            Write-Report "You selected the destination folder: $destinationFolderPath"
        } else {
            Show-Error "No destination folder was selected."
            exit
        } 

        # Store the folder paths in the configuration file
        $config = @{
            SourceFolderPath = $sourceFolderPath
            DestinationFolderPath = $destinationFolderPath
        }

        $config | ConvertTo-Json | Set-Content -Path $configPath
        Invoke-Expression -Command "attrib +h `"$configPath`""

        Write-Report "Saved those folder paths to a hidden configuration file at '$configPath'"
    }
    

    ## VALIDATE

    $s = "does not exist or is not a directory. Try again. If you reused past settings, re-select your folder manually."
    if (-not (Test-Path $sourceFolderPath -PathType Container)) {
        Show-Error "Watched folder '$sourceFolderPath' $s"
        exit
    }
    if (-not (Test-Path $destinationFolderPath -PathType Container)) {
        Show-Error "Destination folder '$destinationFolderPath' $s"
        exit
    }


    ## Ask for watch events

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Watch Settings'
    $form.Size = New-Object System.Drawing.Size(300,300) # Adjust form size
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

    $createdCheckbox = New-Object System.Windows.Forms.CheckBox
    $createdCheckbox.Text = 'Created'
    $createdCheckbox.Top = 60
    $createdCheckbox.Left = 20
    $createdCheckbox.Font = $font
    $createdCheckbox.Checked = $true # Set as checked by default
    $form.Controls.Add($createdCheckbox)

    $changedCheckbox = New-Object System.Windows.Forms.CheckBox
    $changedCheckbox.Text = 'Changed'
    $changedCheckbox.Top = 90
    $changedCheckbox.Left = 20
    $changedCheckbox.Font = $font
    $form.Controls.Add($changedCheckbox)

    $renamedCheckbox = New-Object System.Windows.Forms.CheckBox
    $renamedCheckbox.Text = 'Renamed'
    $renamedCheckbox.Top = 120
    $renamedCheckbox.Left = 20
    $renamedCheckbox.Font = $font
    $form.Controls.Add($renamedCheckbox)

    $subdirectoriesCheckbox = New-Object System.Windows.Forms.CheckBox
    $subdirectoriesCheckbox.Text = 'Include Subdirectories'
    $subdirectoriesCheckbox.AutoSize = $true
    $subdirectoriesCheckbox.Top = 150
    $subdirectoriesCheckbox.Left = 20
    $subdirectoriesCheckbox.Font = $font
    $form.Controls.Add($subdirectoriesCheckbox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Top = 200
    $okButton.Left = 20
    $okButton.Font = $font

    $okButton.Add_Click({
        if (-not ($createdCheckbox.Checked -or $deletedCheckbox.Checked -or $changedCheckbox.Checked -or $renamedCheckbox.Checked)) {
            [System.Windows.Forms.MessageBox]::Show('Please select at least one event to watch.', 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        } else {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
    })
    $form.Controls.Add($okButton)

    $result = $form.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Show-Error "The watch settings form was exited or canceled."
        return
    }

    ## INITIALIZE WATCHER

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $sourceFolderPath
    $watcher.IncludeSubdirectories = $subdirectoriesCheckbox.Checked
    if (-not (Test-Path $destinationFolderPath)) {
        New-Item -ItemType Directory -Path $destinationFolderPath -Force
    }

    $events = @()
    if ($createdCheckbox.Checked) {
        Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier File.Created -Action { Copy-Image $message $event } | Out-Null
        $events += 'Create'
    }
    if ($changedCheckbox.Checked) {
        Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier File.Changed -Action { Copy-Image $message $event } | Out-Null
        $events += 'Change'
    }
    if ($renamedCheckbox.Checked) {
        Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier File.Renamed -Action { Copy-Image $message $event } | Out-Null
        $events += 'Rename'
    }

    $eventList = [string]::Join(', ', $events)
    $subdirText = if ($subdirectoriesCheckbox.Checked) { " and subdirectories" } else { "" }
    Write-Report "File watcher started for $eventList events in `"$sourceFolderPath`"$subdirText."
    Write-Host "`nKeep this terminal window open to continue watching/copying operations!`n" -BackgroundColor Red -ForegroundColor White

    ## DEFINE A DISPOSE

    function Unregister-Watcher {
        # Stop and dispose the watcher
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()

        # Unregister the events
        Unregister-Event -SourceIdentifier File.Created
        Unregister-Event -SourceIdentifier File.Changed
        Unregister-Event -SourceIdentifier File.Renamed
    }

    ## INITIALIZE TIMER

    $timer = New-Object Timers.Timer
    $timer.Interval = 30000

    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier Timer.Elapsed -Action {
        if (-not (Test-Path $sourceFolderPath -PathType Container)) {
            Unregister-Watcher
            $timer.Stop() 
            Show-Error "Watched folder '$sourceFolderPath' does not exist or is not a directory"
            exit
        }
    } | Out-Null

    $timer.Start() # Start the timer


    ## DEFINE COPY OPERATION

    function Copy-Image
    {
        param ($message, $event)
        # function to call when event is raised
        try {
            $name = $event.SourceEventArgs.Name
            $path = $event.SourceEventArgs.FullPath
            # $basename = Split-Path -Path $path -Leaf
            $changeType = $event.SourceEventArgs.ChangeType
            $timeStamp = $event.TimeGenerated
            $formattedDate = $timeStamp.ToString("yyyyMMddHHmmss")

            # check the extension
            $extension = [System.IO.Path]::GetExtension($name)
            $allowedExtensions = @(".jfif", ".jpeg", ".jpg", ".png")
            if ($allowedExtensions -notcontains $extension) {
                Write-Report "Not an image I recognize! '$extension'"
                return
            }

            # generate an MD5 hash of the file
            $hash = Get-FileHash -Path $path -Algorithm MD5
            $id = "${formattedDate}_$($hash.Hash)"
            
            # give a new name
            $newname = "$id$extension"

            # copy the file
            $destinationPath = Join-Path -Path $destinationFolderPath -ChildPath $newname

            # copy the file with retry logic
            $maxRetryCount = 3
            $retryCount = 0
            while ($true) {
                try {
                    Copy-Item -Path $path -Destination $destinationPath
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

            Write-Report "The file '$name' was $changeType, copied as $newname"

            # Start-Process cmd.exe "/C echo $("{0} {1}" -f $event.SourceEventArgs.FullPath, $changeType)&pause"
        }
        catch {
            Write-Report "An error occurred: $_"
        }
        
    }

}

$encodedBlock = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($block))
$maxChars = 32768
if ( $encodedBlock.Length -gt $maxChars ) { Write-Host "Encoded command is too long: ${encodedBlock.Length} > $maxChars" }

$scriptLocation = Split-Path -Parent $MyInvocation.MyCommand.Definition
Start-Process PowerShell.exe -WorkingDirectory $scriptLocation -argumentlist '-NoExit', '-ExecutionPolicy Bypass', '-EncodedCommand', $encodedBlock
#  '-WindowStyle Hidden'
