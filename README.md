
# HelloID-Conn-Prov-Target-GGZ-Ecademy


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://ggzecademy.nl/web/themes/ggzecademy/img/logo-new.svg"
  width="500">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-GGZ-Ecademy](#helloid-conn-prov-target-ggz-ecademy)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
      - [Creation / correlation process](#creation--correlation-process)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-GGZ-Ecademy_ is a _target_ connector. GGZ-Ecademy provides a set of REST API's that allow you to programmatically interact with its data.


The following lifecycle events are available:

| Event  | Description | Notes |
|---	 |---	|---	|
| create.ps1 | Create (or update) and correlate an Account | - |
| update.ps1 | Update the Account | - |
| delete.ps1 | Delete the Account | - |
| enable.ps1 | Not available / Not supported by the API | - |
| disable.ps1 |  Not available / Not supported by the API | - |
| Permissions.ps1 |  Not available / Not supported by the API | - |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting            | Description                            | Mandatory |
| ------------------ | -------------------------------------- | --------- |
| ClientId           | The ClientId to connect to the API     | Yes       |
| ClientSecret       | The ClientSecret to connect to the API | Yes       |
| BaseUrl            | The URL to the API                     | Yes       |
| Organization [Org] | The company's organization code        | Yes       |

### Prerequisites
- The credentials to authenticate the API connection (see: Connection Settings)


### Remarks
- Due to some uncertainties regarding the design of the connector, some assumptions were made, upon which the account object is based. This means that the current code may not work directly in every environment. The actual design will have to be determined during the first implementation.
- Presently, ExternalEngagements are linked to a primary contract, allowing each account to have only one ExternalEngagement. However, the API has the capability to support multiple ExternalEngagements if required. If necessary, the existing code can be modified accordingly.
- The current ExternalEngagements for a GGZ-Ecademy user account remain unaltered, with updates being solely applied to the ExternalEngagements that are matched with the ExternalEngagements in the account object.
- The same applies for the traits within the ExternalEngagements. The connector only updates existing or adding new Traits, while the remaining traits shall be retained without any modification.
- The externalId associated with an ExternalEngagement is stored in the account reference, which is then utilized to disable the previous engagement and set its end date after a change of the primary contract.
- It is not possible to set or update the Username attribute of a GGZ-Ecademy account.
- The API's datetime values caused inconsistent comparisons, so a function `Format-GGZDateObject` was added to extract only the date portion for property comparison, though regional differences between the original code and your implementation may necessitate adjustments to this function.
- When updating an existing trait, it is not possible for its values to be null. Attempting to do so will result in an exception being thrown. To clear a trait, you should use an empty string instead.

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the `create.ps1` by setting the boolean `$updatePerson` to the value of `$true`.

> Be aware that this might have unexpected implications. The Update trigger in the `create.ps1` file performs a basic update and does not take into consideration the current account's pre-existing traits and engagements. Consequently, any pre-existing properties will be replaced.

## Setup the connector
There is no comprehensive configuration required.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _More information about the GGZ-Ecademy API can be found here: [API Docs](https://portaal.ggzecademy.nl/api/docs)_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1318-helloid-conn-prov-target-ggz-ecademy)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
