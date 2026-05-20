#
# main.ps1 - Improved Azure DevOps inventory collection script with error handling and logging
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_Name,
    [Parameter(Mandatory=$true)][String]$CSVFILENAME,
    [Boolean]$ONPREM=$false,
    [String]$LOGFILE="",
    [String]$REPO_CSVFILE="",
    [Boolean]$EXPORT_REPOS=$true
)

. .\Helpers.ps1

# ============================================================================
# INITIALIZATION
# ============================================================================

try {
    # Initialize logging
    if ([string]::IsNullOrEmpty($LOGFILE)) {
        $LOGFILE = ".\ado-inventory-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    }
    
    Initialize-Logger -LogFile $LOGFILE -LogLevel "INFO"
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Azure DevOps Inventory Export Started" -ForegroundColor Green
    
    # Validate parameters
    if ([string]::IsNullOrEmpty($PAT)) {
        throw "PAT cannot be empty"
    }
    
    if ([string]::IsNullOrEmpty($ORGANIZATION_URL)) {
        throw "ORGANIZATION_URL cannot be empty"
    }
    
    # Set default repo CSV path if not specified
    if ([string]::IsNullOrEmpty($REPO_CSVFILE)) {
        $REPO_CSVFILE = ".\" + [System.IO.Path]::GetFileNameWithoutExtension($CSVFILENAME) + "_repositories.csv"
    }
    
    Write-Log "========================================" -Level "INFO"
    Write-Log "Organization: $ORGANIZATION_URL" -Level "INFO"
    Write-Log "Org Name: $ORGANIZATION_Name" -Level "INFO"
    Write-Log "On-Prem: $ONPREM" -Level "INFO"
    Write-Log "Output CSV: $CSVFILENAME" -Level "INFO"
    Write-Log "Repository CSV: $REPO_CSVFILE (export enabled: $EXPORT_REPOS)" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
}
catch {
    Write-Host "Initialization failed: $_" -ForegroundColor Red
    exit 1
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {
    # Fetch all projects
    Write-Log "Fetching projects..." -Level "INFO"
    $list_projects = .\list-projects.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL
    
    if ($null -eq $list_projects -or $list_projects.Count -eq 0) {
        Write-Log "No projects found or failed to fetch projects" -Level "ERROR"
        exit 1
    }
    
    Write-Log "Found $($list_projects.Count) projects" -Level "INFO"
    
    $project_collection = @()
    $repo_collection = @()
    $processed_count = 0
    $failed_count = 0
    $repo_file_exists = $false
    
    # Process each project
    foreach ($project in $list_projects) {
        try {
            $processed_count++
            $projectProgress = "$processed_count/$($list_projects.Count)"
            Write-Log "Processing project [$projectProgress]: $($project.name)" -Level "INFO"
            
            # Create base project object
            $add_project = New-InventoryObject -Properties @{
                Project = $project.name
                ProjectId = $project.id
                ProjectState = $project.state
                ProjectDescription = Safe-PropertyAccess -Object $project -PropertyPath "description" -DefaultValue "N/A"
                ProjectUrl = Safe-PropertyAccess -Object $project -PropertyPath "url" -DefaultValue "N/A"
            }
            
            # ============================================================
            # REPOSITORIES
            # ============================================================
            Write-Debug-Log "Collecting repository metrics..."
            $list_repos = .\list-repos.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
            $add_project | Add-Member -Name "Repositories" -Type NoteProperty -Value ($list_repos.Count ?? 0)
            
            # Export individual repository details
            if ($EXPORT_REPOS -and $list_repos.Count -gt 0) {
                Write-Debug-Log "Exporting $($list_repos.Count) repositories..."
                .\export-repositories.ps1 `
                    -PAT $PAT `
                    -ORGANIZATION_URL $ORGANIZATION_URL `
                    -PROJECT_NAME $project.name `
                    -OUTPUT_FILE $REPO_CSVFILE `
                    -AppendToExisting $repo_file_exists | Out-Null
                $repo_file_exists = $true
            }
            
            # Get latest push across all repos
            $latestPush = "No pushes"
            if ($list_repos.Count -gt 0) {
                $pushDates = @()
                foreach ($repo in $list_repos) {
                    try {
                        $repo_push = .\latest-push.ps1 `
                            -PAT $PAT `
                            -ORGANIZATION_URL $ORGANIZATION_URL `
                            -PROJECT_NAME $project.name `
                            -REPO_ID $repo.id
                        
                        if ($repo_push.Count -gt 0) {
                            $pushDates += $repo_push[0].date
                        }
                    }
                    catch {
                        Write-Debug-Log "Failed to get push for repo $($repo.name)"
                    }
                }
                
                $latest = Get-LatestDate $pushDates
                if ($null -ne $latest) {
                    $latestPush = Format-DateForCsv $latest
                }
            }
            $add_project | Add-Member -Name "LatestPushDate" -Type NoteProperty -Value $latestPush
            
            # ============================================================
            # TFVC
            # ============================================================
            Write-Debug-Log "Collecting TFVC metrics..."
            $tfvc = .\get-latest-tfvc.ps1 `
                -PAT $PAT `
                -ORGANIZATION_URL $ORGANIZATION_URL `
                -PROJECT_NAME $project.name
            
            $latestTfvc = "No TFVC"
            if ($tfvc.Count -gt 0) {
                $latest_tfvc_date = Get-LatestDate ($tfvc.createdDate)
                if ($null -ne $latest_tfvc_date) {
                    $latestTfvc = Format-DateForCsv $latest_tfvc_date
                }
            }
            $add_project | Add-Member -Name "LatestTfvcDate" -Type NoteProperty -Value $latestTfvc
            
            # ============================================================
            # PROJECT METADATA
            # ============================================================
            $add_project | Add-Member -Name "ProjectUpdated" -Type NoteProperty -Value (Format-DateForCsv $project.lastUpdateTime)
            $add_project | Add-Member -Name "ExportDateTime" -Type NoteProperty -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            
            $project_collection += $add_project
            Write-Log "Successfully processed project: $($project.name)" -Level "DEBUG"
        }
        catch {
            $failed_count++
            Write-Log "Failed to process project $($project.name)" -Level "ERROR" -Exception $_.Exception
            continue
        }
    }
    
    # ============================================================================
    # EXPORT RESULTS
    # ============================================================================
    
    Write-Log "Processed $processed_count projects with $failed_count failures" -Level "INFO"
    
    if ($project_collection.Count -gt 0) {
        $success = Export-InventoryCsv `
            -Data $project_collection `
            -FilePath $CSVFILENAME `
            -Append $false
        
        if ($success) {
            Write-Log "Project inventory exported: $($project_collection.Count) records" -Level "INFO"
        }
        else {
            Write-Log "Failed to export project inventory" -Level "ERROR"
        }
    }
    else {
        Write-Log "No projects to export" -Level "WARN"
    }
    
    Write-Log "========================================" -Level "INFO"
    Write-Log "Azure DevOps Inventory Export Completed" -Level "INFO"
    Write-Log "Projects Processed: $processed_count" -Level "INFO"
    Write-Log "Failures: $failed_count" -Level "INFO"
    Write-Log "Log File: $LOGFILE" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
}
catch {
    if ($null -ne (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        Write-Log "Fatal error in main script" -Level "ERROR" -Exception $_.Exception
    }
    else {
        Write-Host "Fatal error in main script: $($_.Exception.Message)" -ForegroundColor Red
    }
    exit 1
}
