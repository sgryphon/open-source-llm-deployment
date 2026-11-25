#!/usr/bin/env pwsh

<# .SYNOPSIS
  Removes the baseline resource group and all deployed resources. You need to purge the foundry if you want to recreate.

.EXAMPLE

  az login
  az account set --subscription <subscription id>
  $VerbosePreference = 'Continue'
  Remove-All.ps1
#>
[CmdletBinding()]
param ()

Write-Verbose "Removing resource group."
az stack sub delete `
  --name stack-foundry-llm-dev-001-init `
  --action-on-unmanage deleteAll

Write-Verbose "Purging Foundry (so it can be recreated)."
az cognitiveservices account purge `
  --resource-group rg-foundry-llm-dev-001 `
  --name aif-llm-dev-buf5ue-001 `
  --location australiaeast
