param(
    [String]$PAT="",
    [String]$ORGANIZATION_Name="",
    [String]$PROJECT_NAME =""
    #[String[]]$groups =""
)

. .\Helpers.ps1
$header = CreateAuthHeader $PAT

$groups = .\get-groups.ps1 -PAT $PAT -ORGANIZATION_Name $ORGANIZATION_Name

$adminlist = @()

foreach($group in $groups)
    {
        if($group.principalName -eq '['+$PROJECT_NAME+']\Project Administrators'){
            $groupid = $group.originId
            $uriApi2 = 'https://vsaex.dev.azure.com/'+$ORGANIZATION_Name+'/_apis/GroupEntitlements/'+$groupid+'/members?api-version=6.0-preview.1'
            $admins = Invoke-RestMethod -Uri $uriApi2 -Method Get -Headers $header -ContentType "application/json"
            $adminlist += $admins.members.user.displayName
        }

    }

    return $adminlist

