#
# list-projects.ps1 - List all projects with pagination and error handling
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [int]$PageSize = 200
)

. .\Helpers.ps1

try {
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/_apis/projects?api-version=7.0"
    
    Write-Log "Fetching projects from organization" -Level "INFO"
    
    # Use paginated call to handle large project counts
    $projects = Invoke-PaginatedApiCall `
        -Uri $uriApi `
        -Headers $header `
        -PageSize $PageSize `
        -Description "List all projects"
    
    if ($null -eq $projects) {
        Write-Log "Failed to fetch projects" -Level "ERROR"
        return @()
    }
    
    Write-Log "Successfully retrieved $($projects.Count) projects" -Level "INFO"
    return $projects
}
catch {
    Write-Log "Exception in list-projects.ps1" -Level "ERROR" -Exception $_.Exception
    return @()
}
