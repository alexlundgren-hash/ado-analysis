param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME=""
)
. .\Helpers.ps1

# Http request

$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL+ "/" + $PROJECT_NAME + "/_apis/wiki/wikis?api-version=5.0"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"

return $res.value