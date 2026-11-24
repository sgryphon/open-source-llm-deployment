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

Write-Verbose "Removing resource group. You need to purge the Foundry in you want to recreate."
az stack sub delete `
  --name stack-foundry-llm-dev-001-init `
  --action-on-unmanage deleteAll
