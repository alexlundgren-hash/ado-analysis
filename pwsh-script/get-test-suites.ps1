param(
    [String]$PAT ="",
    [String]$ORGANIZATION_URL ="",
    [String]$PROJECT_NAME ="",
    [String]$PROJECT_ID =""
)
. .\Helpers.ps1


# Test suites
$bodysteps = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' AND [System.WorkItemType] = 'Test Suite'"
} | ConvertTo-Json


$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL + "/" + $PROJECT_ID + "/_apis/wit/wiql?api-version=5.0"
$suites = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $bodysteps

return $suites.workItems.Count
