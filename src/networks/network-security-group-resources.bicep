param resourceGroupLocation string

param nsgName string

param elasticTags object

param standardInternalOrExternalLoadBalancer bool
param standardExternalLoadBalancer bool

var vmNsgProperties = [
  {}
  {
    securityRules: [
      {
        name: 'External'
        properties: {
          description: 'Allows inbound traffic from Standard External LB'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9201'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
]

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2019-04-01' = if (standardInternalOrExternalLoadBalancer) {
  name: nsgName
  location: resourceGroupLocation
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: vmNsgProperties[(standardExternalLoadBalancer ? 1 : 0)]
}
