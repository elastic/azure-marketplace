@description('Location where resources will be provisioned')
param location string

@description('The unique namespace for the Kibana VM')
param vmName string

@description('Network settings')
param networkSettings object

@description('Credentials information block')
@secure()
param credentials object

@description('Platform and OS settings')
param osSettings object

@description('Size of the Kibana VM')
param vmSize string = 'Standard_A1'

@description('Whether to enable accelerated networking for Kibana, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Yes'
  'No'
])
param acceleratedNetworking string = 'No'

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var subnetId = resourceId(networkSettings.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', networkSettings.name, networkSettings.subnet.name)
var publicIpName = '${vmName}-ip'
var securityGroupName = '${vmName}-nsg'
var networkInterfaceName = '${vmName}-nic'
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
          description: 'Allows inbound SSH traffic from anyone'
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
      {
        name: 'Kibana'
        properties: {
          description: 'Allows inbound Kibana traffic from anyone'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5601'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2019-04-01' = {
  name: networkInterfaceName
  location: location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    primary: true
    enableAcceleratedNetworking: (acceleratedNetworking == 'Yes')
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', publicIpName)
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

resource script 'Microsoft.Compute/virtualMachines/extensions@2019-03-01' = {
  name: '${vmName}/script'
  location: location
  properties: osSettings.extensionSettings.kibana
  dependsOn: [
    virtualMachine
  ]
}
