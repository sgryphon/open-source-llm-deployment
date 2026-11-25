# Azure AI Foundry

Repeatable Bicep deployment of an Azure AI Foundry account and project with
Azure Monitor integration for agent tracing.

## Model selection

The models below are open-weight models with an OSI-approved licence, sold directly by Azure in Foundry
(pay per token, no Marketplace subscription). They are ranked by suitability for agentic coding, which
needs tool calling and a long context.

**Note:** These models run as a global deployment, not a regional one, even when the Foundry account is in
an Australian region. Prompts and responses may be processed in any Azure region. Data at rest stays in the
account's geography.

The list was last checked in November 2026.

| Model format | Model name               | Model version | Licence    | Notes                                                                                                                        |
| ------------ | ------------------------ | ------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `DeepSeek`   | `DeepSeek-V4-Pro`        | `2026-04-23`  | MIT        | 1.6T MoE (49B active). Strongest open coding and agentic model in the catalogue.                                             |
| `DeepSeek`   | `DeepSeek-V4-Flash-0731` | `2026-07-31`  | MIT        | Smaller, faster and cheaper V4 variant. A good default for interactive coding agents.                                        |
| `OpenAI-OSS` | `gpt-oss-120b`           | `1`           | Apache 2.0 | OpenAI open-weight reasoning model with function calling and structured outputs. Preview. Needs a Foundry project to deploy. |
| `Mistral AI` | `Mistral-Large-3`        | `1`           | Apache 2.0 | 675B MoE (41B active). Good general and coding model, strong on European languages. Preview.                                 |
| `DeepSeek`   | `DeepSeek-V3.2`          | `1`           | MIT        | Previous generation, now superseded by V4.                                                                                   |

Excluded:

- `Kimi-K2.7-Code` (Moonshot AI) is the catalogue's dedicated coding model and a strong candidate. It is
  left out of the table because it uses a Modified MIT licence.
- Meta Llama uses the Llama Community Licence, which is not OSI-approved. Foundry also lists it without
  tool calling.

To check the current model formats, names, versions and SKUs in your region:

```powershell
az cognitiveservices model list --location australiaeast `
  --query "[?model.format!='OpenAI'].{format:model.format, name:model.name, version:model.version, skus:join(',', model.skus[].name)}" `
  -o table
```

## Prerequisites

- Azure CLI 2.61.0 or later with Bicep support.
- PowerShell 7 or later.
- Access to a subscription and region where Azure AI Foundry is available.
- Azure permissions to create the resources in the selected deployment mode.
- Permission to manage deployment stacks at the selected scopes.

Sign in and, if useful, choose the subscription:

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
```

## Initialise the resource group

Note: If you have already been provided a resource group, you can skip this step and go straight to **Deploying shared services**. This avoids requiring subscription-level permissions.

To initialise a Resource Group:

```powershell
az stack sub create `
  --name stack-foundry-llm-dev-001-init `
  --location australiaeast `
  --template-file ./azure-foundry-llm/001-init-foundry-rg/main.bicep `
  --action-on-unmanage detachAll `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
```

This creates the following Azure Resources (using the default settings):

| Resource       | Default naming pattern   | Purpose           |
| -------------- | ------------------------ | ----------------- |
| Resource group | `rg-foundry-llm-dev-001` | LLM deployment RG |

The default `orgId` is derived deterministically from the subscription ID.
All stacks apply the lowercase tag keys `env`, `region`, `criticality`,
`businessunit`, and `confidentiality`. The default confidentiality value is
`unclassified`; change it to match your organization's classification taxonomy.

## Deploying shared services: Azure Monitor

Deploy the shared Azure Monitor resources within the resource group:

```powershell
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-shared `
  --template-file ./baseline/002-deploy-shared/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
```

This creates the following Azure Resources (using the default settings):

| Resource                | Default naming pattern     | Purpose                                |
| ----------------------- | -------------------------- | -------------------------------------- |
| Log Analytics workspace | `log-llm-dev-{orgId}-001`  | Workspace backing Application Insights |
| Application Insights    | `appi-llm-dev-{orgId}-001` | Observability foundation for workloads |

## Deploying the workload: Foundry account, project, and model

```powershell
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-workload `
  --template-file ./baseline/003-deploy-llm/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
```

This creates the following Azure Resources (using the default settings):

| Resource                         | Default naming pattern               | Purpose                                                                    |
| -------------------------------- | ------------------------------------ | -------------------------------------------------------------------------- |
| Foundry account                  | `aif-llm-dev-{orgId}-001`            | Current `Microsoft.CognitiveServices/accounts` resource, kind `AIServices` |
| Foundry project                  | `proj-llm-dev-001`                   | Child project under the account                                            |
| Application Insights connections | `aif-...-appinsights` and `appi-...` | Account- and project-scoped tracing connections                            |
| Model deployment                 | `deepseek-v4-pro-dev-001`            | Model deployment on the Foundry account (default `DeepSeek-V4-Pro`)        |

You can override parameters, deploy a different model, or use an existing
Azure Monitor Application Insights resource, for example:

```powershell
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-mydemo-test-001-workload `
  --template-file ./baseline/003-deploy-llm/main.bicep `
  --parameters orgId=MyOrg purpose=MyDemo environment=Test instance=001 applicationInsightsName=appi-existing applicationInsightsResourceGroupName=rg-monitoring modelFormat=OpenAI-OSS modelName=gpt-oss-120b modelVersion=<version> `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
```

**Note:** Currently (Nov 2026) the endpoint address, e.g. `aif-llm-dev-buf5ue-001.services.ai.azure.com`, is IPv4 only.

### Deploying a non-OSS model

For testing OSS models may have tight rate limits. If you don't have high limits, you could try a model generous non-OSS model for testing. Non-OSS models may also have Data Zone support.

```powershell
az stack group create `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-workload `
  --template-file ./baseline/003-deploy-llm/main.bicep `
  --parameters modelFormat=OpenAI modelName=gpt-6.2-sol modelVersion=2026-11-17 skuName=DataZoneStandard skuCapacity=250 `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=llm confidentiality=unclassified
```

## Using the model

The Foundry account exposes an OpenAI-compatible endpoint, so any tool that can talk to an
OpenAI-compatible API can use the deployed model. You need three values: the endpoint URL, an API key,
and the deployment name (which is used as the model id).

```powershell
$rg = 'rg-foundry-llm-dev-001'
$foundry = az cognitiveservices account list --resource-group $rg | ConvertFrom-Json
$apiKeys = az cognitiveservices account keys list --resource-group $rg --name $foundry.name | ConvertFrom-Json
$deployment = az cognitiveservices account deployment list --resource-group $rg --name $foundry.name | ConvertFrom-Json

$modelUrl = "$($foundry.properties.endpoints.'AI Foundry API')/openai/v1/responses"
$modelId = $deployment.name

Write-Output "Model URL: $modelUrl"
Write-Output "Model ID: $modelId"
```

Check the model responds before configuring any tools:

```powershell
$body = @{
  model    = $modelId
  messages = @(@{ role = 'user'; content = 'Say hello in five words.' })
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri $modelUrl `
  -Headers @{ 'api-key' = $apiKeys.key1 } -ContentType 'application/json' -Body $body |
  Select-Object -ExpandProperty choices | ForEach-Object { $_.message.content }
```

Treat the API key like a password. Don't paste it into files that are committed to the repo. If it
leaks, rotate it with `az cognitiveservices account keys regenerate --key-name key1 ...`.

### VS Code

These steps use GitHub Copilot Chat's "bring your own key" support. You need the GitHub Copilot Chat
extension and a Copilot plan that allows custom models (on Copilot Business and Enterprise, your
organisation admin may need to enable this policy).

1. In VS Code, make sure the GitHub Copilot for Azure extension is installed
2. Open the Chat sidebar and click the model picker at the bottom
3. Select Add Models... (plus)
4. On the models screen, click Add Models and select Custom Endpoint
5. You can use the default group name 'Custom Endpoint', then enter the API Key
6. For API Type, use Responses API for modern models (Chat Completion is older but widely supported, Messages API is for Anthropic)

You will need to manually complete the models section in chatLanguageModels.json with your Foundry URL and Model ID. Modify settings as needed, e.g. for Deepseek v4 Pro set vision = false.

```json
{
  "name": "Custom Endpoint",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.-1437e28d}",
  "apiType": "responses",
  "models": [
    {
      "id": "deepseek-v4-pro-dev-001",
      "name": "Deepseek v4 Pro",
      "url": "https://aif-llm-dev-buf5ue-001.services.ai.azure.com/openai/v1/responses",
      "toolCalling": true,
      "vision": false,
      "maxInputTokens": 128000,
      "maxOutputTokens": 16000
    }
  ]
}
```

Troubleshooting: If the model cannot handle your request size, try configuring with less tools (turn off the ones you aren't using).

## Stack lifecycle

The init stack retains resources removed from its template (`detachAll`);
the shared and workload stacks delete removed resources but retain resource groups
(`deleteResources`). Application Insights and connections belong to the shared and workload stacks respectively.

## Cleanup

If you want to delete everything, just skip to the last step.

Otherwise you can delete stacks individually.

Delete the workload stack and its managed resources first:

```powershell
az stack group delete `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-workload `
  --action-on-unmanage deleteResources
```

Then delete the shared stack:

```powershell
az stack group delete `
  --resource-group rg-foundry-llm-dev-001 `
  --name stack-foundry-llm-dev-001-shared `
  --action-on-unmanage deleteResources
```

Finally, delete the init stack and resource group (this also deletes anything else that has not already been deleted):

```powershell
az stack sub delete `
  --name stack-foundry-llm-dev-001-init `
  --action-on-unmanage deleteAll
```

The AI Foundry will soft delete, so you need to purge if you want to re-run:

```
az cognitiveservices account purge `
  --resource-group rg-foundry-llm-dev-001 `
  --name aif-llm-dev-buf5ue-001 `
  --location australiaeast
```

## Issues

While you may have Contributor role, e.g. in the subscription to create a Foundry resource, that doesn't mean you can actually use it.

e.g. When you try to access tools like Agents, you get an error:

"You don't have permission to build agents in this project.
To get access, please ask your administrator to assign you the Foundry User role for the resource:
proj-default"

You can modify or even delete the Foundry resource, but to actually use it you need admin permissions (that you may not have) to assign roles.

Try getting your training subscription administrator to assign at least the 'Foundry User' role as the subscription level (or preferably a higher level role such as 'Foundry Owner'). The subscription level permission will allow you to access the Foundry you create.

```
az role assignment create `
  --role "Foundry User" `
  --assignee "<your-user-id>" `
  --scope "/subscriptions/419ddfc4-e365-4b55-9364-eb45b8f256b1"
```

## Notes

In Azure Portal, when creating Foundry:

- Can link to Key Vault
- Can link to App Insights
- Can set inbound and outbound networking
- Can set User-assigned identity (or System-assigned)
