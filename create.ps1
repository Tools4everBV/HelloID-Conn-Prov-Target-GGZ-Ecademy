#####################################################
# HelloID-Conn-Prov-Target-GGZ-Ecademy-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    externalId          = $p.ExternalId
    surname             = $p.Name.FamilyName
    surnamePrefix       = $p.Name.FamilyNamePartnerPrefix
    givenName           = $p.Name.GivenName
    ltiId               = ''
    initials            = $p.Name.Initials
    externalEmail       = $p.Contact.Business.Email
    dateOfBirth         = $p.Details.BirthDate
    # user                = @{
    #     username = $p.UserName
    # } # It is not possible to update this field.
    externalEngagements = @(
        @{
            dateStart  = $p.PrimaryContract.StartDate
            dateEnd    = $p.PrimaryContract.enddate
            externalId = $p.PrimaryContract.ExternalId
            traits     = @(
                @{
                    traitKey   = 'Manager'
                    traitValue = "$($m.DisplayName)"  # Null is not allowed, use empty string instead.
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

# Set to true if accounts in the target system must be updated
# Please note that this action will triggers a basic update and replace the corresponding account in GGZ with the account properties contained
# in the account object, which might override current Engagements.
$updatePerson = $false

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
#endregion

# Begin
try {
    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    $action = 'Correlate'
    $accessToken = (Get-GGZEcademyToken )

    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Accept', 'application/ld+json')
    $headers.Add('Content-Type', 'application/ld+json')
    $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")

    try {
        $splatRestParams = @{
            Uri     = "$($config.BaseUrl)/api/external_identities/$($account.externalId)"
            Method  = 'GET'
            Headers = $headers
        }
        $responseUser = Invoke-RestMethod @splatRestParams -Verbose:$false
        if ($updatePerson -eq $true) {
            $action = 'Update-Correlate'
        }
    } catch {
        $errorObj = Resolve-GGZ-EcademyError -ErrorObject $_
        if ($errorObj.FriendlyMessage -eq 'Not Found') {
            $action = 'Create-Correlate'
        } else {
            throw $_
        }
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action GGZ-Ecademy account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating GGZ-Ecademy account'
                $splatRestParams = @{
                    Uri     = "$($config.BaseUrl)/api/external_identities"
                    Method  = 'POST'
                    Body    = $account | ConvertTo-Json -Depth 10
                    Headers = $headers
                }
                $resultUser = Invoke-RestMethod @splatRestParams -Verbose:$false
                $aRef = [PSCustomObject]@{
                    ExternalId            = $resultUser.externalID
                    externalEngagementIds = $account.externalEngagements.externalId
                }
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating GGZ-Ecademy account'
                $splatRestParams = @{
                    Uri     = "$($config.BaseUrl)/api/external_identities/$($responseUser.externalId)"
                    Method  = 'PUT'
                    Body    = $account | ConvertTo-Json -Depth 10
                    Headers = $headers
                }
                $resultUser = Invoke-RestMethod @splatRestParams -Verbose:$false
                $aRef = [PSCustomObject]@{
                    ExternalId            = $responseUser.externalId
                    externalEngagementIds = $account.externalEngagements.externalId
                }
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating GGZ-Ecademy account'
                $aRef = [PSCustomObject]@{
                    ExternalId            = $responseUser.externalId
                    externalEngagementIds = $account.externalEngagements.externalId
                }
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$($aRef.ExternalId)]"
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-GGZ-EcademyError -ErrorObject $ex
        $auditMessage = "Could not $action GGZ-Ecademy account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action GGZ-Ecademy account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
