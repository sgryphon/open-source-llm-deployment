# Amazon Bedrock open-weight models

Use an open-weight LLM hosted by Amazon Bedrock from VS Code, through Bedrock's OpenAI-compatible
endpoint.

Nothing is deployed. Bedrock runs the models serverless and charges per token, so there is no idle
cost. You authenticate with a short-term Bedrock API key generated from your existing AWS sign-in.
No IAM users, roles or policies are created.

## Prerequisites

- Python 3 and AWS CLI v2 (both included in the devcontainer).
- An AWS sign-in whose role allows Bedrock inference on the `bedrock-mantle` endpoint:
  `bedrock-mantle:CreateInference` and `bedrock-mantle:CallWithBearerToken`. If you're not sure,
  the test below will tell you.

## Setup

Create a Python virtual environment for this example and install its dependencies from
[requirements.txt](requirements.txt). Create it once per clone, then activate it in each new
terminal. The commands below assume you are in the `aws-bedrock-llm` folder with the virtual
environment active.

Windows PowerShell:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Devcontainer (PowerShell on Linux):

```powershell
python3 -m venv .venv
./.venv/bin/Activate.ps1
pip install -r requirements.txt
```

In bash, activate with `source .venv/bin/activate` instead.

## Endpoint

Bedrock uses a shared endpoint with usage based charging:

```text
https://bedrock-mantle.ap-southeast-2.api.aws/v1
```

**Note:** Currently (Nov 2026) the address is IPv4 only.

This endpoint supports the OpenAI Responses and Chat Completions APIs and `GET /v1/models`.
Requests are handled in the region you call (Sydney here); it doesn't route to other regions.

Some models are served under `/openai/v1` instead of `/v1`. If you get "model ... isn't supported on
this route", use that path instead. The model card in the Bedrock console shows which applies.

## Models

Open-weight models with an OSI-approved licence, ranked by suitability for agentic coding (tool
calling, long context). Check the exact model ids available to you with the test script, which
lists them.

| Model            | Model id              | Licence    | Notes                               |
| ---------------- | --------------------- | ---------- | ----------------------------------- |
| Qwen3 Coder Next | see model list        | Apache 2.0 | Dedicated coding model.             |
| DeepSeek V3.2    | see model list        | MIT        | Strong general and coding model.    |
| gpt-oss-120b     | `openai.gpt-oss-120b` | Apache 2.0 | OpenAI open-weight reasoning model. |
| Mistral Large 3  | see model list        | Apache 2.0 | Good general and coding model.      |

Kimi K2.5 and Devstral 2 are also available but use modified licences.

The list was last checked in November 2026.

## Get an API key

Sign in, then generate a key:

```powershell
aws login
$ENV:BEDROCK_API_KEY = python get_bedrock_api_key.py
```

In bash: `export BEDROCK_API_KEY=$(python get_bedrock_api_key.py)`. Add `-v` to see progress, or
`--region <region>` for a region other than Sydney (or set `AWS_REGION`).

The key only lasts as long as the AWS credentials it was signed with (maximum 12 hours). With
`aws login` that is about 15 minutes, because `aws login` issues 15-minute credentials (the CLI
refreshes them, but an existing key keeps the old ones). Re-run the command above when the key
expires. Signing in with IAM Identity Center (`aws sso login`) may give you up to 12 hours,
depending on your permission set's session duration.

The key only works in the region it was generated for. Treat it like a password.

## Test

```powershell
python check_bedrock_model.py
```

This lists the models available to you, then sends a short prompt to `openai.gpt-oss-120b`. Use
`--model <id>` to test another model; `--help` lists all options.

If it fails:

- **403 on the model list:** your role doesn't have the `bedrock-mantle` permissions above. Ask the
  account owner to add them.
- **401 or "expired":** generate a new key.
- **"isn't supported on this route":** run again with
  `--base-url https://bedrock-mantle.ap-southeast-2.api.aws/openai/v1`.

## Connect VS Code

### OpenCode

OpenCode (installed in the devcontainer, with a VS Code extension) reads the key from the
environment, so a fresh key only needs `$ENV:BEDROCK_API_KEY` set before starting it. Add a
provider to `opencode.json` in your project or `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "bedrock-mantle": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Amazon Bedrock (Sydney)",
      "options": {
        "baseURL": "https://bedrock-mantle.ap-southeast-2.api.aws/v1",
        "apiKey": "{env:BEDROCK_API_KEY}"
      },
      "models": {
        "openai.gpt-oss-120b": { "name": "gpt-oss-120b" }
      }
    }
  }
}
```

Then pick the model with `/models`.

### GitHub Copilot Chat

Needs the GitHub Copilot Chat extension and a Copilot plan that allows custom models (on Business
and Enterprise, an admin may need to enable the policy).

1. Open the Chat view and click the model picker.
2. Select **Manage Models**, then **Add Models** > **Custom Endpoint**.
3. Enter the API key (`$ENV:BEDROCK_API_KEY`).
4. Choose the API type: Responses, or Chat Completions if a model doesn't support Responses.
5. Complete the models section in `chatLanguageModels.json`:

```json
{
  "name": "Custom Endpoint",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.xxxxxxxx}",
  "apiType": "responses",
  "models": [
    {
      "id": "openai.gpt-oss-120b",
      "name": "gpt-oss-120b (Bedrock Sydney)",
      "url": "https://bedrock-mantle.ap-southeast-2.api.aws/v1",
      "toolCalling": true,
      "vision": false,
      "maxInputTokens": 128000,
      "maxOutputTokens": 16000
    }
  ]
}
```

Copilot stores the key, so you need to re-enter it when it expires. Check each model card for its
context and output limits.

If Copilot reports "static system messages and tool definitions exceed this model's context
budget", too many tools are enabled: agent mode sends every MCP server's tool definitions with each
request. Use **Configure Tools** in the Chat view to untick MCP servers you don't need, or disable
extensions that contribute them.

## Data residency

A summary for engineering use, not a compliance statement.

- **Processing location:** requests to `bedrock-mantle` in `ap-southeast-2` are handled in Sydney.
- **Model providers:** AWS runs the open-weight models itself, so the model vendor never receives
  your traffic. AWS states Bedrock doesn't use prompts or completions for training and doesn't
  share them with model providers.
- **Jurisdiction:** AWS is a US company, so the US CLOUD Act applies regardless of region.
- **Government work:** check whether Bedrock and the mantle endpoint are in the current AWS IRAP
  assessment scope.
- **The client:** Copilot Chat sends model requests to Bedrock, but still needs GitHub sign-in,
  sends telemetry, and some features may use GitHub-hosted models. OpenCode only talks to the
  configured endpoint.

## Cleanup

Nothing to remove. Keys expire on their own, and there is no charge when you're not sending
requests.

## References

- [Bedrock mantle endpoint](https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-mantle.html)
- [Model availability by endpoint](https://docs.aws.amazon.com/bedrock/latest/userguide/models-endpoint-availability.html)
- [Model availability by region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html)
- [Bedrock API keys](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html)

## AWS test example:

```powershell
$ENV:AWS_DEFAULT_REGION = 'ap-southeast-2'

aws login

$vpcId = aws ec2 create-vpc `
  --cidr-block 10.20.0.0/16 `
  --amazon-provided-ipv6-cidr-block `
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=LlmNetwork-Dev/VPC},{Key=aws-cdk-ex:vpc-protocol,Value=DualStack},{Key=demo:owner,Value=LLM Lab},{Key=demo:classification,Value=Confidential}]" `
  --query Vpc.VpcId --output text

$v6 = aws ec2 describe-vpcs --vpc-ids $vpcId `
--query 'Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock' --output text

aws ec2 create-subnet --vpc-id $vpcId `
  --cidr-block 10.20.1.0/24 `
  --ipv6-cidr-block ($v6 -replace '/56$', '/64') `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=LlmNetwork-Dev/PublicSubnet1},{Key=aws-cdk-ex:subnet-protocol,Value=DualStack},{Key=demo:owner,Value=LLM Lab},{Key=demo:classification,Value=Confidential}]"
```

Clean up (subnets first, then the VPC):

```powershell
$vpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=LlmNetwork-Dev/VPC" `
  --query 'Vpcs[0].VpcId' --output text

aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" `
  --query 'Subnets[].SubnetId' --output text |
  ForEach-Object { $_ -split '\s+' } | Where-Object { $_ } |
  ForEach-Object { aws ec2 delete-subnet --subnet-id $_ }

aws ec2 delete-vpc --vpc-id $vpcId
```
