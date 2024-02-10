
# PowerShell File Watch and Copy

This PowerShell script is a robust file watcher and copier. It monitors a specified source directory for file changes, including file creation, modification, and renaming. When such an event occurs, the script copies the affected file to a designated destination directory and renames it with a unique identifier.

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
