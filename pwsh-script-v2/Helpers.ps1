#
# Helpers.ps1 - Centralized helper functions for Azure DevOps inventory scripts
#

# ============================================================================
# AUTHENTICATION
# ============================================================================

function CreateAuthHeader {
    <#
    .SYNOPSIS
        Creates a Basic Auth header for Azure DevOps API calls
    
    .PARAMETER PAT
        Personal Access Token for authentication
    
    .OUTPUTS
        Hashtable with Authorization header
    #>
    param([string]$PAT)
    
    if ([string]::IsNullOrEmpty($PAT)) {
        throw "PAT cannot be empty"
    }
    
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PAT)")) }
}

# ============================================================================
# LOGGING
# ============================================================================

$script:LogFilePath = $null
$script:LogLevel = "INFO"  # DEBUG, INFO, WARN, ERROR

function Initialize-Logger {
    <#
    .SYNOPSIS
        Initialize logging to file and console
    
    .PARAMETER LogFile
        Path to log file (optional)
    
    .PARAMETER LogLevel
        Minimum log level: DEBUG, INFO, WARN, ERROR (default: INFO)
    #>
    param(
        [string]$LogFile = "",
        [string]$LogLevel = "INFO"
    )
    
    $script:LogFilePath = $LogFile
    $script:LogLevel = $LogLevel
    
    if ($LogFile) {
        $logDir = Split-Path $LogFile -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Write log message with timestamp and level
    #>
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [Exception]$Exception = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if ($Exception) {
        $logMessage += "`n  Exception: $($Exception.Message)`n  StackTrace: $($Exception.StackTrace)"
    }
    
    # Console output
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
        "DEBUG"   { Write-Host $logMessage -ForegroundColor Cyan }
        default   { Write-Host $logMessage }
    }
    
    # File output
    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $logMessage -Encoding UTF8
    }
}

function Write-Debug-Log {
    param([string]$Message)
    if ($script:LogLevel -in @("DEBUG")) {
        Write-Log -Message $Message -Level "DEBUG"
    }
}

# ============================================================================
# ERROR HANDLING & RETRY
# ============================================================================

function Invoke-ApiCall {
    <#
    .SYNOPSIS
        Execute Azure DevOps API call with error handling and retry logic
    
    .PARAMETER Uri
        API endpoint URL
    
    .PARAMETER Method
        HTTP method (Get, Post, etc.)
    
    .PARAMETER Headers
        HTTP headers (including auth)
    
    .PARAMETER Body
        Request body for POST/PATCH
    
    .PARAMETER MaxRetries
        Number of retries on transient failures (default: 3)
    
    .PARAMETER RetryDelaySeconds
        Delay between retries in seconds (default: 2)
    
    .OUTPUTS
        API response object or $null on failure
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][hashtable]$Headers,
        [string]$Body = "",
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2,
        [string]$Description = ""
    )
    
    $attempt = 0
    $lastException = $null
    
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-Debug-Log "API Call ($attempt/$MaxRetries): $Method $Uri"
            
            if ($Description) {
                Write-Debug-Log "Description: $Description"
            }
            
            $params = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $Headers
                ContentType = "application/json;charset=utf-8"
            }
            
            if ($Body) {
                $params["Body"] = $Body
            }
            
            # Capture response headers for continuation tokens
            $responseHeaders = $null
            $response = Invoke-RestMethod @params -ResponseHeadersVariable responseHeaders
            Write-Debug-Log "Success: Received $($response.value.Count ?? 1) items"
            
            return @{ Body = $response; Headers = $responseHeaders }
        }
        catch [System.Net.WebException] {
            $lastException = $_
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $_.Exception.Response.StatusCode }
            
            # Handle 404 gracefully for TFVC or missing endpoints
            if ($statusCode -eq 404 -or $Uri -match '/_apis/tfvc/') {
                Write-Log "Resource not found or TFVC not enabled (HTTP $statusCode): $Uri" -Level "DEBUG" -Exception $_.Exception
                return $null
            }
            
            # Determine if retryable
            $retryable = $statusCode -in @(408, 429, 500, 502, 503, 504)
            
            if ($retryable -and $attempt -lt $MaxRetries) {
                $delay = $RetryDelaySeconds * $attempt  # Exponential backoff
                Write-Log "Retryable error (HTTP $statusCode). Retrying in ${delay}s..." -Level "WARN"
                Start-Sleep -Seconds $delay
                continue
            }
            else {
                Write-Log "API Call Failed (HTTP $statusCode): $Uri" -Level "ERROR" -Exception $_.Exception
                return $null
            }
        }
        catch {
            # Check if this is a 404 or TFVC-related error before logging as ERROR
            $statusCode = $null
            $uri = $null
            try {
                if ($_.Exception -is [System.Net.WebException]) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                    $uri = $_.Exception.Response.ResponseUri
                }
            }
            catch { }
            
            # 404 or TFVC errors are expected, not critical
            if ($statusCode -eq 404 -or $Uri -match '/_apis/tfvc/') {
                Write-Log "Resource not found or TFVC not enabled (HTTP $statusCode): $Uri" -Level "DEBUG" -Exception $_.Exception
                return $null
            }
            
            Write-Log "API Call Failed: $Uri" -Level "ERROR" -Exception $_.Exception
            return $null
        }
    }
    
    Write-Log "Max retries exceeded for $Uri" -Level "ERROR" -Exception $lastException
    return $null
}

# ============================================================================
# PAGINATION
# ============================================================================

function Invoke-PaginatedApiCall {
    <#
    .SYNOPSIS
        Execute paginated Azure DevOps API call, automatically handling pagination
    
    .PARAMETER Uri
        Base API endpoint URL (without $top/$skip parameters)
    
    .PARAMETER Headers
        HTTP headers (including auth)
    
    .PARAMETER PageSize
        Items per page (default: 200, max: 1000)
    
    .OUTPUTS
        Array of all items across all pages
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][hashtable]$Headers,
        [int]$PageSize = 200,
        [string]$Description = ""
    )
    
    if ($PageSize -gt 1000) {
        $PageSize = 1000
        Write-Log "PageSize capped at 1000" -Level "WARN"
    }
    
    $all_items = @()
    $skip = 0
    $pageNum = 0
    
    do {
        $pageNum++
        # Build URI: support either skip/top or continuationToken
        if ($continuationToken) {
            $paginatedUri = $Uri + "&`$top=$PageSize&continuationToken=$continuationToken"
        }
        else {
            $paginatedUri = $Uri + "&`$top=$PageSize&`$skip=$skip"
        }

        Write-Debug-Log "Fetching page ${pageNum} (skip=$skip, top=$PageSize, token=$continuationToken)"

        $resp = Invoke-ApiCall -Uri $paginatedUri -Method Get -Headers $Headers -Description "$Description (page ${pageNum})"

        if ($null -eq $resp) {
            Write-Log "Failed to fetch page ${pageNum}. Stopping pagination." -Level "WARN"
            break
        }

        $response = $resp.Body
        $responseHeaders = $resp.Headers

        # Check for continuation token in headers (Azure DevOps uses x-ms-continuationtoken)
        $token = $null
        try {
            if ($responseHeaders -and $responseHeaders.ContainsKey('x-ms-continuationtoken')) {
                $token = $responseHeaders['x-ms-continuationtoken']
            }
            elseif ($responseHeaders -and $responseHeaders.ContainsKey('X-MS-CONTINUATIONTOKEN')) {
                $token = $responseHeaders['X-MS-CONTINUATIONTOKEN']
            }
        }
        catch { $token = $null }

        $itemCount = 0
        if ($response -and $response.value) {
            $itemCount = $response.value.Count
        }

        if ($itemCount -gt 0) {
            $all_items += $response.value
            Write-Debug-Log "Page ${pageNum}: Retrieved $itemCount items (total: $($all_items.Count))"
            $skip += $PageSize
        }
        else {
            Write-Debug-Log "Page ${pageNum}: No more items"
            break
        }

        # If a continuation token is present, use it; otherwise fall back to skip/top logic
        if ($token) {
            $continuationToken = $token
            # continue loop; do not rely solely on itemCount
        }
        else {
            $continuationToken = $null
        }

    } while ($itemCount -eq $PageSize -or $continuationToken)

    
    Write-Log "Pagination complete: Retrieved $($all_items.Count) total items" -Level "DEBUG"
    return $all_items
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Format-DateForCsv {
    <#
    .SYNOPSIS
        Convert DateTime to consistent CSV format, handling nulls and invalid types
    
    .PARAMETER Date
        Any date value (can be DateTime, string, or null)
    
    .OUTPUTS
        String in yyyy-MM-dd format or "N/A" if null/invalid
    #>
    param([object]$Date)
    
    if ($null -eq $Date) {
        return "N/A"
    }
    
    # Handle empty strings
    if ($Date -is [string] -and [string]::IsNullOrWhiteSpace($Date)) {
        return "N/A"
    }
    
    try {
        $dateTime = [DateTime]$Date
        return $dateTime.ToString('yyyy-MM-dd')
    }
    catch {
        Write-Debug-Log "Failed to parse date '$Date': $($_.Exception.Message)"
        return "N/A"
    }
}

function Get-LatestDate {
    <#
    .SYNOPSIS
        Get latest date from array, handling nulls and strings gracefully
    
    .PARAMETER Dates
        Array of date values (can be DateTime objects or strings)
    
    .OUTPUTS
        Latest DateTime formatted as string (yyyy-MM-dd) or $null if no valid dates
    #>
    param([array]$Dates)
    
    if ($null -eq $Dates -or $Dates.Count -eq 0) {
        return $null
    }
    
    try {
        $validDates = @()
        foreach ($date in $Dates) {
            if ($null -ne $date) {
                try {
                    $parsedDate = [DateTime]$date
                    $validDates += $parsedDate
                }
                catch {
                    # Skip invalid dates
                    Write-Debug-Log "Skipping invalid date: $date"
                    continue
                }
            }
        }
        
        if ($validDates.Count -eq 0) {
            return $null
        }
        
        $latestDate = $validDates | Sort-Object | Select-Object -Last 1
        return $latestDate.ToString('yyyy-MM-dd')
    }
    catch {
        Write-Debug-Log "Error processing dates: $($_.Exception.Message)"
        return $null
    }
}

function Safe-PropertyAccess {
    <#
    .SYNOPSIS
        Safely access nested properties, returning $null if missing
    #>
    param(
        [object]$Object,
        [string]$PropertyPath,
        [object]$DefaultValue = $null
    )
    
    try {
        $result = $Object
        foreach ($prop in $PropertyPath.Split('.')) {
            $result = $result.$prop
            if ($null -eq $result) {
                return $DefaultValue
            }
        }
        return $result
    }
    catch {
        return $DefaultValue
    }
}

function New-InventoryObject {
    <#
    .SYNOPSIS
        Create typed inventory object with consistent structure
    #>
    param(
        [hashtable]$Properties = @{}
    )
    
    $obj = New-Object PSObject -Property $Properties
    return $obj
}

# ============================================================================
# BATCH OPERATIONS
# ============================================================================

function Export-InventoryCsv {
    <#
    .SYNOPSIS
        Export inventory data to CSV with error handling
    
    .PARAMETER Data
        Array of objects to export
    
    .PARAMETER FilePath
        Output CSV file path
    
    .PARAMETER Append
        Append to existing file or overwrite (default: false)
    #>
    param(
        [Parameter(Mandatory=$true)][array]$Data,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [bool]$Append = $false
    )
    
    try {
        if ($Data.Count -eq 0) {
            Write-Log "No data to export to $FilePath" -Level "WARN"
            return $false
        }
        
        # Ensure directory exists
        $dir = Split-Path $FilePath
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        $Data | Export-Csv -NoTypeInformation -Path $FilePath -Append:$Append -Encoding UTF8
        Write-Log "Exported $($Data.Count) records to $FilePath" -Level "INFO"
        
        return $true
    }
    catch {
        Write-Log "Failed to export to $FilePath" -Level "ERROR" -Exception $_.Exception
        return $false
    }
}
