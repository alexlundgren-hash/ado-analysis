
param(
[String]$PAT="",
[String]$ORGANIZATION_URL="",
[String]$PROJECT_NAME="",
[String]$PROJECT_ID=""
)

. .\Helpers.ps1
. .\wiql_query_helper.ps1

function CreateAuthHeader {
    param([string]$PAT)
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}

# Http request
$header = CreateAuthHeader $PAT

$body = @{
query = "Select * From WorkItems WHERE [System.TeamProject] = '"+$PROJECT_NAME+"' order by [System.ChangedDate] desc"
} | ConvertTo-Json

$uriApi = $ORGANIZATION_URL+"/"+$PROJECT_ID+ "/_apis/wit/wiql?api-version=7.0"


try {
    $res = Invoke-RestMethod -Uri $uriApi -Method POST -Headers $header -ContentType "application/json;charset=utf-8" -BODY $body
    return $res.workItems
}
catch [System.Net.WebException] {
    
        $firstWorkItem = getFirstWorkItem $PAT $ORGANIZATION_URL $PROJECT_ID $PROJECT_NAME
        $lastWorkItem = getLastWorkItem $PAT $ORGANIZATION_URL $PROJECT_ID $PROJECT_NAME
        $totalWorkItems = $lastWorkItem.Id - $firstWorkItem.Id
        $list = @()
        $start_number = $firstWorkItem.Id

        # The interval is the max characters per query
        $interval = 2800
        $numberOfQueries = [math]::Ceiling($totalWorkItems / $interval)
        $actualWorkItems = @()
        for ($i=1; $i -le $numberOfQueries; $i++) { #5x

            for ($query=$start_number; $query -le ($start_number+$interval-1); $query++) {
                
                if ($query -eq ($start_number+$interval-1)) {
                    $start_number = ($start_number+$interval)
                    
                    $list += $query
                    break
                }
                else{
                    $list += "$query,"
                }
                if ($query -eq $lastWorkItem){
                    break
                }
            }
            
            [array]$res = @()
            $res = getWorkItems $PAT $ORGANIZATION_URL $PROJECT_ID $PROJECT_NAME $list
            
            if ($actualWorkItems.count -eq 0){
                $actualWorkItems = $res
            } 
            else{
                $actualWorkItems += $res
            }
            $list = @()
        }
        #Write-Host $actualWorkItems.count

        #ConvertTo-JsonFile $actualWorkItems "actualWorkItems.json"
        
}
return $actualWorkItems
