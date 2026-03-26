param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME="",
    [String]$REPO_ID=""
)

. .\Helpers.ps1

$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL+"/" + $PROJECT_NAME + "/_apis/git/repositories/"+$REPO_ID+"/pushes?api-version=5.0"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
return $res.value
