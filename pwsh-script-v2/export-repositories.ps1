#
# export-repositories.ps1 - Export detailed repository inventory for a project
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME,
    [Parameter(Mandatory=$true)][String]$OUTPUT_FILE,
    [bool]$AppendToExisting = $false,
    [int]$PageSize = 200
)

. .\Helpers.ps1

try {
    Write-Log "Starting repository inventory export for project: $PROJECT_NAME" -Level "INFO"
    
    $header = CreateAuthHeader $PAT
    
    # Fetch all repositories with pagination
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories?api-version=7.0"
    
    $repositories = Invoke-PaginatedApiCall `
        -Uri $uriApi `
        -Headers $header `
        -PageSize $PageSize `
        -Description "Export repositories for $PROJECT_NAME"
    
    if ($null -eq $repositories -or $repositories.Count -eq 0) {
        Write-Log "No repositories found for project $PROJECT_NAME" -Level "WARN"
        return $false
    }
    
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
            
            # Build inventory record
            $repoRecord = New-Object PSObject -Property @{
                ProjectName          = $PROJECT_NAME
                RepositoryId         = $repo.id
                RepositoryName       = $repo.name
                RepositoryUrl        = $repo.url
                DefaultBranch        = Safe-PropertyAccess -Object $repo -PropertyPath "defaultBranch" -DefaultValue "N/A"
                WebUrl               = Safe-PropertyAccess -Object $repo -PropertyPath "webUrl" -DefaultValue "N/A"
                RepositoryType       = Safe-PropertyAccess -Object $repo -PropertyPath "repositoryType" -DefaultValue "Git"
                Size                 = Safe-PropertyAccess -Object $repo -PropertyPath "size" -DefaultValue "0"
                IsDisabled           = Safe-PropertyAccess -Object $repo -PropertyPath "isDisabled" -DefaultValue "false"
                IsFork               = Safe-PropertyAccess -Object $repo -PropertyPath "isFork" -DefaultValue "false"
                CreatedDate          = Format-DateForCsv (Safe-PropertyAccess -Object $repo -PropertyPath "createdDate")
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
