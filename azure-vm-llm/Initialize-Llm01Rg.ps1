#!/usr/bin/env pwsh

<# .SYNOPSIS
  Deploy workload resource group and network into Azure.

.DESCRIPTION
  Creates, idempotently via Azure CLI:

    * Resource group `rg-llm-workload-dev-01`
    * Virtual network `vnet-llm-workload-dev-australiaeast-01`, dual-stack (IPv6 ULA + IPv4)

  Addresses are derived deterministically with an IPv6 ULA Global ID 10-hex-character
  prefix based on the subscription ID, plus the vnetId for a /56 range. IPv4 assigns a
  10.vnetId.0.0/16 range.

.NOTES
  This creates a workload network in your Azure subscription.

  The network is dual stack with an IPv6 /56 Unique Local Address allocation,
  using a default Global ID based on a consistent unique hash of the
  subscription ID, with a default vnet ID, fdxx:xxxx:xxxx:yy00::/56.

  The -UlaGlobalId and -VnetId can also be passed in as parameters.
  For more information on ULAs see https://en.wikipedia.org/wiki/Unique_local_address

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
   ./infrastructure/Initialize-WorkloadRg.ps1
#>
[CmdletBinding()]
param (
    ## Purpose prefix
    [string]$Purpose = $ENV:DEPLOY_PURPOSE ?? 'LLM',
    ## Workload prefix
    [string]$Workload = $ENV:DEPLOY_WORKLOAD ?? 'workload',
    ## Deployment environment, e.g. Prod, Dev, QA, Stage, Test.
    [string]$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev',
    ## The Azure region where the resource is deployed.
    [string]$Region = $ENV:DEPLOY_REGION ?? 'australiaeast',
    ## Instance number uniquifier
    [string]$Instance = $ENV:DEPLOY_INSTANCE ?? '01',
    ## 40-bit (10 hex) IPv6 Unique Local Address GlobalID to use (default hash of subscription ID)
    [string]$UlaGlobalId = $ENV:DEPLOY_GLOBAL_ID ?? (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes((az account show --query id --output tsv))))).Hash.Substring(0, 10),
    ## Address range to use for IPv4. Default to 10.0.0.0/8
    [System.Net.IPNetwork] $GlobalPrefixV4 = $ENV:DEPLOY_GLOBAL_IPV4 ?? '10.0.0.0/8',
    ## Vnet length (bits). Default 8, which gives IPv6 a /56 and IPv4 a /16.
    [int] $VnetLengthBits = $ENV:DEPLOY_VNET_LENGTH ?? 8,
    ## Vnet index (within the specified length) to use for the workload subnet
    [int] $VnetIndex = $ENV:DEPLOY_LLM01_VNET_INDEX ?? 17,
    ## Data classification, for tagging
    [string] $DataClassification = $ENV:DEPLOY_CLASSIFICATION ?? 'Non-business',
    ## Criticality, for tagging
    [string] $Criticality = $ENV:DEPLOY_CRITICALITY ?? 'Low'
)

<#
To run interactively, start with:

$VerbosePreference = 'Continue'

$Purpose = $ENV:DEPLOY_PURPOSE ?? 'LLM',
$Workload = $ENV:DEPLOY_WORKLOAD ?? 'workload',
$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev'
$Region = $ENV:DEPLOY_REGION ?? 'australiaeast'
$Instance = $ENV:DEPLOY_INSTANCE ?? '01'
$UlaGlobalId = $ENV:DEPLOY_GLOBAL_ID ?? (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes((az account show --query id --output tsv))))).Hash.Substring(0, 10)
$VnetId = $ENV:DEPLOY_WORKLOAD_VNET_ID ?? ("02")
#>

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Functions

function CidrSubnet {
    param(
        [System.Net.IPNetwork] $Network,
        [int]    $Length,
        [int]    $Index
    )

    $addrBytes = $Network.BaseAddress.GetAddressBytes() # big-endian
    $prefixLen = $Network.PrefixLength
    $totalBits = $addrBytes.Length * 8

    if ($Length -lt $prefixLen) { throw "New length $Length must be >= base prefix length $prefixLen" }
    if ($Length -gt $totalBits) { throw "New length $Length exceeds address space ($totalBits bits)" }
    if ($Index  -lt 0) { throw "Index must be >= 0" }

    # Mask base address down to network bits only
    for ($i = 0; $i -lt $addrBytes.Length; $i++) {
        $bit = $i * 8
        if ($bit + 8 -le $prefixLen) { <# full byte inside prefix — keep #> }
        elseif ($bit -ge $prefixLen) { $addrBytes[$i] = 0 }
        else {
            $keep = $prefixLen - $bit
            $addrBytes[$i] = $addrBytes[$i] -band ([byte](0xFF -shl (8 - $keep)))
        }
    }

    # Convert big-endian bytes → BigInteger (unsigned: append 0x00 sign guard before reversing)
    $leBytes = [byte[]]($addrBytes.Clone())
    [array]::Reverse($leBytes)
    $leBytes += [byte]0
    $addrInt = [System.Numerics.BigInteger]::new($leBytes)

    $step = [System.Numerics.BigInteger]::Pow(2, $totalBits - $Length)
    $newInt = $addrInt + ($step * $Index)

    # Convert BigInteger (little-endian) back to big-endian fixed-length bytes
    $leResult = $newInt.ToByteArray()
    $result = [byte[]]::new($addrBytes.Length)
    $copyLen = [Math]::Min($leResult.Length, $addrBytes.Length)
    for ($i = 0; $i -lt $copyLen; $i++) {
        $result[$addrBytes.Length - 1 - $i] = $leResult[$i]
    }

    $subnetAddr = [System.Net.IPAddress]::new($result)
    $subnet = [System.Net.IPNetwork]::new($subnetAddr, $Length)
    return $subnet
}

# Deploy

$SubscriptionId = $(az account show --query id --output tsv)
Write-Verbose "Initialising $Purpose $Workload $Environment resource group in subscription '$SubscriptionId'"

# Following standard naming conventions from Azure Cloud Adoption Framework
# https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
# With an additional organisation or subscription identifier (after app name) in global names to make them unique 

$rgName = "rg-$Purpose-$Workload-$Environment-$Instance".ToLowerInvariant()
$vnetName = "vnet-$Purpose-$Workload-$Environment-$Region-$Instance".ToLowerInvariant()

# Global will default to unique value per subscription
$globalPrefixV6 = [System.Net.IPNetwork]::Parse("fd$($UlaGlobalId.Substring(0, 2)):$($UlaGlobalId.Substring(2, 4)):$($UlaGlobalId.Substring(6))::/48")
$vnetPrefixV6 = CidrSubnet $globalPrefixV6 ($globalPrefixV6.PrefixLength + $VnetLengthBits) $VnetIndex

# Azure only supports dual-stack (not single stack IPv6)
# "At least one IPv4 ipConfiguration is required for an IPv6 ipConfiguration on the network interface"

# Use the first byte of the ULA Global ID, and the vnet ID (as decimal)
$globalPrefixV4 = [System.Net.IPNetwork]::Parse($GlobalPrefixV4)
$vnetPrefixV4 = CidrSubnet $GlobalPrefixV4 ($GlobalPrefixV4.PrefixLength + $VnetLengthBits) $VnetIndex

# Following standard tagging conventions from  Azure Cloud Adoption Framework
# https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging

$TagDictionary = [ordered]@{
    WorkloadName       = $Workload
    DataClassification = $DataClassification
    Criticality        = $Criticality
    BusinessUnit       = $Purpose
    Env                = $Environment
}

# Convert dictionary to tags format used by Azure CLI create command
$tags = $TagDictionary.Keys | ForEach-Object { $key = $_; "$key=$($TagDictionary[$key])" }

# Create

Write-Verbose "Creating resource group $rgName"
az group create --name $rgName -l $Region --tags $tags
if ($LASTEXITCODE -ne 0) { throw "az group create failed for '$rgName'" }

Write-Verbose "Creating virtual network $vnetName ($vnetPrefixV6, $vnetPrefixV4)"
az network vnet create --name $vnetName `
                       --resource-group $rgName `
                       --address-prefixes $vnetPrefixV6 $vnetPrefixV4 `
                       --location $Region `
                       --tags $tags

Write-Verbose "Initialise $rgName complete"
