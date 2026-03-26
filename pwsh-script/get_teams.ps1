param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID=""
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT
$uriApi =  $ORGANIZATION_URL + "/_apis/projects/" + $PROJECT_ID + "/teams?api-version=5.0"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"

return $res
