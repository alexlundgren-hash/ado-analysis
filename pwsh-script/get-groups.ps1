param(
    [String]$PAT="",
    [String]$ORGANIZATION_Name="",
    [String]$PROJECT_NAME ="",
    [String]$ONPREM=$false
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT

$groups = @()
Do {
    $uri = "https://vssps.dev.azure.com/"+$ORGANIZATION_Name+"/_apis/graph/groups?api-version=6.0-preview.1&continuationToken="+$continuationToken+""
    $result = Invoke-WebRequest -Uri $uri -Headers $header
    $groups += ($result.Content | ConvertFrom-Json).Value
    $continuationToken = $result.Headers.'X-MS-ContinuationToken'
}
While($continuationToken)
return $groups