@description('Location where resources will be provisioned')
param location string

@description('The unique namespace for the Kibana VM')
param namespace string

@description('Controls if the output address should be HTTP or HTTPS')
@allowed([
  'Yes'
  'No'
])
param https string = 'No'

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var publicIpName = '${namespace}-ip'
var fqdnSchema = https == 'Yes' ? 'https://' : 'http://'

resource publicIp 'Microsoft.Network/publicIPAddresses@2019-04-01' = {
  name: publicIpName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: 'kb-${uniqueString(resourceGroup().id, deployment().name, publicIpName)}'
    }
  }
}

output fqdn string = '${fqdnSchema}${publicIp.properties.dnsSettings.fqdn}:5601'
