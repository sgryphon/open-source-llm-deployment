#!/usr/bin/env pwsh

<# .SYNOPSIS
  Runs all the deployment scripts, with default values.

.EXAMPLE

  az login
  az account set --subscription <subscription id>
  $VerbosePreference = 'Continue'
  Deploy-Baseline.ps1
#>
[CmdletBinding()]
param ()

Write-Verbose "Creating resource group"
az stack sub create `
  --name stack-foundry-llm-dev-001-init `
  --location australiaeast `
  --template-file ./baseline/001-init-foundry-rg/main.bicep `
  --action-on-unmanage detachAll `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified

Write-Verbose "Deploying shared resources"
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-shared `
  --template-file ./baseline/002-deploy-shared/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified

Write-Verbose "Deploying Foundry and Model"
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-workload `
  --template-file ./baseline/003-deploy-llm/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
