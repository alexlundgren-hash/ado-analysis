param(
    [String]$PAT="",
    [String]$ORGANIZATION_Name="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_NAME="",
    [Boolean]$ONPREM=$false
)

. .\Helpers.ps1

$header = CreateAuthHeader $PAT
if($ONPREM){
    $uriApi = $ORGANIZATION_URL+"/"+$PROJECT_NAME+"/_apis/release/definitions?api-version=5.0"
}
else{
    $uriApi = "https://vsrm.dev.azure.com/"+$ORGANIZATION_Name+"/"+$PROJECT_NAME+"/_apis/release/definitions?api-version=7.0" 
}

$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
#Write-Host $res.count
return $res.value
