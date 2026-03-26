function CreateAuthHeader {
    param([string]$PAT)
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}
