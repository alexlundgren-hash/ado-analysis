param(
    [String]$PAT ="",
    [String]$ORGANIZATION_URL ="",
    [String]$PROJECT_NAME ="",
    [String]$PROJECT_ID =""
)
. .\Helpers.ps1


# over 50 revs
$body50 = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' AND [System.Rev] > 50 AND [System.Rev] < 100"
} | ConvertTo-Json

# #over 100 revs
$body100 = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' AND [System.Rev] > 99"
} | ConvertTo-Json

$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL + "/" + $PROJECT_ID + "/_apis/wit/wiql?api-version=5.0"
$res50 = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body50
$res100 = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body100

$result = New-Object PSObject -Property @{
    Result50 = $res50.workItems.Count
    Result100 = $res100.workItems.Count
}

return $result
