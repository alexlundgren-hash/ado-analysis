
param(
[String]$PAT="",
[String]$ORGANIZATION_URL="",
[String]$PROJECT_NAME="",
[String]$PROJECT_ID=""
)

. .\Helpers.ps1
function CreateAuthHeader {
    param([string]$PAT)
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}

# Http request
$header = CreateAuthHeader $PAT

$uriApi = $ORGANIZATION_URL+ "/" + $PROJECT_NAME + "/_apis/githubconnections?api-version=7.1-preview.1"

$res = Invoke-RestMethod -Uri $uriApi -Method GET -Headers $header -ContentType "application/json;charset=utf-8"


if ($res.count -gt 0){

    $body = @{
        query = "Select * From WorkItems WHERE [System.TeamProject] = '"+$PROJECT_NAME+"' AND [System.ExternalLinkCount] > 0"
        } | ConvertTo-Json
    $uriApi = $ORGANIZATION_URL+"/"+$PROJECT_ID+ "/_apis/wit/wiql?api-version=7.0"
    $res = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body

    return $res.workItems.id

}
else{
    return $null
}