param(
[String]$PAT="",
[String]$PROJECT_NAME="",
[String]$ORGANIZATION_URL=""
)

function CreateAuthHeader {
    param([string]$PAT)
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}

# Http request
$header = CreateAuthHeader $PAT
$uriApi =  $ORGANIZATION_URL + "/" + $PROJECT_NAME + "/_apis/distributedtask/deploymentgroups?api-version=5.0-preview"

$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
return $res.count
