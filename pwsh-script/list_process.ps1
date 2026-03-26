param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID=""
)
. .\Helpers.ps1

# Http request: Getting the process_typeId
$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL + "/_apis/projects/" + $PROJECT_ID + "/properties?keys=System.ProcessTemplateType&api-version=5.0-preview"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"
$process_typeId = $res.value.value

# Http request: Getting the name of process_type
$find_process_name_uriApi = $ORGANIZATION_URL + "/_apis/work/processes/" + $process_typeId + "?api-version=5.0-preview"
$find_process_name_res = Invoke-RestMethod -Uri $find_process_name_uriApi -Method Get -Headers $header -ContentType "application/json"

return $find_process_name_res.name
