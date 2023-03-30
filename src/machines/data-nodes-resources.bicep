@description('vm configuration')
param vm object

@description('Storage Account Settings')
param storageSettings object

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var namespace = vm.namespace
var avSetCount = (((vm.count - 1) / 100) + 1)
// this is actually never zero, meaning there are never 0 disks. I wonder if this is how it's supposed to work...
var diskCount = ((storageSettings.dataDisks > 0) ? storageSettings.dataDisks : 1)

resource availabilitySets 'Microsoft.Compute/availabilitySets@2019-03-01' = [for i in range(0, avSetCount): {
  name: '${namespace}${i}-av-set'
  location: vm.shared.location
  tags: {
    provider: toUpper(elasticTags.provider)
  }
  properties: {
    platformUpdateDomainCount: 20
    platformFaultDomainCount: vm.platformFaultDomainCount
  }
  sku: {
    name: 'Aligned'
  }
}]

module virtualMachinesWithDisks '../partials/vm.bicep' = [for i in range(0, vm.count): if (diskCount > 0) {
  name: '${namespace}${i}-vm-creation'
  params: {
    vm: vm
    index: i
    availabilitySet: '${namespace}${(i % avSetCount)}-av-set'
    dataDisks: {
      disks: [for j in range(0, diskCount): {
        name: '${namespace}${i}-datadisk${(j + 1)}'
        diskSizeGB: storageSettings.diskSize
        lun: j
        managedDisk: {
          storageAccountType: storageSettings.accountType
        }
        caching: 'None'
        createOption: 'Empty'
      }]
    }
    elasticTags: elasticTags
  }
  dependsOn: [
    availabilitySets
  ]
}]

module virtualMachinesWithoutDisks '../partials/vm.bicep' = [for i in range(0, vm.count): if (diskCount == 0) {
  name: '${namespace}${i}-vm-nodisks-creation'
  params: {
    vm: vm
    index: i
    availabilitySet: '${namespace}${(i % avSetCount)}-av-set'
    elasticTags: elasticTags
  }
  dependsOn: [
    availabilitySets
  ]
}]
