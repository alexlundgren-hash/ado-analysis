param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME=""
)

. .\Helpers.ps1


$header = CreateAuthHeader $PAT

$uriApi = $ORGANIZATION_URL+"/" + $PROJECT_NAME + "/_apis/tfvc/changesets?api-version=7.0"

Try{
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
}
catch {
    return $null
}

return $res.value
