#!/usr/bin/env pwsh

<# .SYNOPSIS
  Deploy Azure Key Valut into the resource group.

.DESCRIPTION
  Creates, idempotently via Azure CLI:
    * Key Vault `kv-<orgId>-llm-dev-01`

.NOTES
  This creates Azure Key Vault in the resource group.

  Running these scripts requires the following to be installed:
  * PowerShell, https://github.com/PowerShell/PowerShell
  * Azure CLI, https://docs.microsoft.com/en-us/cli/azure/

  You also need to connect to Azure (log in), and set the desired subscription context.

  Follow standard naming conventions from Azure Cloud Adoption Framework, 
  with an additional organisation or subscription identifier (after app name) in global names 
  to make them unique.
  https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming

  Follow standard tagging conventions from  Azure Cloud Adoption Framework.
  https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging

.EXAMPLE

  az login
  az account set --subscription <subscription id>
  $VerbosePreference = 'Continue'
  /shared/Deploy-SharedServices.ps1
#>
[CmdletBinding()]
param (
  ## Purpose prefix
  [string]$Purpose = $ENV:DEPLOY_PURPOSE ?? 'LLM',
  ## Workload prefix
  [string]$Workload = $ENV:DEPLOY_WORKLOAD ?? 'workload',
  ## Deployment environment, e.g. Prod, Dev, QA, Stage, Test.
  [string]$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev',
  ## Identifier for the organisation (or subscription) to make global names unique.
  [string]$OrgId = $ENV:DEPLOY_ORGID ?? "0x$((az account show --query id --output tsv).Substring(0,4))",
  ## Instance number uniquifier
  [string]$Instance = $ENV:DEPLOY_INSTANCE ?? '01',
  ## Data classification, for tagging
  [string] $DataClassification = $ENV:DEPLOY_CLASSIFICATION ?? 'Non-business',
  ## Criticality, for tagging
  [string] $Criticality = $ENV:DEPLOY_CRITICALITY ?? 'Low'
)

<#
To run interactively, start with:

$VerbosePreference = 'Continue'

$Purpose = $ENV:DEPLOY_PURPOSE ?? 'LLM'
$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev'
$OrgId = $ENV:DEPLOY_ORGID ?? "0x$((az account show --query id --output tsv).Substring(0,4))"
$Instance = $ENV:DEPLOY_INSTANCE ?? '001'
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SubscriptionId = $(az account show --query id --output tsv)
Write-Verbose "Deploying shared services in subscription '$SubscriptionId'"

# ---------------------------------------------------------
# Names

# Following standard naming conventions from Azure Cloud Adoption Framework
# https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
# With an additional organisation or subscription identifier (after app name) in global names to make them unique 

$rgName = "rg-$Purpose-$Workload-$Environment-$Instance".ToLowerInvariant()
$rg = az group show --name $rgName | ConvertFrom-Json

$kvName = "kv-$OrgId-$Purpose-$Environment-$Instance".ToLowerInvariant()

Write-Verbose "Key Vault: $kvName"

# ---------------------------------------------------------
# Other values

# Following standard tagging conventions from  Azure Cloud Adoption Framework
# https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging

$TagDictionary = [ordered]@{
  DataClassification = $DataClassification
  Criticality        = $Criticality
  BusinessUnit       = $Purpose
  Env                = $Environment
}

# Convert dictionary to tags format used by Azure CLI create command
$tags = $TagDictionary.Keys | ForEach-Object { $key = $_; "$key=$($TagDictionary[$key])" }

# ---------------------------------------------------------
# Key Vault

$existingVault = az keyvault show --name $kvName --resource-group $rgName 2>$null | ConvertFrom-Json
if (-not $existingVault) {
  Write-Verbose "Creating key vault $kvName"

  # Contributor on the RG is sufficient to self-grant data-plane permissions.

  az keyvault create `
    --resource-group $rgName `
    -l $rg.location `
    --name $kvName `
    --enable-rbac-authorization false `
    --tags $tags
  if ($LASTEXITCODE -ne 0) { throw "az keyvault create failed for '$kvName'" }

  $signedInUserObjectId = az ad signed-in-user show --query id --output tsv
  if ($LASTEXITCODE -ne 0 -or -not $signedInUserObjectId) {
    throw "Unable to resolve signed-in user object id via 'az ad signed-in-user show'"
  }
  Write-Verbose "Granting signed-in user $signedInUserObjectId broad data-plane permissions on $kvName"

  $secretPerms = @('get', 'list', 'set', 'delete', 'recover', 'backup', 'restore', 'purge')
  $certPerms = @('get', 'list', 'create', 'import', 'delete', 'update', 'managecontacts',
    'getissuers', 'listissuers', 'setissuers', 'deleteissuers', 'manageissuers',
    'recover', 'backup', 'restore', 'purge')
  $keyPerms = @('get', 'list', 'create', 'import', 'delete', 'update', 'recover', 'backup', 'restore', 'purge',
    'encrypt', 'decrypt', 'sign', 'verify', 'wrapKey', 'unwrapKey')

  az keyvault set-policy `
    --name $kvName `
    --resource-group $rgName `
    --object-id $signedInUserObjectId `
    --secret-permissions @secretPerms `
    --certificate-permissions @certPerms `
    --key-permissions @keyPerms | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "az keyvault set-policy failed for '$kvName'" }
} else {
  Write-Verbose "Key Vault already exists"
}
