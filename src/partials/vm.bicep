@description('vm configuration')
param vm object

@description('the outer loop index')
param index int

@description('The name of the availability set')
param availabilitySet string

@description('additional data disks to attach')
param dataDisks object = {
  disks: []
}

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var vmName = '${vm.namespace}${index}'
var password_osProfile = {
  computername: vmName
  adminUsername: vm.shared.credentials.adminUsername
  adminPassword: vm.shared.credentials.password
}
var sshPublicKey_osProfile = {
  computername: vmName
  adminUsername: vm.shared.credentials.adminUsername
  linuxConfiguration: {
    disablePasswordAuthentication: 'true'
    ssh: {
      publicKeys: [
        {
          path: '/home/${vm.shared.credentials.adminUsername}/.ssh/authorized_keys'
          keyData: vm.shared.credentials.sshPublicKey
        }
      ]
    }
  }
}

var publicIpName = '${vmName}-ip'
var nsgIpConfigs = [
  {}
  {
    networkSecurityGroup: {
      id: resourceId('Microsoft.Network/networkSecurityGroups', vm.nsg)
    }
  }
  {
    networkSecurityGroup: {
      id: resourceId('Microsoft.Network/networkSecurityGroups', vm.nsg)
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vm.shared.subnetId
          }
          loadBalancerBackendAddressPools: vm.backendPools
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
]
var nsgIpConfig = nsgIpConfigs[(empty(vm.nsg) ? 0 : (vm.standardInternalLoadBalancer ? 2 : 1))]
var nicProperties = {
  primary: true
  enableAcceleratedNetworking: (vm.acceleratedNetworking == 'Yes')
  ipConfigurations: [
    {
      name: 'ipconfig1'
      properties: {
        privateIPAllocationMethod: 'Dynamic'
        subnet: {
          id: vm.shared.subnetId
        }
        loadBalancerBackendAddressPools: vm.backendPools
      }
    }
  ]
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2019-04-01' = if ((!empty(vm.nsg)) && vm.standardInternalLoadBalancer) {
  name: publicIpName
  location: vm.shared.location
  sku: {
    name: 'Standard'
  }
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${vmName}${uniqueString(resourceGroup().id, deployment().name)}'
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2019-04-01' = {
  name: '${vmName}-nic'
  location: vm.shared.location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: union(nicProperties, nsgIpConfig)
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2019-03-01' = {
  name: vmName
  location: vm.shared.location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    availabilitySet: {
      id: resourceId('Microsoft.Compute/availabilitySets', availabilitySet)
    }
    hardwareProfile: {
      vmSize: vm.size
    }
    osProfile: vm.shared.credentials.authenticationType == 'password' ? password_osProfile : sshPublicKey_osProfile
    storageProfile: {
      imageReference: vm.imageReference
      osDisk: {
        name: '${vmName}-osdisk'
        managedDisk: {
          storageAccountType: vm.storageAccountType
        }
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
      dataDisks: dataDisks.disks
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

resource vmInstallScript 'Microsoft.Compute/virtualMachines/extensions@2019-03-01' = {
  name: '${vmName}/script'
  location: vm.shared.location
  properties: vm.installScript
  dependsOn: [
    virtualMachine
  ]
}
