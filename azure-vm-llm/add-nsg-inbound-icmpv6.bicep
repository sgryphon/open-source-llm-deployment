targetScope = 'resourceGroup'

@description('Existing NSG name')
param nsgName string

@description('Security rule name')
param ruleName string = 'Allow-ICMPv6-Inbound'

@description('Rule priority (must be unique in NSG)')
param priority int = 1002

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-07-01' existing = {
  name: nsgName
}

resource icmpv6Rule 'Microsoft.Network/networkSecurityGroups/securityRules@2025-07-01' = {
  parent: nsg
  name: ruleName
  properties: {
    access: 'Allow'
    direction: 'Inbound'
    priority: priority
    protocol: 'Icmpv6'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
  }
}
