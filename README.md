# Open Source LLM's in your Azure tennant

Blueprints for deploying open source LLMs on Azure.

## Goal

Connect your local AI tools to an open source LLM, run in a private environment on Azure, without sending data or code ourside your Azure tenant or to any third party.

## Examples

### Azure VM LLM

Work in progress

See `azure-vm-llm`

### Azure VPN protected VM

Work in progress

See `azure-vpn-llm`

Note: Wrapping a secure service in a VPN may actually reduce security. See https://sgryphon.gamertheory.net/2026/05/stop-wrapping-zero-trust-apps-in-a-vpn/

## Notes

### Open source large language model (LLM)

An LLM hosted in Azure, fully within your own tennant. Running this can be expensive.

You local AI tools connect, via your private connection, to your LLM.

### Agentic harness

As well as local development, provide sandbox environments with supporting services to run agents on Azure resources.
