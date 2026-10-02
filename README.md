# HelloID-Conn-Prov-Target-GGZ-Ecademy

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

>[!WARNING]
>This connector has been updated to meet the requirements of a PowerShell V2 target connector.
>The update was dry-coded and could not be tested in a working environment.
>We recommend thoroughly testing and validating the connector during implementation, as the code may require adjustments.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-GGZ-Ecademy](#helloid-conn-prov-target-ggz-ecademy)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [externalEngagements / traits](#externalengagements--traits)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-GGZ-Ecademy_ is a _target_ connector. _GGZ-Ecademy_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks           |
| ----------------------------------------- | --------- | --------------------------------------- | ----------------- |
| **Account Lifecycle**                     | ✅         | Create, Delete, Update |                   |
| **Permissions**                           | ❌         | -                | - |
| **Resources**                             | ❌         | -                                       |                   |
| **Entitlement Import: Accounts**          | ❌         | -                                       |                   |
| **Entitlement Import: Permissions**       | ❌         | -                                       |                   |
| **Governance Reconciliation Resolutions** | ✅       | -                                       |                   |

<!--
Example
### ⚠️ Governance Reconciliation Resolutions
Governance reconciliation is supported for reporting purposes.
Resolutions are not possible because...
-->

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-GGZ-Ecademy/refs/heads/main/Icon.png
```

### Requirements

<!--
Describe the specific requirements that must be met before using this connector, such as the need for an agent, a certificate or IP whitelisting.

**Please ensure to list the requirements using bullet points for clarity.**

Example:

- **SSL Certificate**:<br>
  A valid SSL certificate must be installed on the server to ensure secure communication. The certificate should be trusted by a recognized Certificate Authority (CA) and must not be self-signed.
- **IP Whitelisting**:<br>
  The IP addresses used by the connector must be whitelisted on the target system's firewall to allow access. Ensure that the firewall rules are configured to permit incoming and outgoing connections from these IPs.
-->

### Connection settings

The following settings are required to connect to the API.

| Setting            | Description                            | Mandatory |
| ------------------ | -------------------------------------- | --------- |
| ClientId           | The ClientId to connect to the API     | Yes       |
| ClientSecret       | The ClientSecret to connect to the API | Yes       |
| BaseUrl            | The URL to the API                     | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _GGZ-Ecademy_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `externalId`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

**The Organization field is required in the field mapping.**

### Account Reference

The account reference is populated with the property `externalId` property from _GGZ-Ecademy_.

## Remarks

### externalEngagements / traits

Because a test environment was not available for the V1-to-V2 conversion, the `externalEngagements` and `traits` functionality, including the custom compare logic, has been dry-coded but has not yet been tested in an environment.

The following functionality has been implemented but still requires validation:

- Create an `externalEngagement` for each contract.
- Populate the start and end dates.
- Populate the `externalId` with the contract (sequence) number.
- Populate the `traits` array with the function and cost center/department information.
- Compare `externalEngagements` and their nested `traits` to determine whether an update is required.
- Currently only the active engagement (from HelloID) is being send / updated in GGZ-Ecademy. Meaning; engagements in GGZ are left unmodified.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint | HTTP Method      | Description                                  |
| -------- | ---------------- | -------------------------------------------- |
| /api/external_identities   | GET, POST, PUT, DELETE | Retrieve, Create and update user information |

### API documentation

The API documentation is available on: https://next.ggzecademy.nl/api/docs#/

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
