param(
    [String]$PAT="",
    [String]$PROJECT_NAME="",
    [String]$ORGANIZATION_URL=""
)

# Iterate all child of child dirs
function check_children($parent) {
    $total_shared_queries = 0
    foreach ($child in $parent){
        if (!$child.isFolder){
            $total_shared_queries++
        }
        elseif ($child.isFolder){
            foreach ($double_child in $child.children){
                if (!$double_child.isFolder){
                    $total_shared_queries++
                }
                elseif ($double_child.isFolder){
                    # Create a new API and search for the query ID with a new depth=2 to find more children of the path
                    $second_uriApi = $ORGANIZATION_URL+ "/" + $PROJECT_NAME + "/_apis/wit/queries/" + $double_child.id  + "?`$depth=2&api-version=5.0"
                    $second_res = Invoke-RestMethod -Uri $second_uriApi -Method Get -Headers $header -ContentType "application/json"

                    foreach ($tripple_child in $second_res.children){                    
                        if (!$tripple_child.isFolder){
                            $total_shared_queries++                   
                        }
                        elseif ($double_child.isFolder){
                            foreach ($quad_child in $tripple_child.children){
                                if (!$quad_child.isFolder){
                                    $total_shared_queries++
                                }
                            }
                        }
                    }
                }
            }
        }   
    }
    return $total_shared_queries
}
. .\Helpers.ps1

# Http request

$header = CreateAuthHeader $PAT
$uriApi = $ORGANIZATION_URL+ "/" + $PROJECT_NAME + "/_apis/wit/queries?`$depth=2&api-version=5.0"
$res = Invoke-RestMethod -Uri $uriApi -Method Get -Headers $header -ContentType "application/json"

$total_shared_queries = 0
foreach ($children in $res.value){
    if ($children.name -eq "Shared Queries"){
        foreach ($queries in $children.children){
            $queries_from_children = check_children($queries)
            $total_shared_queries = $total_shared_queries + $queries_from_children 
        }
    }
}

return $total_shared_queries
