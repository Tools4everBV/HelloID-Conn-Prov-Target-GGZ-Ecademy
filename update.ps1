#####################################################
# HelloID-Conn-Prov-Target-GGZ-Ecademy-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

#region HelpFunction
function Format-GGZDateObject {
    [CmdletBinding()]
    param(
        [Parameter(Position = 1, ValueFromPipeline)]
        $datetime
    )
    process {
        try {
            if (-not [string]::IsNullOrEmpty( $datetime)) {
                $output = $datetime.Substring(0, 10)
            } else {
                $output = $null
            }
            Write-Output $output
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
#endregion HelpFunction

# Account mapping
$account = [PSCustomObject]@{
    externalId          = "$($aRef.ExternalId)"
    surname             = $p.Name.FamilyName
    surnamePrefix       = $p.Name.FamilyNamePartnerPrefix
    givenName           = $p.Name.GivenName
    ltiId               = ''
    initials            = $p.Name.Initials
    externalEmail       = $p.Contact.Business.Email
    dateOfBirth         = $p.Details.BirthDate | Format-GGZDateObject
    # user                = @{
    #     username = $p.UserName
    # } # It is not possible to update this field.
    externalEngagements = @(
        @{
            dateStart  = $p.PrimaryContract.StartDate | Format-GGZDateObject
            dateEnd    = $p.PrimaryContract.enddate | Format-GGZDateObject
            externalId = $p.PrimaryContract.ExternalId
            traits     = @(
                @{
                    traitKey   = 'Manager'
                    traitValue = "$($m.DisplayName)" # Null is not allowed, use empty string instead.
                },
                @{
                    traitKey   = 'Kostenplaatscode'
                    traitValue = "$($p.PrimaryContract.CostCenter.Code)"
                },
                @{
                    traitKey   = 'Kostenplaatsomschrijving'
                    traitValue = "$($p.PrimaryContract.CostCenter.Name)"
                },
                @{
                    traitKey   = 'Functie'
                    traitValue = "$($p.PrimaryContract.Title.Name)"
                }
            )
        }
    )
    org                 = "$($config.org)"
}
# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Get-GGZEcademyToken {
    [CmdletBinding()]
    param()
    try {
        Write-Verbose 'Creating authentication header'
        $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($($config.ClientId) + ':' + $($config.ClientSecret)))
        $headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/x-www-form-urlencoded'
            Authorization  = "Basic $base64String"
        }

        $splatRestParams = @{
            Uri     = "$($config.BaseUrl)/token"
            Method  = 'POST'
            Body    = 'grant_type=client_credentials'
            Headers = $headers
        }
        Invoke-RestMethod @splatRestParams -Verbose:$false
    } catch {
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
        } elseif ($ErrorObject.Exception.Response) {
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
                        } else {
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
            } catch {
                $httpErrorObj.FriendlyMessage = $convertedErrorDetails
                $httpErrorObj.ErrorDetails = $convertedErrorDetails
            }
        }
        Write-Output $httpErrorObj
    }
}

function Compare-AccountProperties {
    param(
        $Account,
        $CurrentAccount
    )
    # Format dattime before compare so it matches the Time in the current account object
    $currentAccount.dateOfBirth = $currentAccount.dateOfBirth | Format-GGZDateObject

    $splatCompareProperties = @{
        ReferenceObject  = @($currentAccount.PSObject.Properties | Where-Object { $_.name -notin 'externalEngagements' })
        DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.name -notin 'externalEngagements' })
    }
    Write-Output (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
}

function Compare-EngagementProperties {
    param(
        $CurrentEngagement,
        $Engagement
    )
    # Ensure that the DateTime object is properly formatted before comparison
    $CurrentEngagement.dateStart = $CurrentEngagement.dateStart | Format-GGZDateObject
    $CurrentEngagement.dateEnd = $CurrentEngagement.dateEnd | Format-GGZDateObject

    $splatCompareProperties = @{
        ReferenceObject  = @(([PSCustomObject]$CurrentEngagement).PSObject.Properties | Where-Object { $_.name -notin 'traits' })
        DifferenceObject = @(([PSCustomObject]$Engagement).PSObject.Properties | Where-Object { $_.name -notin 'traits' })
    }
    Write-Output  (Compare-Object @splatCompareProperties -PassThru ).Where({ $_.SideIndicator -eq '=>' })
}
#endregion

# Begin
try {
    Write-Verbose "Verifying if a GGZ-Ecademy account for [$($p.DisplayName)] exists"
    $accessToken = (Get-GGZEcademyToken )

    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Accept', 'application/ld+json')
    $headers.Add('Content-Type', 'application/ld+json')
    $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")

    if ($null -eq $aRef.ExternalId) {
        throw 'No account reference is available'
    }

    $splatRestParams = @{
        Uri     = "$($config.BaseUrl)/api/external_identities/$($aRef.ExternalId)"
        Method  = 'GET'
        Headers = $headers
    }
    try {
        $currentAccount = Invoke-RestMethod @splatRestParams -Verbose:$false
    } catch {
        $errorMessage = Resolve-GGZ-EcademyError -ErrorObject $_
        if ($errorMessage.FriendlyMessage -eq 'Not Found') {
            $currentAccount = $null
        } else {
            throw $_
        }
    }


    # Verify if the account must be updated
    if ($null -eq $currentAccount) {
        $action = 'NotFound'
        $dryRunMessage = "GGZ-Ecademy account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
    } else {
        # Initialize variables
        $action = 'NoChanges'
        $dryRunMessage = 'No changes will be made to the account during enforcement'

        # Compare between the current properties of an GGZ account and the properties desired in the AccountObject.
        $propertiesChanged = Compare-AccountProperties -Account $account -CurrentAccount $CurrentAccount

        # Modify the current account object by updating the altered properties of the account.
        if ($propertiesChanged.count -gt 0) {
            $action = 'Update'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ', ')]"
            foreach ($prop in $propertiesChanged) {
                $currentAccount.$($prop.Name) = $account.$($prop.Name)
            }
        }

        # Verify if any managed engagements stored in the account reference have been updated with new engagements.
        # This situation could arise if the primary contract has changed.
        $previousManagedEngagementIds = $aRef.externalEngagementIds | Where-Object { [string[]]$_ -notin [string[]]$account.externalEngagements.externalid }
        if ($null -ne $previousManagedEngagementIds) {
            $updateAccountReference = $true
            $aRef.externalEngagementIds = $account.externalEngagements.ExternalId

            # If a managed engagement has been modified and is no longer in scope, it will be disabled by specifying an end date.
            foreach ($engagementId in $previousManagedEngagementIds) {
                Write-Verbose "Previous externalEngagement [$engagementId] out of scope, will end the engagement"
                $currentAccount.externalEngagements | Where-Object { $_.externalId -eq $engagementId } | ForEach-Object { $_.dateEnd = (Get-Date -f 'yyyy-MM-dd') }
            }
        }

        # Compare the externalEngagements within the account object with the current engagements stored in the GGZ account.
        # Update the current account object with the required changes
        foreach ($engagement in $account.externalEngagements) {
            $currentEngagement = $currentAccount.externalEngagements | Where-Object { $_.externalId -eq $engagement.externalId }
            if ($currentEngagement.Count -gt 1) {
                throw "Multiple external engagements were found with the same externalID [$($engagement.externalId)]. Processing the engagement is not possible at this time."
            }

            if ($null -eq $currentEngagement ) {
                Write-Verbose "New externalEngagements with external ID  [$($engagement.externalId)]"
                $currentAccount.externalEngagements += $engagement
                $action = 'Update'

            } else {
                Write-Verbose "Existing ExternalEngagements found with externalID  [$($engagement.externalId)]"

                # Compare the current properties of the engegement against desired engegement(s) in account object
                $propertiesEngagementChanged = Compare-EngagementProperties -CurrentEngagement $currentEngagement -Engagement $Engagement

                # Update Changed Engagement Properties
                if ( $propertiesEngagementChanged.count -gt 0 ) {
                    Write-Verbose "ExternalEngagement [$($engagement.externalId)] need a update [$($propertiesEngagementChanged.name -join ', ')]"
                    foreach ($prop  in $propertiesEngagementChanged ) {
                        $currentEngagement."$($prop.Name)" = $account.externalEngagements."$($prop.Name)"
                    }
                    $action = 'Update'
                }

                # Compare between the traits in the current engagement and the traits listed in the account object,
                # and then update the engagement traits accordingly.
                foreach ($trait in  $engagement.traits) {
                    $currentTrait = $currentEngagement.traits | Where-Object traitKey -EQ $trait.traitKey

                    if ($currentTrait -and $trait.traitValue -ne $currentTrait.traitValue) {
                        Write-Verbose  "Trait [$($trait.traitKey)] requires an Update [$($currentTrait.traitValue)] => [$($trait.traitValue)]"
                        $currentTrait.traitValue = $trait.traitValue
                        $action = 'Update'

                    } elseif (-not $currentTrait) {
                        Write-Verbose  "New trait found [Key: $($trait.traitKey)] [Value: $($trait.traitValue)]"
                        $currentEngagement.traits += [PSCustomObject]$trait
                        $action = 'Update'
                    }
                }
            }
        }
    }

    if ($action -eq 'NoChanges') {
        Write-Verbose "$dryRunMessage"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating GGZ-Ecademy account with accountReference: [$($aRef.ExternalId)]"

                $splatRestParams = @{
                    Uri     = "$($config.BaseUrl)/api/external_identities/$($aRef.ExternalId)"
                    Method  = 'PUT'
                    Body    = $currentAccount | ConvertTo-Json -Depth 10
                    Headers = $headers
                }
                $null = Invoke-RestMethod @splatRestParams -Verbose:$false

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful. AccountReference: [$($aRef.ExternalId)]"
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to GGZ-Ecademy account with accountReference: [$($aRef.ExternalId)]"
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful. AccountReference: [$($aRef.ExternalId)] No Changes"
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $success = $false
                $auditLogs.Add([PSCustomObject]@{
                        Message = "GGZ-Ecademy account for: [$($p.DisplayName)] not found. Possibly deleted"
                        IsError = $true
                    })
                break
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-GGZ-EcademyError -ErrorObject $ex
        $auditMessage = "Could not update GGZ-Ecademy account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update GGZ-Ecademy account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }

    if ($updateAccountReference) {
        $result | Add-Member -NotePropertyMembers @{
            AccountReference = $aRef
        }
    }

    Write-Output $result | ConvertTo-Json -Depth 10
}
