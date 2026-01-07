# BIG-IP APM OAuth Auth Server Client Credentials Grant Demo

This repository contains proof of concept code to configure BIG-IP APM as an OAuth Authorization Server (AS) that issues
access tokens that are functionally-compatible with Okta's client credentials authentication flow.

Most importantly, it demonstrates how to export existing client credentials from Okta, import them into APM, and
provides an iRule that can detect when users present an Okta-formatted client ID and convert it to BIG-IP format
prior to processing by APM.

Expect bugs; this is not production-quality code.
The code currently assumes everything is in `/Common`, and that it has been given a fresh BIG-IP with no
other LTM or APM configuration.

## Setup

The recommended setup is to create a Python virtual environment, and then install Ansible in it using the included
`requirements.txt` file.

Once Ansible is installed, install required collections using `requirements.yaml`:

```bash
ansible-galaxy install -r requirements.yaml
```

This code was developed with Ansible 2.18.3 and Python 3.13.7.

## Configuration

Simple configurations can be managed through Ansible group variables configured under Ansible's `all` group. See the
files under `inventories/example/` for a recommended setup and example configurations.

One note about variable naming: underscores are preferred in variable names to align with normal Ansible standards.
When camel-case or other standards are encountered, these fields are likely be converted directly into JSON and used in
API requests. This is common when directly interacting with the BIG-IP API.

### BIG-IP Credentials

Provide administrator-level credentials to the BIG-IP by defining `service_account_user` and `service_account_password`
variables. These can be placed in a `secrets.yaml` file encrypted with `ansible-vault` located in your
`group_vars` directory. The example inventory has an *unencrypted* `secrets.yaml` sample configuration.

## Authentication Servers

### Configuring

Authentication servers are defined in the `auth-servers` variable as a list of objects. The `auth-servers.yaml` file in
the sample configuration contains examples. Supported configuration variables for an AS are listed below. All variables
are required *except* for claims, which may be left empty (but which will result in an access token with no claims):

| Variable Name | Description |
|---------------|-------------|
| `name` | A name for the AS, used a base when building various F5 objects (so it must be compatible with F5 object names) |
| `uri` | A unique path segment added to URIs to direct traffic to the AS. Use Okta's ID for the AS. |
| `audience` | A *list* of audiences to add to the access token. |
| `jwtAccessTokenLifetime` | Validity period of the access token, in minutes. |
| `subject` | The access token subject. |
| `issuer` | The access token issuer. |
| `algType` | The algorithm used to sign the access token. Valid values can be found in the corresponding dropdown in the OAuth profile UI. |
| `cert` | The certificate used to sign access tokens. |
| `certKey` | The key used to sign access tokens. |
| `logSettings` | A list of log profiles to use for the AS' access policy. |
| `client_apps` | A list of client applications authorized to use the AS. Use the F5 object name, excluding the partition. |
| `scopes` | A list of scopes available to clients. Use the F5 object name, excluding the partition. |
| `claims` | A list of claims to add to access tokens. Use the F5 object name, excluding the partition. The default value defined for the claim will be used, but a custom value can be provided (an example is provided in the sample configurations). |

#### Default Values

The `vars.yaml` file in the example inventory contains a `defaults.auth_servers` variable that shows all the AS
configuration fields supporting default values. To define a default vault, add a `defaults.auth_servers`
variable to your configuration with the desired fields. To override a default within an AS' configuration, simply define
a field with the same name.

### Scopes

Scopes are defined as a list of objects in the `scopes` variable. The `scopes.yaml` file in the sample configuration
contains examples. Scopes support the following configuration variables.

| Variable Name | Description |
|---------------|-------------|
| `name` | **Required.** The name of the scope. Used for both the F5 object name and the access token. |
| `scopeValue` | An optional value for the scope. |

### Claims

Claims are defined as a list of objects in the `claims` variable. The `claims.yaml` file in the sample configuration
contains examples. Claims support the following configuration variables.

| Variable NName | Description |
|----------------|-------------|
| `name` | **Required.** The name of the claim. Used for both the F5 object name and the access token. |
| `claimType` | **Required.** The data type of the claim value. Choices are `string`, `number`, `boolean`, and `custom`. |
| `claimValue` | **Required.** The default value to assign to the claim. You can use APM variables here (see the [APM Variables](#apm-variables) section for a non-exhaustive list). |
| `claimDescription` | An optional description for the claim. Only shown in the BIG-IP UI/API. |

### Playbooks

Several playbooks are provided that work together to build a complete AS.

| Playbook | Description |
|----------|-------------|
| `all.yaml` | Runs all other listed playbooks in the correct sequence. |
| `auth-servers.yaml` | Builds AS configurations, including virtual servers and routing data groups. |
| `claims.yaml` | Manages claims for use in AS configurations. |
| `okta-client-apps.yaml` | Imports client applications using Okta-formatted client IDs and secrets. |
| `scopes.yaml` | Manages scopes for use in AS configurations. |

Run the playbook with `ansible-playbook` from the top-level directory of this repository:

```bash
ansible-playbook -i inventories/example/hosts playbook.yaml
```

## Importing Okta Client Applications

Client applications can be exported from Okta and imported into F5 APM.

### Configuration

Define Okta clients as a list of objects in the `okta_clients` variable. Use the following configuration variables to
import Okta clients:

| Variable Name | Description |
|---------------|-------------|
| `client_id` | **Required.** The client ID. |
| `client_secret` | **Required.** The client secret. |
| `app_name` | **Required.** A descriptive name for the client (only shown in the F5 UI and REST API). |
| `description` | Another optional description only shown in the F5 UI and REST API. |
| `attributes` | An optional list of key-value objects with custom attributes for the client ID. These are added as APM variables for use in the access token. Each object must contain `name` and `value` parameters. |

### Playbook

 Run playbook `okta-client-apps.yaml` to perform the import.

```bash
ansible-playbook -i inventories/example/hosts okta-client-apps.yaml
# Note: if you encrypted your BIG-IP credentials with ansible-vault, include the --vault-id parameter
```

You can also regenerate the data group by specifying the `client-app-attributes` tag:

```bash
ansible-playbook -i inventories/example/hosts -t client-app-attributes okta-client-apps.yaml
```

## APM Variables

The following APM variables are available to use when defining an AS or claim. Use the standard `%{...}` syntax to
reference the variable. This is a non-exhaustive list.

| Variable Name | Description |
|---------------|-------------|
| `session.custom.*` | Custom attributes defined for a client application. |
| `session.custom.original_client_id` | The original client ID seen by the F5, before conversion to F5 format. |
| `session.oauth.authz.client_id` | The F5-formatted client ID. |
| `session.custom.scp` | The scope names associated with the access token, formatted as a JSON list. |
