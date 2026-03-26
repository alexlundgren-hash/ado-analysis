function listWorkItemTypes {
    param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID=""
    )

    $header = CreateAuthHeader $PAT
    $uriApi = $ORGANIZATION_URL+"/_apis/projects/" + $PROJECT_ID + "/properties?keys=System.ProcessTemplateType&api-version=7.0-preview.1"

    $res = Invoke-RestMethod -Uri $uriApi -Method GET -Headers $header -ContentType "application/json;charset=utf-8"

    $WorkItemTypeUri = $ORGANIZATION_URL+"/_apis/work/processdefinitions/" + $res.value.value + "/workitemtypes?api-version=4.1-preview.1"
    $resWorkItemType = Invoke-RestMethod -Uri $WorkItemTypeUri -Method GET -Headers $header -ContentType "application/json;charset=utf-8"

    return $resWorkItemType
}
function CreateAuthHeader {
    param([string]$PAT)
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}
function getLastWorkItem {
    param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID="",
    [String]$PROJECT_NAME=""
    )
    $header = CreateAuthHeader $PAT
    
    $lastWorkItemBody = @{
        query = "Select * From WorkItems WHERE [System.TeamProject] = '"+$PROJECT_NAME+"' order by [System.Id] desc"
        } | ConvertTo-Json
    $UriApi = $ORGANIZATION_URL+"/"+$PROJECT_ID+ "/_apis/wit/wiql?`$top=1&api-version=5.0"
    $res = Invoke-RestMethod -Uri $UriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $lastWorkItemBody
    return $res.workItems

}

function getFirstWorkItem {
    param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID="",
    [String]$PROJECT_NAME=""
    )
    $header = CreateAuthHeader $PAT
    $firstWorkItemBody = @{
        query = "Select * From WorkItems WHERE [System.TeamProject] = '"+$PROJECT_NAME+"' order by [System.Id] asc"
        } | ConvertTo-Json
    $UriApi = $ORGANIZATION_URL+"/"+$PROJECT_ID+ "/_apis/wit/wiql?`$top=1&api-version=5.0"
    $res = Invoke-RestMethod -Uri $UriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $firstWorkItemBody
    return $res.workItems
}

function ConvertTo-JsonFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [System.Object[]]$InputObject,
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    $json = $InputObject | ConvertTo-Json
    
    $json | Out-File -FilePath $FilePath -Encoding utf8
}

function getWorkItems {
    param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$PROJECT_ID="",
    [String]$PROJECT_NAME="",
    [String]$QUERY=""
    )
    $header = CreateAuthHeader $PAT
    
    $body = @{
            query = "Select * From WorkItems WHERE [System.TeamProject] = '"+$PROJECT_NAME+"' AND [System.Id] IN ($QUERY) order by [System.Id] asc"
            } | ConvertTo-Json
    $UriApi = $ORGANIZATION_URL+"/"+$PROJECT_ID+ "/_apis/wit/wiql?api-version=5.0"
    $res = Invoke-RestMethod -Uri $UriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body

    return $res.workItems
}
