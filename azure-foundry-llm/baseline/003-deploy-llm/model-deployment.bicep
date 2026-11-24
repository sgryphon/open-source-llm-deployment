/*
Deploys a model to an existing Azure AI Foundry account.
*/

@description('Azure AI Foundry account name.')
@minLength(2)
@maxLength(64)
param foundryName string

@description('Model deployment name.')
@minLength(2)
@maxLength(64)
param deploymentName string

@allowed([
  'AI21 Labs'
  'Cohere'
  'Core42'
  'DeepSeek'
  'xAI'
  'Meta'
  'Microsoft'
  'Mistral AI'
  'OpenAI'
  'OpenAI-OSS'
])
@description('Model format (e.g., DeepSeek, OpenAI-OSS).')
param modelFormat string

@description('Model identifier or name to deploy (e.g., gpt-6.1-terra, gpt-6-astra, claude-opus-5.5).')
@minLength(1)
@maxLength(64)
param modelName string

@description('Model version to deploy.')
@minLength(1)
@maxLength(64)
param modelVersion string

@allowed([
  'GlobalStandard'
  'DataZoneStandard'
  'Standard'
  'GlobalProvisioned'
  'Provisioned'
])
@description('SKU (e.g., GlobalStandard).')
param skuName string

@description('Capacity (quota) units for the model deployment. 1 quota unit is 1,000 tokens/minute.')
@minValue(1)
param skuCapacity int

@description('Content filter policy name')
param contentFilterPolicyName string

@description('Tags applied to all resources that support tags.')
param tags object

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: deploymentName
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
    raiPolicyName: contentFilterPolicyName == null ? 'Microsoft.Nill' : contentFilterPolicyName
  }
  tags: tags
}

output deploymentId string = modelDeployment.id
output deploymentName string = modelDeployment.name
output modelName string = modelName
