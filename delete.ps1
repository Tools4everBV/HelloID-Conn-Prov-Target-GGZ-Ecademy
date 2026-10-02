##################################################
# HelloID-Conn-Prov-Target-GGZ-Ecademy-Delete
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-GGZEcademyToken {
    [CmdletBinding()]
    param()
    try {
        $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($($actionContext.Configuration.ClientId) + ':' + $($actionContext.Configuration.ClientSecret)))
        $headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/x-www-form-urlencoded'
            Authorization  = "Basic $base64String"
        }

        $splatRestParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/token"
            Method  = 'POST'
            Body    = 'grant_type=client_credentials'
            Headers = $headers
        }
        Invoke-RestMethod @splatRestParams -Verbose:$false
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
function Resolve-GGZ-EcademyError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $errorObject.Exception.message
            FriendlyMessage  = $errorObject.Exception.message
        }
        if ($ErrorObject.ErrorDetails) {
            $errorExceptionDetails = $ErrorObject.ErrorDetails
        }
        elseif ($ErrorObject.Exception.Response) {
            $result = $ErrorObject.Exception.Response.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($result)
            $errorExceptionDetails = $reader.ReadToEnd()
            $reader.Dispose()
        }

        if (-not [string]::IsNullOrEmpty($errorExceptionDetails)) {
            try {
                $convertedErrorDetails = $errorExceptionDetails | ConvertFrom-Json
                $httpErrorObj.ErrorDetails = $errorExceptionDetails

                switch ($convertedErrorDetails) {
                    { -not [string]::IsNullOrEmpty($_.'hydra:description') } {
                        if ( $_.'hydra:description' -eq 'Call to a member function getRoleNames() on null') {
                            $httpErrorObj.FriendlyMessage = "Possibly incorrect authorization credentials: $($_.'hydra:description')"
                            $httpErrorObj.ErrorDetails = "Possibly incorrect authorization credentials: $($_.'hydra:description')"
                        }
                        else {
                            $httpErrorObj.FriendlyMessage = $_.'hydra:description'
                            $httpErrorObj.ErrorDetails = $_.'hydra:description'
                        }
                        break
                    }
                    { -not [string]::IsNullOrEmpty($_.error_description) } {
                        $httpErrorObj.FriendlyMessage = $_.error_description
                        $httpErrorObj.ErrorDetails = $_.error_description
                        break
                    }
                }
            }
            catch {
                $httpErrorObj.FriendlyMessage = $convertedErrorDetails
                $httpErrorObj.ErrorDetails = $convertedErrorDetails
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $accessToken = Get-GGZEcademyToken
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Accept', 'application/ld+json')
    $headers.Add('Content-Type', 'application/ld+json')
    $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")

    Write-Information 'Verifying if a GGZ-Ecademy account exists'
    try {
        $splatRestParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/external_identities/$($actionContext.References.Account)"
            Method  = 'GET'
            Headers = $headers
        }
        $correlatedAccount = Invoke-RestMethod @splatRestParams
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            $correlatedAccount = $null
        }
        else {
            throw $_
        }
    }

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'DeleteAccount'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DeleteAccount' {
            $splatRestParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/external_identities/$($actionContext.References.Account)"
                Method  = 'DELETE'
                Headers = $headers
            }


            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Deleting GGZ-Ecademy account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatRestParams
            }
            else {
                Write-Information "[DryRun] Delete GGZ-Ecademy account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Delete account: [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "GGZ-Ecademy account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "GGZ-Ecademy account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-GGZ-EcademyError -ErrorObject $ex
        $auditLogMessage = "Could not delete GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not delete GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}