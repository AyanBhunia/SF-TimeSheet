<#
.SYNOPSIS
    SF-Auto: Salesforce Development Workflow Automation
.DESCRIPTION
    Run one or more workflow steps by passing space-separated numbers.
    State (current org, latest version ID) is persisted in sf-auto-state.txt.

    Usage:
        .\SF-Auto.ps1 <step numbers>

    Steps:
        1  - Create new package version  (managed or unlocked, sub-menu)
        2  - Create new scratch org
        3  - Install package version in current org + assign permission set
        4  - Delete current scratch org
        5  - Promote current package version
        6  - Deploy delta changes to current org

    Examples:
        .\SF-Auto.ps1 2 1 3        # Create org -> create version -> install
        .\SF-Auto.ps1 1 3 6        # Create version -> install -> deploy
        .\SF-Auto.ps1 4            # Delete scratch org
#>

param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Steps
)

# --- Paths -----------------------------------------------------------------
$ScriptDir        = Split-Path -Parent $MyInvocation.MyCommand.Definition
$StateFile        = Join-Path $ScriptDir "sf-auto-state.txt"
$ProjectFile      = Join-Path $ScriptDir "sfdx-project.json"
$DeployScript     = Join-Path $ScriptDir "Deploy-Delta.ps1"
$ScratchDefFile   = "config/project-scratch-def.json"

# --- Output helpers --------------------------------------------------------
function Write-Step  ($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Info  ($msg) { Write-Host "  > $msg"       -ForegroundColor Gray }
function Write-Ok    ($msg) { Write-Host "  [OK] $msg"    -ForegroundColor Green }
function Write-Warn  ($msg) { Write-Host "  [!] $msg"     -ForegroundColor Yellow }
function Write-Err   ($msg) { Write-Host "  [X] $msg"     -ForegroundColor Red }

# ===========================================================================
# STATE MANAGEMENT -- simple key=value file
# ===========================================================================
function Load-State {
    $script:State = @{
        OrgAlias          = "testorg"
        LatestVersionId   = ""
        PackageType       = ""
    }
    if (Test-Path $StateFile) {
        Get-Content $StateFile | ForEach-Object {
            if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*?)\s*$") {
                $script:State[$matches[1]] = $matches[2]
            }
        }
    }
}

function Save-State {
    @(
        "# SF-Auto persistent state - auto-generated, do not edit manually",
        "# Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "",
        "OrgAlias=$($script:State.OrgAlias)",
        "LatestVersionId=$($script:State.LatestVersionId)",
        "PackageType=$($script:State.PackageType)"
    ) | Set-Content $StateFile -Encoding UTF8
}

function Show-State {
    Write-Host ""
    $orgVal = if ($script:State.OrgAlias) { $script:State.OrgAlias } else { "(none)" }
    $verVal = if ($script:State.LatestVersionId) { $script:State.LatestVersionId } else { "(none)" }
    $typeVal = if ($script:State.PackageType) { $script:State.PackageType } else { "(none)" }
    Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |  Current State                               |" -ForegroundColor DarkCyan
    Write-Host "  |  Org Alias     : $($orgVal.PadRight(26))|" -ForegroundColor DarkCyan
    Write-Host "  |  Version ID    : $($verVal.PadRight(26))|" -ForegroundColor DarkCyan
    Write-Host "  |  Package Type  : $($typeVal.PadRight(26))|" -ForegroundColor DarkCyan
    Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
}

# ===========================================================================
# HELPER -- bump managed version in sfdx-project.json
# ===========================================================================
function Bump-ManagedVersion {
    $json = Get-Content $ProjectFile -Raw | ConvertFrom-Json

    # Find the Timesheet (managed) package entry
    $pkg = $json.packageDirectories | Where-Object { $_.package -eq "Timesheet" }
    if (-not $pkg) {
        Write-Err "Could not find 'Timesheet' package in sfdx-project.json"
        return $false
    }

    # Parse current versionNumber: "2.26.0.NEXT"
    if ($pkg.versionNumber -match "^(\d+)\.(\d+)\.(\d+)\.(.+)$") {
        $major    = [int]$matches[1]
        $minor    = [int]$matches[2]
        $patch    = $matches[3]
        $suffix   = $matches[4]
    } else {
        Write-Err "Cannot parse versionNumber: $($pkg.versionNumber)"
        return $false
    }

    $newMinor    = $minor + 1
    $newVersion  = "$major.$newMinor.$patch.$suffix"
    $newAncestor = "$major.$minor.$patch"

    Write-Info "Bumping version: $($pkg.versionNumber) -> $newVersion"
    Write-Info "Setting ancestor: $($pkg.ancestorVersion) -> $newAncestor"

    # Read as text to preserve formatting
    $content = Get-Content $ProjectFile -Raw
    $oldVerStr = "`"versionNumber`": `"$($pkg.versionNumber)`""
    $newVerStr = "`"versionNumber`": `"$newVersion`""
    $oldAncStr = "`"ancestorVersion`": `"$($pkg.ancestorVersion)`""
    $newAncStr = "`"ancestorVersion`": `"$newAncestor`""

    # Replace only the first occurrence (managed package is first in the array)
    $verIdx = $content.IndexOf($oldVerStr)
    if ($verIdx -ge 0) {
        $content = $content.Remove($verIdx, $oldVerStr.Length).Insert($verIdx, $newVerStr)
    }
    $ancIdx = $content.IndexOf($oldAncStr)
    if ($ancIdx -ge 0) {
        $content = $content.Remove($ancIdx, $oldAncStr.Length).Insert($ancIdx, $newAncStr)
    }

    Set-Content $ProjectFile -Value $content -NoNewline -Encoding UTF8
    Write-Ok "sfdx-project.json updated"
    return $true
}

# ===========================================================================
# HELPER -- pick next available scratch org alias
# ===========================================================================
function Get-NextOrgAlias {
    Write-Info "Checking active scratch orgs..."
    $orgListRaw = sf org list --json 2>$null
    $orgListJson = $orgListRaw | ConvertFrom-Json

    $scratchOrgs = @()
    if ($orgListJson.result -and $orgListJson.result.scratchOrgs) {
        $scratchOrgs = @($orgListJson.result.scratchOrgs | Where-Object {
            $_.isExpired -eq $false -and $_.alias -match "^testorg\d*$"
        })
    }

    $usedAliases = @()
    foreach ($org in $scratchOrgs) {
        if ($org.alias) { $usedAliases += $org.alias }
    }

    if ($usedAliases -notcontains "testorg") {
        return "testorg"
    }

    for ($i = 2; $i -le 20; $i++) {
        $candidate = "testorg$i"
        if ($usedAliases -notcontains $candidate) {
            return $candidate
        }
    }
    return "testorg_$(Get-Date -Format 'yyyyMMddHHmmss')"
}

# ===========================================================================
# STEP 1 -- Create new package version
# ===========================================================================
function Step-CreateVersion {
    Write-Step "STEP 1: Create New Package Version"

    Write-Host ""
    Write-Host "  Select package type:" -ForegroundColor White
    Write-Host "    a  Managed -- with code coverage" -ForegroundColor White
    Write-Host "    b  Managed -- skip validation (no code coverage)" -ForegroundColor White
    Write-Host "    c  Unlocked" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  Enter choice (a/b/c)"

    switch ($choice.ToLower()) {
        "a" {
            Write-Info "Creating MANAGED version WITH code coverage..."
            if (-not (Bump-ManagedVersion)) { return }

            $script:State.PackageType = "managed"
            Save-State

            $resultRaw = sfdx force:package:version:create `
                --package Timesheet `
                --installation-key-bypass `
                -v pbo --json `
                --code-coverage `
                --post-install-script TimesheetPostInstallScript `
                --wait 30
            $result = $resultRaw | ConvertFrom-Json

            if ($result.status -eq 0) {
                $versionId = $result.result.SubscriberPackageVersionId
                $script:State.LatestVersionId = $versionId
                Save-State
                Write-Ok "Version created: $versionId"
            } else {
                Write-Err "Version creation failed:"
                Write-Host ($result | ConvertTo-Json -Depth 5)
            }
        }
        "b" {
            Write-Info "Creating MANAGED version SKIPPING validation..."
            if (-not (Bump-ManagedVersion)) { return }

            $script:State.PackageType = "managed"
            Save-State

            $resultRaw = sfdx force:package:version:create `
                --package Timesheet `
                --installation-key-bypass `
                -v pbo --json `
                --post-install-script TimesheetPostInstallScript `
                --wait 30 `
                --skipvalidation
            $result = $resultRaw | ConvertFrom-Json

            if ($result.status -eq 0) {
                $versionId = $result.result.SubscriberPackageVersionId
                $script:State.LatestVersionId = $versionId
                Save-State
                Write-Ok "Version created: $versionId"
            } else {
                Write-Err "Version creation failed:"
                Write-Host ($result | ConvertTo-Json -Depth 5)
            }
        }
        "c" {
            Write-Info "Creating UNLOCKED version..."
            $script:State.PackageType = "unlocked"
            Save-State

            $resultRaw = sfdx force:package:version:create `
                --package TimesheetUnlocked `
                --installation-key-bypass `
                -v pbo --json `
                --wait 30
            $result = $resultRaw | ConvertFrom-Json

            if ($result.status -eq 0) {
                $versionId = $result.result.SubscriberPackageVersionId
                $script:State.LatestVersionId = $versionId
                Save-State
                Write-Ok "Version created: $versionId"
            } else {
                Write-Err "Version creation failed:"
                Write-Host ($result | ConvertTo-Json -Depth 5)
            }
        }
        default {
            Write-Warn "Invalid choice '$choice'. Skipping step 1."
        }
    }
}

# ===========================================================================
# STEP 2 -- Create new scratch org
# ===========================================================================
function Step-CreateOrg {
    Write-Step "STEP 2: Create New Scratch Org"

    $alias = Get-NextOrgAlias
    Write-Info "Using alias: $alias"

    sf org create scratch `
        --set-default `
        --definition-file $ScratchDefFile `
        --alias $alias `
        --no-ancestors

    if ($LASTEXITCODE -eq 0) {
        $script:State.OrgAlias = $alias
        Save-State
        Write-Ok "Scratch org '$alias' created and set as default"
    } else {
        Write-Err "Failed to create scratch org"
    }
}

# ===========================================================================
# STEP 3 -- Install package version + assign permission set
# ===========================================================================
function Step-InstallVersion {
    Write-Step "STEP 3: Install Package and Assign Permission Set"

    $versionId = $script:State.LatestVersionId
    $orgAlias  = $script:State.OrgAlias

    if (-not $versionId) {
        Write-Warn "No version ID stored. Enter one manually:"
        $versionId = Read-Host "  Package Version ID (04t...)"
        if (-not $versionId) {
            Write-Err "No version ID provided. Skipping."
            return
        }
        $script:State.LatestVersionId = $versionId
        Save-State
    }

    Write-Info "Installing $versionId into '$orgAlias'..."
    sf package install --package $versionId --wait 30 --target-org $orgAlias

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Package installed"

        Write-Info "Assigning permission set 'Timesheet_HR_Admin'..."
        sfdx force:user:permset:assign -n Timesheet_HR_Admin -u $orgAlias

        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Permission set assigned"
        } else {
            Write-Warn "Permission set assignment had issues (check above)"
        }
    } else {
        Write-Err "Package installation failed"
    }
}

# ===========================================================================
# STEP 4 -- Delete current scratch org
# ===========================================================================
function Step-DeleteOrg {
    Write-Step "STEP 4: Delete Scratch Org"

    $orgAlias = $script:State.OrgAlias

    Write-Info "Deleting scratch org '$orgAlias'..."
    sf org delete scratch --target-org $orgAlias --no-prompt

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Scratch org '$orgAlias' deleted"
    } else {
        Write-Warn "Delete may have failed (org might not exist)"
    }
}

# ===========================================================================
# STEP 5 -- Promote package version
# ===========================================================================
function Step-PromoteVersion {
    Write-Step "STEP 5: Promote Package Version"

    $versionId = $script:State.LatestVersionId

    if (-not $versionId) {
        Write-Warn "No version ID stored. Enter one manually:"
        $versionId = Read-Host "  Package Version ID (04t...)"
        if (-not $versionId) {
            Write-Err "No version ID provided. Skipping."
            return
        }
        $script:State.LatestVersionId = $versionId
        Save-State
    }

    Write-Info "Promoting $versionId..."
    sf package version promote --package $versionId --no-prompt

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Version promoted successfully"
    } else {
        Write-Err "Promotion failed"
    }
}

# ===========================================================================
# STEP 6 -- Deploy delta changes
# ===========================================================================
function Step-DeployDelta {
    Write-Step "STEP 6: Deploy Delta Changes"

    $orgAlias = $script:State.OrgAlias
    Write-Info "Deploying to '$orgAlias'..."

    # Set target-org so Deploy-Delta.ps1 uses the correct org
    $env:SFDX_DEFAULTUSERNAME = $orgAlias

    if (Test-Path $DeployScript) {
        & $DeployScript
    } else {
        Write-Err "Deploy-Delta.ps1 not found at: $DeployScript"
    }
}

# ===========================================================================
# MAIN -- parse arguments and run steps
# ===========================================================================
Load-State

# If no steps provided, show interactive menu
if (-not $Steps -or $Steps.Count -eq 0) {
    Write-Host ""
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Host "  |       SF-Auto: Salesforce Workflow Manager          |" -ForegroundColor Cyan
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Host "  |  1  Create new package version                     |" -ForegroundColor White
    Write-Host "  |  2  Create new scratch org                         |" -ForegroundColor White
    Write-Host "  |  3  Install package + assign permission set        |" -ForegroundColor White
    Write-Host "  |  4  Delete current scratch org                     |" -ForegroundColor White
    Write-Host "  |  5  Promote package version                        |" -ForegroundColor White
    Write-Host "  |  6  Deploy delta changes                           |" -ForegroundColor White
    Write-Host "  +====================================================+" -ForegroundColor Cyan

    Show-State

    Write-Host ""
    $userInput = Read-Host "  Enter step numbers (space-separated, e.g. '2 1 3')"
    $Steps = $userInput -split '\s+'
}

# Show current state before running
Show-State
Write-Host ""
$stepList = $Steps -join " -> "
Write-Host "  Running steps: $stepList" -ForegroundColor Magenta
Write-Host ""

# Execute each step in order
foreach ($step in $Steps) {
    switch ($step.Trim()) {
        "1" { Step-CreateVersion }
        "2" { Step-CreateOrg }
        "3" { Step-InstallVersion }
        "4" { Step-DeleteOrg }
        "5" { Step-PromoteVersion }
        "6" { Step-DeployDelta }
        default {
            Write-Warn "Unknown step '$step' -- skipping"
        }
    }
}

# Show final state
Write-Host ""
Write-Host "  --- Done ---" -ForegroundColor Green
Show-State
Write-Host ""
