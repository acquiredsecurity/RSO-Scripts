# Deploy Chainsaw with SentinelOne RemoteOps
#
# Description: Deploys Chainsaw, executes it against Windows event logs, and outputs results in JSON format.
# Remote Script Type: Data Collection
# Required Permissions: RemoteOps execution
#
# Input Parameters:
#   -EventLogsPath: Event log directory path (optional)
#   -OutputFilePath: JSON results file path (optional)
#
# Output Path:
#   -Default: C:\ProgramData\Sentinel\RSO\chainsaw_output.json
#   -Configurable via S1_XDR_OUTPUT_FILE_PATH
#
# Exit Codes:
#   0: Success
#   1: Execution error (missing files/folders)
#   2: Chainsaw execution failed
#   3: JSON output file not created

[CmdletBinding()]
param(
    [string]$EventLogsPath = "C:\Windows\System32\winevt\Logs",
    [string]$OutputFilePath
)

# Base package directory from SentinelOne
$BasePackageDir = $ENV:S1_PACKAGE_DIR_PATH
if (-not $BasePackageDir -or -not (Test-Path $BasePackageDir)) {
    Write-Error "S1_PACKAGE_DIR_PATH not set or invalid."
    exit 1
}

# Dynamically locate Chainsaw executable
$chainsawExe = Get-ChildItem -Path $BasePackageDir -Filter "chainsaw.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $chainsawExe) {
    Write-Error "Chainsaw executable not found in package directory: $BasePackageDir"
    exit 1
}

# Dynamically locate mappings file
$mappingsFile = Get-ChildItem -Path $BasePackageDir -Filter "sigma-event-logs-all.yml" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mappingsFile) {
    Write-Error "Mappings file 'sigma-event-logs-all.yml' not found."
    exit 1
}

# Dynamically locate rules directory
$rulesDir = Get-ChildItem -Path $BasePackageDir -Directory -Filter "rules" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $rulesDir) {
    Write-Error "Rules directory 'rules' not found."
    exit 1
}

# Determine output directory
$outputDir = if ($ENV:S1_OUTPUT_DIR_PATH -and (Test-Path $ENV:S1_OUTPUT_DIR_PATH)) { 
    $ENV:S1_OUTPUT_DIR_PATH 
} else { 
    "C:\ProgramData\Sentinel\RSO" 
}

# Set output file path explicitly within this directory
$outputFile = Join-Path -Path $outputDir -ChildPath "chainsaw_output.json"

Write-Output "JSON output file (auto-collected by SentinelOne): $outputFile"

Write-Output "Chainsaw binary path: $($chainsawExe.FullName)"
Write-Output "Event logs directory: $EventLogsPath"
Write-Output "Rules directory: $($rulesDir.FullName)"
Write-Output "Mappings file: $($mappingsFile.FullName)"
Write-Output "JSON output file: $outputFile"

# Ensure output directory exists
$outputFolder = Split-Path -Path $outputFile -Parent
if (-not (Test-Path -Path $outputFolder)) {
    New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
}

# Execute Chainsaw
Write-Output "Executing Chainsaw..."
$chainsawArgs = @(
    "hunt",
    "`"$EventLogsPath`"",
    "--mapping",
    "`"$($mappingsFile.FullName)`"",
    "-s",
    "`"$($rulesDir.FullName)`"",
    "--json",
    "`"$outputFile`"",
    "--skip-errors"  
)

$process = Start-Process -FilePath $chainsawExe.FullName -ArgumentList $chainsawArgs -Wait -NoNewWindow -PassThru

# Validate Chainsaw execution
if ($process.ExitCode -ne 0) {
    Write-Error "Chainsaw execution failed with exit code $($process.ExitCode)"
    exit 2
}



# Verify JSON output
if (-not (Test-Path -Path $outputFile)) {
    Write-Error "Output JSON file was not created at $outputFile"
    exit 3
}

Write-Output "Chainsaw executed successfully. Output located at $outputFile"
exit 0
