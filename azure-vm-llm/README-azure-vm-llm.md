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
- Disk `diskmodeldev01`, for model download
- Public IP `pip-vmvllmdev01-australiaeast-01` and `pipv4-vmvllmdev01-australiaeast-01`
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

### Cloud init debug

Connect (SSH) to the server:

```sh
$pip = az network public-ip show --resource-group rg-llm-workload-dev-01 --name pip-vmvllmdev01-australiaeast-01 | ConvertFrom-Json
ssh "azureuser@$($pip.dnsSettings.fqdn)"
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

## Import LLM model

Once the VM is ready, we can download the open source LLM (may take a while).

```pwsh
./Import-LlmModel.ps1
```

### Test endpoint

SSH to the machine, and you can test the model locally:

```sh
ls /opt/models
nvidia-smi
sudo systemctl status vllm --no-pager
sudo ss -ltnp | grep :443
sudo cat /etc/vllm/vllm.env
curl -k -H "Authorization: Bearer qwen_deadbeef0001" https://localhost/v1/models
sudo journalctl -u vllm -n 200 --no-pager
```

Troubleshooting Nvidia, e.g. check the CUDA versions match:

```sh
nvidia-smi
cat /proc/driver/nvidia/version
/opt/vllm/.venv/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)"
```

Also test remote access:

```pwsh
$vllmApiKey = 'qwen_deadbeef0001'
$headers = @{ Authorization = "Bearer $vllmApiKey" }
$invokeArgs = @{ Headers = $headers }
$pip = az network public-ip show --resource-group rg-llm-workload-dev-01 --name pip-vmvllmdev01-australiaeast-01 | ConvertFrom-Json
$modelsUri = "https://$($pip.dnsSettings.fqdn)/v1/models"
Invoke-RestMethod -Method Get -Uri $modelsUri @invokeArgs -TimeoutSec 180
```

## Rebuilding the virtual machine

Detach the model disk, then rebuild:

```pwsh
./Dismount-LlmModelDisk.ps1
az vm delete --resource-group rg-llm-workload-dev-01 --name vmvllmdev01 --yes
az disk delete --resource-group rg-llm-workload-dev-01 --name osdiskvmvllmdev01 --yes
./Deploy-VllmQwen.ps1 -VllmApiKey $vllmApiKey -OrgId $orgId -UlaGlobalId $ulaGlobalId -VnetIndex 17
```
