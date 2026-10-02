#################################################
# HelloID-Conn-Prov-Target-GGZ-Ecademy-Update
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

function ConvertTo-SortedObject {
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $result = [ordered]@{}

            foreach ($key in ($InputObject.Keys | Sort-Object)) {
                $result[$key] = ConvertTo-SortedObject $InputObject[$key]
            }

            [PSCustomObject]$result
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and
            $InputObject -isnot [string]) {
            return @(
                foreach ($item in $InputObject) {
                    ConvertTo-SortedObject $item
                }
            )
        }

        if ($InputObject.PSObject.Properties.Count -gt 0 -and
            $InputObject -isnot [ValueType] -and
            $InputObject -isnot [string]) {

            $result = [ordered]@{}

            foreach ($property in ($InputObject.PSObject.Properties | Sort-Object Name)) {
                $result[$property.Name] = ConvertTo-SortedObject $property.Value
            }

            [PSCustomObject]$result
        }

        return $InputObject
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
        $outputContext.PreviousData = $correlatedAccount | ConvertTo-HelloIDAccountObject
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
        $targetAccount = $actionContext.Data | ConvertTo-GGZAccountObject

        # Compare regular account properties
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($targetAccount.PSObject.Properties)
        }

        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru |
        Where-Object { $_.SideIndicator -eq '=>' }

        # Compare externalEngagements and nested traits
        $engagementPropertiesChanged = [System.Collections.Generic.List[string]]::new()

        foreach ($targetEngagement in @($targetAccount.externalEngagements)) {
            $referenceEngagement = @(
                $correlatedAccount.externalEngagements |
                Where-Object { $_.externalId -eq $targetEngagement.externalId }
            )[0]

            if ($null -eq $referenceEngagement) {
                $engagementPropertiesChanged.Add(
                    "externalEngagements[$($targetEngagement.externalId)]"
                )
                continue
            }

            # Engagement properties
            foreach ($property in @('dateStart', 'dateEnd', 'externalId')) {
                if ($referenceEngagement.$property -ne $targetEngagement.$property) {
                    $engagementPropertiesChanged.Add(
                        "externalEngagements[$($targetEngagement.externalId)].$property"
                    )
                }
            }

            # Engagement traits
            foreach ($targetTrait in @($targetEngagement.traits)) {
                $referenceTrait = @(
                    $referenceEngagement.traits |
                    Where-Object { $_.traitKey -eq $targetTrait.traitKey }
                )[0]

                if ($null -eq $referenceTrait) {
                    $engagementPropertiesChanged.Add(
                        "externalEngagements[$($targetEngagement.externalId)].traits[$($targetTrait.traitKey)]"
                    )
                    continue
                }

                if ($referenceTrait.traitValue -ne $targetTrait.traitValue) {
                    $engagementPropertiesChanged.Add(
                        "externalEngagements[$($targetEngagement.externalId)].traits[$($targetTrait.traitKey)].traitValue"
                    )
                }
            }
        }

        $engagementsChanged = $engagementPropertiesChanged.Count -gt 0

        if ($propertiesChanged -or $engagementsChanged) {

            if ($propertiesChanged) {
                Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
            }

            if ($engagementPropertiesChanged.Count -gt 0) {
                Write-Information "External engagement property(s) required to update: $($engagementPropertiesChanged -join ', ')"
            }

            $lifecycleProcess = 'UpdateAccount'
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            $splatRestParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/external_identities/$($actionContext.References.Account)"
                Method  = 'PUT'
                Headers = $headers
            }
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating GGZ-Ecademy account with accountReference: [$($actionContext.References.Account)]"
                $ggzAccount = $actionContext.Data | ConvertTo-GGZAccountObject
                $splatRestParams.Body = $ggzAccount | ConvertTo-Json -Depth 10
                $null = Invoke-RestMethod @splatRestParams

            }
            else {
                Write-Information "[DryRun] Update GGZ-Ecademy account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $changed = @()
            if ($propertiesChanged) {
                $changed += "Account property(s): [$($propertiesChanged.Name -join ', ')]"
            }

            if ($engagementPropertiesChanged) {
                $changed += "Engagement property(s): [$($engagementPropertiesChanged -join ', ')]"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Update account was successful. $($changed -join ' and ')"
                IsError = $false
            })
            break
        }

        'NoChanges' {
            Write-Information "No changes to GGZ-Ecademy account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating GGZ-Ecademy account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "GGZ-Ecademy account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "GGZ-Ecademy account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-GGZ-EcademyError -ErrorObject $ex
        $auditLogMessage = "Could not update GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update GGZ-Ecademy account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
