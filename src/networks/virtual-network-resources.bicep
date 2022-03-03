@description('Choose to create a new Virtual Network or use an existing one. If choosing an existing network, the subnet also needs to exist.')
@allowed([
  'new'
  'existing'
])
param vNetNewOrExisting string

@description('Network settings object')
param networkSettings object

@description('Set up an internal or external load balancer, or use Application Gateway (gateway) for load balancing and SSL offload. If you are setting up Elasticsearch on a publicly available endpoint, it is *strongly recommended* to secure your nodes with a product like Elastic\'s X-Pack Security')
@allowed([
  'internal'
  'external'
  'gateway'
])
param loadBalancerType string = 'internal'

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-04-01' = if (vNetNewOrExisting == 'New') {
  name: networkSettings.name
  location: networkSettings.location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        networkSettings.addressPrefix
      ]
    }
  }
}

resource esSubnet 'Microsoft.Network/virtualNetworks/subnets@2019-04-01' = {
  name: '${networkSettings.name}/${networkSettings.subnet.name}'
  properties: {
    addressPrefix: networkSettings.subnet.addressPrefix
  }
}

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2019-04-01' = if (loadBalancerType == 'gateway') {
  parent: virtualNetwork
  name: networkSettings.applicationGatewaySubnet.name
  properties: {
    addressPrefix: networkSettings.applicationGatewaySubnet.addressPrefix
  }
}
