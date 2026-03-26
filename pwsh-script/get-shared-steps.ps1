param(
    [String]$PAT ="",
    [String]$ORGANIZATION_URL ="",
    [String]$PROJECT_NAME ="",
    [String]$PROJECT_ID =""
)
. .\Helpers.ps1


# shared steps
$bodysteps = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' AND [System.WorkItemType] = 'Shared Steps'"
} | ConvertTo-Json

# shared parameters
$bodyparameter = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' AND [System.WorkItemType] = 'Shared Parameter'"
} | ConvertTo-Json

$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL + "/" + $PROJECT_ID + "/_apis/wit/wiql?api-version=5.0"
$steps = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $bodysteps
$parameter = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $bodyparameter

$result = New-Object PSObject -Property @{
    resultSteps = $steps.workItems.Count
    resultParameter = $parameter.workItems.Count
}

return $result
