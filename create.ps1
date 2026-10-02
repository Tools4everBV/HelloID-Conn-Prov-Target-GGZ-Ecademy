#################################################
# HelloID-Conn-Prov-Target-GGZ-Ecademy-Create
# PowerShell V2
#################################################

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
        Invoke-RestMethod @splatRestParams
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-GGZEcademyError {
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

function Get-TraitValue {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    return $Value
}

function ConvertTo-GGZAccountObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]
        $Data
    )

    return [PSCustomObject]@{
        externalId          = $Data.externalId
        surname             = $Data.surname
        surnamePrefix       = $Data.surnamePrefix
        givenName           = $Data.givenName
        ltiId               = $Data.ltiId
        initials            = $Data.initials
        externalEmail       = $Data.externalEmail
        dateOfBirth         = $Data.dateOfBirth

        externalEngagements = @(
            [PSCustomObject]@{
                dateStart  = $Data.externalEngagementStartDate
                dateEnd    = $Data.externalEngagementEndDate
                externalId = $Data.externalEngagementExternalId

                traits     = @(
                    [PSCustomObject]@{
                        traitKey   = 'Manager'
                        traitValue = Get-TraitValue $Data.externalEngagementTraitManager
                    }
                    [PSCustomObject]@{
                        traitKey   = 'Kostenplaatscode'
                        traitValue = Get-TraitValue $Data.externalEngagementTraitKostenplaatscode
                    }
                    [PSCustomObject]@{
                        traitKey   = 'Kostenplaatsomschrijving'
                        traitValue = Get-TraitValue $Data.externalEngagementTraitKostenplaatsomschrijving
                    }
                    [PSCustomObject]@{
                        traitKey   = 'Functie'
                        traitValue = Get-TraitValue $Data.externalEngagementTraitFunctie
                    }
                )
            }
        )

        org                 = $actionContext.Data.org
    }
}

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]
        $Data
    )

    $engagement = $Data.externalEngagements | Select-Object -First 1

    return [PSCustomObject]@{
        externalId                                      = $Data.externalId
        surname                                         = $Data.surname
        surnamePrefix                                   = $Data.surnamePrefix
        givenName                                       = $Data.givenName
        ltiId                                           = $Data.ltiId
        initials                                        = $Data.initials
        dateOfBirth                                     = $Data.dateOfBirth
        externalEmail                                   = $Data.externalEmail

        externalEngagementTraitManager                  = Get-TraitValue $engagement.traits | Where-Object traitKey -eq 'Manager' | Select-Object -ExpandProperty traitValue
        externalEngagementTraitKostenplaatscode         = Get-TraitValue $engagement.traits | Where-Object traitKey -eq 'Kostenplaatscode' | Select-Object -ExpandProperty traitValue
        externalEngagementTraitFunctie                  = Get-TraitValue $engagement.traits | Where-Object traitKey -eq 'Functie' | Select-Object -ExpandProperty traitValue
        externalEngagementTraitKostenplaatsomschrijving = Get-TraitValue $engagement.traits | Where-Object traitKey -eq 'Kostenplaatsomschrijving' | Select-Object -ExpandProperty traitValue

        externalEngagementStartDate                     = $engagement.dateStart
        externalEngagementEndDate                       = $engagement.dateEnd
        externalEngagementExternalId                    = $engagement.externalId

        org                                             = $Data.org
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $accessToken = Get-GGZEcademyToken
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Accept', 'application/ld+json')
    $headers.Add('Content-Type', 'application/ld+json')
    $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a GGZ-Ecademy account exists where $correlationField is: [$correlationValue]"
        try {
            $splatRestParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/external_identities/$($correlationValue)"
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
    }

    if ($null -eq $correlatedAccount) {
        $lifecycleProcess = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }
    else {
        $lifecycleProcess = 'CorrelateAccount'
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            $splatRestParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/external_identities"
                Method  = 'POST'
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating GGZ-Ecademy account'
                $ggzAccount = $actionContext.Data | ConvertTo-GGZAccountObject
                $splatRestParams.Body = $ggzAccount | ConvertTo-Json -Depth 10
                $createdAccount = Invoke-RestMethod @splatRestParams
                $outputContext.Data = $createdAccount | ConvertTo-HelloIDAccountObject
                $outputContext.AccountReference = $createdAccount.externalID
            }
            else {
                Write-Information '[DryRun] Create and correlate GGZ-Ecademy account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating GGZ-Ecademy account'
            $correlatedAccount.PSObject.Properties.Remove('externalEngagements')
            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.externalId
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-GGZEcademyError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}