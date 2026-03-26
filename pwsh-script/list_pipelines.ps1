param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME="",
    [Boolean]$ONPREM=$false
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT

if($ONPREM){
    $uriApi = $ORGANIZATION_URL +"/" + $PROJECT_NAME + "/_apis/build/definitions?api-version=5.1"
}
else{
    $uriApi = $ORGANIZATION_URL+"/" + $PROJECT_NAME + "/_apis/pipelines?api-version=6.0-preview.1"
}

$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
return $res.value
