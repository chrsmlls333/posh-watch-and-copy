
# PowerShell File Watch and Copy

This PowerShell script monitors a specified source directory for file changes, including file creation, modification, and renaming. When such an event occurs, the script copies the affected file to a designated destination directory and renames it with a unique identifier.

Note: this script is built for Windows PowerShell 5.1 and may not work with PowerShell Core.

## Usage

- Clone the repository to your local machine.
- Unblock the `launch.ps1` file by right-clicking it, selecting Properties, and clicking the Unblock button
  - or by running the following command in PowerShell: 
  ```powershell
  Unblock-File -Path .\launch.ps1
  ```
  - or by setting the execution policy to Unrestricted:
  ```powershell
  Set-ExecutionPolicy Unrestricted
  ```
  - Note: this is a security risk and should be used with caution. Always set the execution policy back to Restricted or RemoteSigned after running the script.
  - Always review the contents of a script before running it.
- Run `launch.ps1` to start `watch.ps1` in a new Windows PowerShell process with the Bypass execution policy. 
- You will be given a short intro dialog, then prompted to select the source and destination directories if there is no hiorstory of these paths in the config file.
- The script will then prompt you to select the types of file events to watch for: file creation, changes, renaming, or deletion (not implemented).
- The script will start monitoring the source directory, logging events and errors to a log file, `watch_log.txt`, in the script's directory.


## Features

- **Configuration File**: The script starts by reading a configuration file, `watch_config.json`, which stores the paths of the source and destination directories from the last run. If the configuration file doesn't exist or the user chooses not to reuse the paths, the script prompts the user to manually select the source and destination directories.

- **Directory Validation**: The script then validates the existence of the source and destination directories. If either directory doesn't exist, the script shows an error message and exits.

- **Event Selection**: Next, the script prompts the user to select the types of file events to watch for: file creation, modification, or renaming. The user's choices are stored and used to set up a `FileSystemWatcher` on the source directory.

- **Logging**: The script also includes a `Write-Report` function, which logs events and errors to a log file, `watch_log.txt`, in the script's directory. The log file is hidden to prevent accidental deletion or modification.

- **Resilience**: The script is designed to be resilient, with error handling and retry logic for the file copy operation.

- **Execution**: The script is started in a new PowerShell process with the Bypass execution policy.

Finally, the script starts the file watcher and displays a message indicating the types of events it's watching for and the directory it's monitoring. The script continues to run and monitor the source directory until the user closes the terminal window.

## Note on Hardcoded Settings/Values

I built this for my own use case, so comment or rewrite these areas to alter behaviour.

- File renaming patterns of `$date_$md5hash.$ext` 
- Whitelisting file extensions (image files: jfif, jp(e)g, png)
- Copy retry count.

## Room for Improvement

- Tie more options into config file values or parameters
  - Allow for filename templating
- Find a better system than the "encoded command into new process" method
  - Administrator permissions based on the original working scope
  - Does it need the execution policy bypass?
- Put a time limit on the hashing function or check filesize first
- Use a faster copy command like robocopy (benefits?)


## Helpful References

- [FileSystemWatcher Class](https://docs.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher?view=net-5.0)
- https://blog.idera.com/database-tools/using-filesystemwatcher-correctly-part-2