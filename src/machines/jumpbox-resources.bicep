@description('Location where resources will be provisioned')
param location string

@description('The unique namespace for jumpbox nodes')
param vmName string

@description('Network settings')
param networkSettings object

@description('Credential information block')
@secure()
param credentials object

@description('Elasticsearch deployment platform settings')
param osSettings object

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var vmSize = 'Standard_A0'
var subnetId = resourceId(networkSettings.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', networkSettings.name, networkSettings.subnet.name)
var publicIpName = '${vmName}-ip'
var securityGroupName = '${vmName}-nsg'
var vmNetworkInterfaceName = '${vmName}-nic'
var password_osProfile = {
  computername: vmName
  adminUsername: credentials.adminUsername
  adminPassword: credentials.password
}
var sshPublicKey_osProfile = {
  computername: vmName
  adminUsername: credentials.adminUsername
  linuxConfiguration: {
    disablePasswordAuthentication: 'true'
    ssh: {
      publicKeys: [
        {
          path: '/home/${credentials.adminUsername}/.ssh/authorized_keys'
          keyData: credentials.sshPublicKey
        }
      ]
    }
  }
}

resource securityGroup 'Microsoft.Network/networkSecurityGroups@2019-04-01' = {
  name: securityGroupName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          description: 'Allows SSH traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: osSettings.managementPort
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2019-04-01' = {
  name: publicIpName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: 'jump-${uniqueString(resourceGroup().id, deployment().name)}'
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2019-04-01' = {
  name: vmNetworkInterfaceName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: securityGroup.id
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2019-03-01' = {
  name: vmName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: credentials.authenticationType == 'password' ? password_osProfile : sshPublicKey_osProfile
    storageProfile: {
      imageReference: osSettings.imageReference
      osDisk: {
        name: '${vmName}-osdisk'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
  }
}

output fqdn string = publicIp.properties.dnsSettings.fqdn
