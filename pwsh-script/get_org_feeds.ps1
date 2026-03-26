# GET https://feeds.dev.azure.com/{organization}/{project}/_apis/packaging/feeds?api-version=7.0
param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$ORGANIZATION_Name="",
    [Boolean]$ONPREM=$false
)

. .\Helpers.ps1

# Http request
$header = CreateAuthHeader $PAT


if($ONPREM){
    $uriApi = $ORGANIZATION_URL +"/_apis/packaging/feeds?api-version=5.0-preview.1"
}
else{
    $uriApi = "https://feeds.dev.azure.com/" + $ORGANIZATION_Name + "/_apis/packaging/feeds?api-version=7.0"
}


$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"

$orgscoped = @()

foreach($feed in $res.value){
if ($feed.PSObject.Properties.Name -contains 'project') {
} else {
    $orgscoped += $feed
}}

#return $res
return $orgscoped.Count