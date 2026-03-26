param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME=""
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL+"/" + $PROJECT_NAME + "/_apis/build/builds?api-version=5.0&QueryOrder=startTimeDescending"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
return $res.value.lastChangedDate

