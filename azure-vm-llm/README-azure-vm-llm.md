# Open Source LLM on an Azure virtual machine

Scripts are writting in PowerShell, and use the Azure CLI to configure resources.

The development container includes the necessary tools, e.g. Azure CLI.

You will need an Azure subscription and either create or be provided a resource group and virtual network.

## Initialise the resource group and network

Deploy at the subscription level to create:

- Resource group `rg-llm-workload-01`
- Virtual network `vnet-llm-workload-dev-australiaeast-01`, dual-stack (IPv6 ULA + IPv4)

```pwsh
$VerbosePreference = 'Continue'
cd azure-vm-llm
az login

# Generate ULA from Bicep uniqueString() base32 mapped to hex
$subscriptionUnique = az deployment sub create `
  --location australiaeast `
  --template-file ./get-subscription-unique.bicep `
  --query "properties.outputs.unique.value" `
  --output tsv
$ulaGlobalId = ($subscriptionUnique.Substring(0, 10).ToLower().ToCharArray() | ForEach-Object { '{0:x}' -f ('abcdefghijklmnopqrstuvwxyz234567'.IndexOf($_) -band 0xF) }) -join ''

./Initialize-Llm01Rg.ps1 -UlaGlobalId $ulaGlobalId -VnetIndex 17
```

Addresses are derived deterministically with an IPv6 ULA Global ID 10-hex-character
prefix based on the subscription ID, plus the vnetId for a /56 range. IPv4 assigns a
10.vnetId.0.0/16 range.

## Deploy shared services -- Azure Key Vault

Deploy at the resource group level to create:

- Azure Key Vault `kv-<orgId>-llm-dev-01`

```pwsh
$orgId = $subscriptionUnique.Substring(0, 6).ToLower()
./Deploy-SharedServices.ps1 -OrgId $orgId
```

OrgId is used where names need to be globally unique (such as the Key Vault URI), i.e. if this example is deployed into multiple subscriptions.

## Deploy vLLM virtual machine, with disk, and subnet

Deploy at the resource group level to create:

- Managed Identity `id-vmvllmdev01`, with permission to KeyVault
- Subnet `snet-llm-workload-dev-australiaeast-01`
- Network Security Group `nsg-llm-workload-dev-01`
- Disk `diskmodeldev001`, for model download
- Public IP `pip-vmvllmdev001-australiaeast-01` and `pipv4-vmvllmdev001-australiaeast-01`
- Network Interface `nic-vmvllmdev01-01`
- Virtual Machine `vmvllmdev01`, Ubuntu 22.04 LTS GPU VM size Standard_NC4as_T4_v3 (NVIDIA T4)
- Disk `osdiskvmvllmdev01`

```pwsh
$vllmApiKey = 'qwen_deadbeef0001'
./Deploy-VllmQwen.ps1 -VllmApiKey $vllmApiKey -OrgId $orgId -UlaGlobalId $ulaGlobalId -VnetIndex 17
```

DNS host names:

- "vllm-<OrgId>-dev-01.australiaeast.cloudapp.azure.com"
- "vllm-<OrgId>-dev-01-ipv4.australiaeast.cloudapp.azure.com"

The network interface and public IPs can be retained if the VM is recreated.

The model disk can also be detached to preserve it if recreating the VM.

Default machine size is 'Standard_NV6ads_A10_v5'. CPU quota and SKU availability are checked for the region.

Required secrets and certificates are stored in the shared Key Vault.

The virtual machine is configured to shut down automatically (based on Brisbane, Australia time), to save costs.

### Test access to the virtual machine

## Shared services

A central IT function may allocate these resources, or they may be dedicated resources for the workload, although they are not part of the workload itself.

| Component     | Details                   | Purpose                                                                                       |
| ------------- | ------------------------- | --------------------------------------------------------------------------------------------- |
| Azure Monitor | log-llm-shared-dev        | Used for monitoring.                                                                          |
| App Insights  | appi-llm-shared-dev       | Used for application monitoring.                                                              |
| KeyVault      | kv-llm-shared-<orgId>-dev | Used for secure storage of secrets and certificates, rather than storing locally on machines. |

### VPN Gateway (StrongSwan)

Road warrior VPN gateway, to demonstrate use of a second layer of security.

DNS host names:

- "vpn-<OrgId>-dev.australiaeast.cloudapp.azure.com"
- "vpn-<OrgId>-dev-ipv4.australiaeast.cloudapp.azure.com"

The following subnet ranges are allocated:

| Vnet                                   | IPv6 range     | IPv4 range   | Purpose                     |
| -------------------------------------- | -------------- | ------------ | --------------------------- |
| snet-llm-gateway-dev-australiaeast-001 | `--:0100::/64` | `--.16.0/24` | VPN gateway subnet.         |
| VPN Clients                            | `--:300::/64`  | `--.48.0/24` | Subnet for VPN client pool. |

The following Azure resources are created (if they do not already exist).

| Component              | Details                               | Purpose                                                                 |
| ---------------------- | ------------------------------------- | ----------------------------------------------------------------------- |
| Network Security Group | nsg-llm-gateway-dev-001               | Security group for gateway subnet.                                      |
| Managed Identity       | id-vmstrongdev001                     | Identity for the VPN gateway server.                                    |
| Public IP              | pip-vmstrongdev001-australiaeast-01   | Public IPv6.                                                            |
| Public IP              | pipv4-vmstrongdev001-australiaeast-01 | Public IPv4.                                                            |
| Network Interface      | nic-vmstrongdev001-01                 | Separate NIC, so that public IP can be retained if server is recreated. |
| Virtual Machine        | vmstrongdev001                        | StrongSwan virtual machine.                                             |
| Disk                   | osdiskvmstrongdev001                  | OS disk for the VM.                                                     |

VPN address pools:

- IPv6 allocates addresses from the range `--:300::1000` to `--:300::1fff`.
- IPv4 allocates addresses from the range `--.48.128` to `--.48.255`.

Default machine size is 'Standard_D2s_v6'.

Required secrets and certificates are stored in the shared Key Vault.

The virtual machine is configured to shut down automatically (based on Brisbane, Australia time), to save costs.

## Troubleshooting

### Cloud init debug

Connect (SSH) to the server:

```sh
ssh azureuser@llm-0x419d-dev-001-ipv4.australiaeast.cloudapp.azure.com
```

Check the cloud init logs:

```sh
more /var/log/cloud-init-output.log
```

Also see: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cloud-init-troubleshooting

### Configure SSH

SSH is configured as part of server creation.

If you want to change to a different key you can manually uploading a new public key to the server:

```pwsh
az vm user update `
  --username azureuser `
  --ssh-key-value ~/.ssh/id_rsa.pub `
  --resource-group rg-llm-workload-dev-001 `
  --name vmvllmdev001
```

If you don't have a key, and need to create a new one:

```pwsh
ssh-keygen -t rsa -b 4096
```

## Notes

### Open source large language model (LLM)

An LLM hosted in Azure, fully within your own tennant. Running this can be expensive.

You local AI tools connect, via your private connection, to your LLM.

### Agentic harness

As well as local development, provide sandbox environments with supporting services to run agents on Azure resources.

## Pre-requisites

### Azure resource group and networking

Your IT provider needs to provide an Azure resource group, with permissions for you to create the LLM in, and allocate networking addresses, with internal routing, to a virtual network (vnet) that you can use.

Sometimes they will lock things down a bit more and also control subnets and security groups.

In a cloud native organisation they may have self-service for a business unit to create an entire subscription, and then self-service network provisioning (with the required routing back to the corporate network).

### Private network connection to your development box

Often this is a virtual private network (VPN) between your local machine and Azure, although in some cases it could just be a public endpoint and relay on zero-trust transport layer security (TLS).

In an office environment it may mean a dedicated ExpressRoute service between your corporate network and Azure.

### Optional shared services

Services such as DNS are usually shared, as are core services like KeyVault and Azure Monitor.

You can duplicate them in your own subscription, or resource group, but shared is more common.

## Scripted deployment

## Ideas

- Basic Azure VM with small LLM, zero trust connection
- Azure VM with large LLM, zero trust connection
- Azure VM via private tunnel (why?), using StrongSWAN for IPv6 support + native client
- Azure Factory (pre-packaged)... not sure if any are open source
- AWS VM with LLM
- AWS Bedrock
