#
# latest-push.ps1 - Get latest push date for a repository with error handling
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME,
    [Parameter(Mandatory=$true)][String]$REPO_ID
)

. .\Helpers.ps1

try {
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/git/repositories/$REPO_ID/pushes?api-version=7.0&`$top=1"
    
    $resp = Invoke-ApiCall `
        -Uri $uriApi `
        -Method Get `
        -Headers $header `
        -Description "Get latest push for repo $REPO_ID"
    
    if ($null -eq $resp -or $null -eq $resp.Body) {
        Write-Debug-Log "No push data found for repo $REPO_ID"
        return @()
    }
    
    $response = $resp.Body
    if ($response.value -and $response.value.Count -gt 0) {
        Write-Debug-Log "Latest push found: $($response.value[0].date)"
        return $response.value
    }
    
    return @()
}
catch {
    Write-Log "Exception in latest-push.ps1 for repo $REPO_ID" -Level "ERROR" -Exception $_.Exception
    return @()
}
