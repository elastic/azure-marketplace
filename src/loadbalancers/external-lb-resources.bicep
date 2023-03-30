@description('Network settings object')
param networkSettings object

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var httpsOpts = {
  Yes: 'https://'
  No: 'http://'
}
var https = httpsOpts[networkSettings.https]
var internalLoadBalancerName = '${networkSettings.namespacePrefix}internal-lb'
var externalLoadBalancerName = '${networkSettings.namespacePrefix}external-lb'
var externalLoadBalancerIpName = '${networkSettings.namespacePrefix}external-lb-ip'

resource internalLoadBalancer 'Microsoft.Network/loadBalancers@2019-04-01' = {
  name: internalLoadBalancerName
  location: networkSettings.location
  sku: {
    name: networkSettings.internalSku
  }
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LBFE'
        properties: {
          subnet: {
            id: resourceId(networkSettings.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', networkSettings.name, networkSettings.subnet.name)
          }
          privateIPAddress: networkSettings.subnet.loadBalancerIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'LBBE'
      }
    ]
    loadBalancingRules: [
      {
        name: 'es-http-internal'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', internalLoadBalancerName, 'LBFE')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', internalLoadBalancerName, 'LBBE')
          }
          protocol: 'Tcp'
          frontendPort: 9200
          backendPort: 9200
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', internalLoadBalancerName, 'es-probe-internal-http')
          }
        }
      }
      {
        name: 'es-transport-internal'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', internalLoadBalancerName, 'LBFE')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', internalLoadBalancerName, 'LBBE')
          }
          protocol: 'Tcp'
          frontendPort: 9300
          backendPort: 9300
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
        }
      }
    ]
    probes: [
      {
        name: 'es-probe-internal-http'
        properties: {
          protocol: 'Tcp'
          port: 9200
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
  }
}

resource externalLoadBalancerIp 'Microsoft.Network/publicIPAddresses@2019-04-01' = {
  name: externalLoadBalancerIpName
  location: networkSettings.location
  sku: {
    name: networkSettings.externalSku
  }
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    publicIPAllocationMethod: ((networkSettings.externalSku == 'Standard') ? 'Static' : 'Dynamic')
    dnsSettings: {
      domainNameLabel: 'lb-${uniqueString(resourceGroup().id, deployment().name)}'
    }
  }
}

resource externalLoadBalancer 'Microsoft.Network/loadBalancers@2019-04-01' = {
  name: externalLoadBalancerName
  location: networkSettings.location
  sku: {
    name: networkSettings.externalSku
  }
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LBFE'
        properties: {
          publicIPAddress: {
            id: externalLoadBalancerIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'LBBE'
      }
    ]
    loadBalancingRules: [
      {
        name: 'es-http-external'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', externalLoadBalancerName, 'LBFE')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', externalLoadBalancerName, 'LBBE')
          }
          protocol: 'Tcp'
          frontendPort: 9200
          backendPort: 9201
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', externalLoadBalancerName, 'es-http-external-probe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'es-http-external-probe'
        properties: {
          protocol: 'Tcp'
          port: 9201
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
  }
}

output fqdn string = '${https}${externalLoadBalancerIp.properties.dnsSettings.fqdn}:9200'
