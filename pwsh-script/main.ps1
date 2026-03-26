param(
    [String]$PAT="",
    [String]$ORGANIZATION_URL="",
    [String]$ORGANIZATION_Name="",
    [String]$CSVFILENAME="",
    [Boolean]$ONPREM=$false
)

function AddingMembers
{ 
    $add_project | Add-Member -Name "Project Updated" -Type NoteProperty -Value ([DateTime]$project.lastUpdateTime).ToString('yyyy-MM-dd')
#   $add_project | Add-Member -Name "Project Admins" -Type NoteProperty -Value $adminsjoined
    $add_project | Add-Member -Name "Work items" -Type NoteProperty -Value $list_workitems.id.Count
    $add_project | Add-Member -Name "Work item updated" -Type NoteProperty -Value $work_item_date
    $add_project | Add-Member -Name "Over 50 revisions" -Type NoteProperty -Value $rev50
    $add_project | Add-Member -Name "Over 100 revisions" -Type NoteProperty -Value $rev100
    $add_project | Add-Member -Name "Repos" -Type NoteProperty -Value $list_repos.id.Count
    $add_project | Add-Member -Name "Latest push" -Type NoteProperty -Value $latest_push
    $add_project | Add-Member -Name "Latest tfvc check in" -Type NoteProperty -Value $latest_tfvc
    $add_project | Add-Member -Name "Pipelines" -Type NoteProperty -Value $list_pipelines.id.Count
    $add_project | Add-Member -Name "Latest run" -Type NoteProperty -Value $pipeline_run
    $add_project | Add-Member -Name "Releases" -Type NoteProperty -Value $list_releases.id.Count
    $add_project | Add-Member -Name "Latest release" -Type NoteProperty -Value $release_date
    #$add_project | Add-Member -Name "Test plans" -Type NoteProperty -Value $tps.count
    $add_project | Add-Member -Name "Test suites" -Type NoteProperty -Value $testSuites
    $add_project | Add-Member -Name "Shared Steps" -Type NoteProperty -Value $sharedSteps
    $add_project | Add-Member -Name "Shared Parameter" -Type NoteProperty -Value $sharedParameter
    $add_project | Add-Member -Name "Variable Groups" -Type NoteProperty -Value $vg.value.Count
    $add_project | Add-Member -Name "Task groups" -Type NoteProperty -Value $tgs.count
    $add_project | Add-Member -Name "Dashboards" -Type NoteProperty -Value $list_dashboards.count
    $add_project | Add-Member -Name "Wikis" -Type NoteProperty -Value $wikisType
    $add_project | Add-Member -Name "Teams" -Type NoteProperty -Value $get_teams.count
    $add_project | Add-Member -Name "Queries" -Type NoteProperty -Value $get_queries
    $add_project | Add-Member -Name "Project Feeds" -Type NoteProperty -Value $feeds.count
    $add_project | Add-Member -Name "Org feeds" -Type NoteProperty -Value $get_org_feeds
    $add_project | Add-Member -Name "Deployment groups" -Type NoteProperty -Value $list_deployment_groups
    $add_project | Add-Member -Name "Process" -Type NoteProperty -Value $list_process
    if($ONPREM -ne $true){
        $add_project | Add-Member -Name "GH connection" -Type NoteProperty -Value $list_GH_connection
    }
}

$list_projects = .\list-projects.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL
$i = 0
$project_collection = @()
#$groups = .\get-groups.ps1 -PAT $PAT -ORGANIZATION_Name $ORGANIZATION_Name

foreach($project in $list_projects){
    Write-Output ("project: " + $project.name +" "+ $i + "/"+$list_projects.length)
    $i++
    $list_repos = .\list-repos.ps1 -Pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $list_pipelines = .\list_pipelines.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -ONPREM $ONPREM
    $list_workitems = .\wiql-all-work-items.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -PROJECT_ID $project.id
    $get_revs = .\get-revisioncount.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -PROJECT_ID $project.id
    $pipeline = .\build.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $list_releases = .\releases.ps1 -PAT $PAT -ORGANIZATION_Name $ORGANIZATION_Name -PROJECT_NAME $project.name -ORGANIZATION_URL $ORGANIZATION_URL -ONPREM $ONPREM
    #$tps = .\list-testplans.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $test_suite = .\get-test-suites.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -PROJECT_ID $project.id
    $shared_steps = .\get-shared-steps.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -PROJECT_ID $project.id
    $feeds = .\get-feeds.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -ORGANIZATION_Name $ORGANIZATION_Name -PROJECT_NAME $project.name -ONPREM $ONPREM
    $vg = .\variable-groups.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $tgs = .\task-groups.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $list_dashboards = .\get-dashboards.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $tfvc = .\get-latest-tfvc.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $get_wikis = .\get_wiki.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $get_org_feeds = .\get_org_feeds.ps1 -pat $PAT -ORGANIZATION_Name $ORGANIZATION_Name -ORGANIZATION_URL $ORGANIZATION_URL -ONPREM $ONPREM
    $get_teams = .\get_teams.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_ID $project.id
    $get_queries = .\get_queries.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    $list_process = .\list_process.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_ID $project.id
    $list_deployment_groups = .\list_deployment_groups.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    if($ONPREM -ne $true){
        $list_GH_connection = .\list-service-connections.ps1 -pat $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -PROJECT_ID $project.id
    }
#    $admins = .\get-projadmin.ps1 -PAT $PAT -ORGANIZATION_Name $ORGANIZATION_Name -PROJECT_NAME $project.name
#    $adminsjoined = $admins -join ","
#    Write-Output $adminsjoined

    if ($null -ne $list_workitems.id) {
        $work_item_date = .\wiql_last_change.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name
    }
    else{
        $work_item_date = '0'
    }
    if ($null -ne $pipeline){
        $pipeline_date = $pipeline | Sort-Object | select -last 1
        $pipeline_run = ([DateTime]$pipeline_date).ToString('yyyy-MM-dd')
    }
    else{
        $pipeline_run = 'No runs'
    }
    if ($null -ne $list_releases.id){
        $release = $list_releases.modifiedOn | Sort-Object | select -last 1
        $release_date = ([DateTime]$release).ToString('yyyy-MM-dd')
    }
    else{
        $release_date = '0'
    }

    if ($null -eq $list_GH_connection){
        $list_GH_connection = "No GH connection"
    }
    else{
        $string = $list_GH_connection -join ","
        $list_GH_connection = $string
    }
    
    $arr = @()
    foreach($repo in $list_repos){
        $repo_push = .\latest-push.ps1 -PAT $PAT -ORGANIZATION_URL $ORGANIZATION_URL -PROJECT_NAME $project.name -REPO_ID $repo.id
        $arr += $repo_push.date
    }

    $last = $arr | Sort-Object | select -last 1
    if($last -eq $null){
        $latest_push = "No pushes"
    }
    else{
    $latest_push = ([DateTime]$last).ToString('yyyy-MM-dd')
    }

    if($null -ne $tfvc){
        $last_tfvc = $tfvc.createdDate | Sort-Object | select -last 1
        $latest_tfvc = ([DateTime]$last_tfvc).ToString('yyyy-MM-dd')
    }
    else{
        $latest_tfvc = "No tfvc"
    }
    # Check if there is a wikiType of "projectWiki" 
    $wikisType = "No"
    foreach ($wiki in $get_wikis){
        if($wiki.type -eq "projectWiki"){
            $wikisType = "Yes"
        }
    }
    $sharedSteps = $shared_steps.resultSteps
    $sharedParameter = $shared_steps.resultParameter
    $testSuites = $test_suite
    $rev50 = $get_revs.Result50
    $rev100 = $get_revs.Result100
    
    $add_project = New-Object -TypeName psobject -Property @{Project = $project.name}
    AddingMembers
    $project_collection += $add_project
}


$project_collection | Export-Csv -NoTypeInformation ('.\'+$CSVFILENAME+'.csv') -Append -Encoding UTF8
