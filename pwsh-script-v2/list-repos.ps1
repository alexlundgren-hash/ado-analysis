#
# list-repos.ps1 - List all Git repositories in a project with pagination and error handling
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME,
    [int]$PageSize = 200
)

. .\Helpers.ps1

try {
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories?api-version=7.0"
    
    Write-Log "Fetching repositories for project: $PROJECT_NAME" -Level "INFO"
    
    # Use paginated call to handle large repo counts
    $repositories = Invoke-PaginatedApiCall `
        -Uri $uriApi `
        -Headers $header `
        -PageSize $PageSize `
        -Description "List repositories in project $PROJECT_NAME"
    
    if ($null -eq $repositories) {
        Write-Log "Failed to fetch repositories for project $PROJECT_NAME" -Level "ERROR"
        return @()
    }
    
    Write-Log "Successfully retrieved $($repositories.Count) repositories" -Level "INFO"
    return $repositories
}
catch {
    Write-Log "Exception in list-repos.ps1" -Level "ERROR" -Exception $_.Exception
    return @()
}
