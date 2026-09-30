# Check if the --opp (or -opp) argument was passed
$flipSlashes = ($args -contains "--opp") -or ($args -contains "-opp")

Write-Host "Scanning for local changes..." -ForegroundColor Cyan

# Get changed files, filter for the force-app folder, and extract the path
$changedFiles = git status --porcelain | 
    Where-Object { $_ -match "^[ MAU\?]{2}\s+(.*force-app/main/default/.*)" } | 
    ForEach-Object { $matches[1] }

if (-not $changedFiles) {
    Write-Host "No deployable changes detected in force-app/main/default." -ForegroundColor Yellow
    exit
}

$deployPaths = @{}

foreach ($file in $changedFiles) {
    # Convert Unix paths from Git to Windows paths, and strip quoting git adds for special characters
    $winPath = ($file -replace "/", "\").Trim('"')

    # If LWC or Aura, capture the bundle folder. Otherwise, capture the exact file.
    if ($winPath -match "(.*\\(?:lwc|aura)\\[^\\]+)") {
        $deployPaths[$matches[1]] = $true
    } else {
        $deployPaths[$winPath] = $true
    }
}

# Build the argument list as an array so paths containing spaces (e.g. layout
# file names like "QBO Reference Data Layout.layout-meta.xml") survive intact.
# Invoke-Expression re-tokenizes the whole command string and mis-splits such
# paths even when individually quoted, so call sf directly with an array instead.
$sfArgs = @("project", "deploy", "start")
foreach ($target in $deployPaths.Keys) {
    $sfArgs += "-d"
    
    # If --opp is passed, flip backslashes to forward slashes
    if ($flipSlashes) {
        $sfArgs += $target -replace '\\', '/'
    } else {
        $sfArgs += $target
    }
}
$sfArgs += "--ignore-conflicts"

Write-Host "`nExecuting:`nsf $($sfArgs -join ' ')`n" -ForegroundColor Green

# Run the command
& sf @sfArgs