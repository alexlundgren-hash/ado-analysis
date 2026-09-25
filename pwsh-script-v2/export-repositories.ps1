#
# export-repositories.ps1 - Export detailed repository inventory for a project
#
# Note: the Repositories List API does not support $top/$skip/continuationToken;
# it always returns the full list of repos in a single response, so no pagination
# is needed (or possible) here.

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME,
    [Parameter(Mandatory=$true)][String]$OUTPUT_FILE,
    [bool]$AppendToExisting = $false
)

. "$PSScriptRoot\Helpers.ps1"

try {
    Write-Log "Starting repository inventory export for project: $PROJECT_NAME" -Level "INFO"
    
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories?api-version=7.0"
    
    $resp = Invoke-ApiCall `
        -Uri $uriApi `
        -Method Get `
        -Headers $header `
        -Description "Export repositories for $PROJECT_NAME"
    
    if ($null -eq $resp -or $null -eq $resp.Body -or $null -eq $resp.Body.value -or $resp.Body.value.Count -eq 0) {
        Write-Log "No repositories found for project $PROJECT_NAME" -Level "WARN"
        return $false
    }
    
    $repositories = $resp.Body.value
    
    $repoInventory = @()
    
    foreach ($repo in $repositories) {
        try {
            Write-Debug-Log "Processing repository: $($repo.name)"
            
            # Fetch latest push for this repo
            $latestPush = "No commits"
            try {
                $pushUri = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories/$($repo.id)/pushes?api-version=7.0&`$top=1"
                $pushResp = Invoke-ApiCall -Uri $pushUri -Method Get -Headers $header -Description "Latest push for repo $($repo.name)"
                
                if ($pushResp -and $pushResp.Body -and $pushResp.Body.value -and $pushResp.Body.value.Count -gt 0 -and $null -ne $pushResp.Body.value[0].date) {
                    $latestPush = Format-DateForCsv $pushResp.Body.value[0].date
                }
            }
            catch {
                Write-Debug-Log "Failed to fetch push date for repo $($repo.name): $($_.Exception.Message)"
                $latestPush = "No commits"
            }
            
            # Convert repository size from bytes to megabytes
            $sizeBytes = Safe-PropertyAccess -Object $repo -PropertyPath "size" -DefaultValue 0
            $sizeMb = [Math]::Round([double]$sizeBytes / 1MB, 2)

            # Build inventory record
            $repoRecord = New-Object PSObject -Property @{
                ProjectName          = $PROJECT_NAME
                RepositoryId         = $repo.id
                RepositoryName       = $repo.name
                RepositoryUrl        = $repo.url
                DefaultBranch        = Safe-PropertyAccess -Object $repo -PropertyPath "defaultBranch" -DefaultValue "N/A"
                WebUrl               = Safe-PropertyAccess -Object $repo -PropertyPath "webUrl" -DefaultValue "N/A"
                RepositoryType       = Safe-PropertyAccess -Object $repo -PropertyPath "repositoryType" -DefaultValue "Git"
                SizeMB               = $sizeMb
                IsDisabled           = Safe-PropertyAccess -Object $repo -PropertyPath "isDisabled" -DefaultValue "false"
                IsFork               = Safe-PropertyAccess -Object $repo -PropertyPath "isFork" -DefaultValue "false"
                LatestPushDate       = $latestPush
                ExportDateTime       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            $repoInventory += $repoRecord
            Write-Log "Processed repository: $($repo.name)" -Level "DEBUG"
        }
        catch {
            Write-Log "Error processing repository $($repo.name): $($_.Exception.Message)" -Level "WARN"
            continue
        }
    }
    
    # Export to CSV
    if ($repoInventory.Count -gt 0) {
        $success = Export-InventoryCsv -Data $repoInventory -FilePath $OUTPUT_FILE -Append $AppendToExisting
        
        if ($success) {
            Write-Log "Repository inventory exported: $($repoInventory.Count) records to $OUTPUT_FILE" -Level "INFO"
            return $true
        }
        else {
            Write-Log "Failed to export repository inventory" -Level "ERROR"
            return $false
        }
    }
    else {
        Write-Log "No repository records to export" -Level "WARN"
        return $false
    }
}
catch {
    Write-Log "Exception in export-repositories.ps1" -Level "ERROR" -Exception $_.Exception
    return $false
}
