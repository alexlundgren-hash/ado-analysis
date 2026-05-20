#
# get-latest-tfvc.ps1 - Get latest TFVC changesets with improved error handling
#

param(
    [Parameter(Mandatory=$true)][String]$PAT,
    [Parameter(Mandatory=$true)][String]$ORGANIZATION_URL,
    [Parameter(Mandatory=$true)][String]$PROJECT_NAME
)

. .\Helpers.ps1

try {
    $header = CreateAuthHeader $PAT
    
    $uriApi = "$ORGANIZATION_URL/$PROJECT_NAME/_apis/tfvc/changesets?api-version=7.0&`$top=1"
    
    Write-Debug-Log "Fetching TFVC changesets for project $PROJECT_NAME"
    
    $resp = Invoke-ApiCall `
        -Uri $uriApi `
        -Method Get `
        -Headers $header `
        -Description "Get latest TFVC changesets for $PROJECT_NAME" `
        -MaxRetries 2
    
    if ($null -eq $resp -or $null -eq $resp.Body) {
        Write-Log "No TFVC changesets found (project may not use TFVC)" -Level "DEBUG"
        return @()
    }
    
    $response = $resp.Body
    if ($response.value -and $response.value.Count -gt 0) {
        Write-Log "Found $($response.value.Count) TFVC changesets" -Level "DEBUG"
        return $response.value
    }
    
    return @()
}
catch {
    Write-Log "TFVC not available or error fetching changesets: $($_.Exception.Message)" -Level "DEBUG"
    return @()
}
