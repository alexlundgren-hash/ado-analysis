param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$ORGANIZATION_NAME="",
    [String]$PROJECT_NAME="",
    [Boolean]$ONPREM=$false
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT

if($ONPREM){
    $uriApi = $ORGANIZATION_URL +"/_apis/packaging/feeds?api-version=5.0-preview.1"
}
else{
    $uriApi = "https://feeds.dev.azure.com/"+ $ORGANIZATION_NAME+"/"+$PROJECT_NAME+"/_apis/packaging/feeds?api-version=7.0"
}

$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"

return $res
