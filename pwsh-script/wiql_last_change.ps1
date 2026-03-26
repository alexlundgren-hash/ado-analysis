param(
    [String]$PAT = "",
    [String]$ORGANIZATION_URL = "",
    [String]$PROJECT_NAME = "",
    [String]$PROJECT_ID = "",
    [String]$ORGANIZATION_Name = ""
)

. .\Helpers.ps1

# Find the latest changed date wiql
$body = @{
    query = "Select * From WorkItems WHERE [System.TeamProject] = '" + $PROJECT_NAME + "' order by [System.ChangedDate] desc"
} | ConvertTo-Json
$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL + $PROJECT_ID + "/_apis/wit/wiql?`$top=1&api-version=6.0"

$res = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body

# If project contains any work items -> Get info about the latest changed one
if ($null -ne $res.workItems -and $res.workItems.Count -gt 0) {
    $find_latest_date_wiql_url = $res.workItems[0].url
    $latest_wiql_res = Invoke-RestMethod -Uri $find_latest_date_wiql_url -Method Get -Headers $header -ContentType "application/json;charset=utf-8"
    $latest_date = $latest_wiql_res.fields.'System.ChangedDate'
    if ($null -eq $latest_date) {
        return "0"
    }
    $formatting_date = ([DateTime]$latest_date).ToString('yyyy-MM-dd')
    return $formatting_date
}
# If no work items found -> return "0" or "null" (main.ps1 expects '0' for no items)
else {
    return "0"
}

