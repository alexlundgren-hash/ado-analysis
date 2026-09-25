#
# list-repos.ps1 - List all Git repositories in a project with error handling
#
# Note: the Repositories List API does not support $top/$skip/continuationToken;
# it always returns the full list of repos in a single response, so no pagination
# is needed (or possible) here.

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME
)

. "$PSScriptRoot\Helpers.ps1"

try {
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories?api-version=7.0"
    
    Write-Log "Fetching repositories for project: $PROJECT_NAME" -Level "INFO"
    
    $resp = Invoke-ApiCall `
        -Uri $uriApi `
        -Method Get `
        -Headers $header `
        -Description "List repositories in project $PROJECT_NAME"
    
    if ($null -eq $resp -or $null -eq $resp.Body -or $null -eq $resp.Body.value) {
        Write-Log "Failed to fetch repositories for project $PROJECT_NAME" -Level "ERROR"
        return @()
    }
    
    $repositories = $resp.Body.value
    Write-Log "Successfully retrieved $($repositories.Count) repositories" -Level "INFO"
    return $repositories
}
catch {
    Write-Log "Exception in list-repos.ps1" -Level "ERROR" -Exception $_.Exception
    return @()
}
