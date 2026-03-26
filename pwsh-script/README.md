## Parameters to run main.ps1
 - "$PAT" | Your personal access token on azure devops
 - "$ORGANIZATION_URL" | Your organization url, ex `https://dev.azure.com/exampleorg`
 - "$ORGANIZATION_Name" | The name of your organization, ex "exampleorg"
 - "$CSVFILENAME" | The name of the csv file the script creates
 - "$ONPREM" | is Azure DevOps on prem(server) or not(sevices)

## How to run script
```
PS > ./main.ps1 -PAT <azure-devops-personal-access-token> -ORGANIZATION_URL https://dev.azure.com/exampleorg -ORGANIZATION_Name exampleorg -CSVFILENAME csvfile -ONPREM $true
```
