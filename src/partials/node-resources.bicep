@description('Operating system settings')
param osSettings object

@description('Shared VM settings')
param commonVmSettings object

@description('Aggregate for topology variable')
param topologySettings object

@description('Network settings')
param networkSettings object

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

var locations = {
  eastus: {
    platformFaultDomainCount: 3
  }
  eastus2: {
    platformFaultDomainCount: 3
  }
  centralus: {
    platformFaultDomainCount: 3
  }
  northcentralus: {
    platformFaultDomainCount: 3
  }
  southcentralus: {
    platformFaultDomainCount: 3
  }
  westus: {
    platformFaultDomainCount: 3
  }
  canadacentral: {
    platformFaultDomainCount: 3
  }
  northeurope: {
    platformFaultDomainCount: 3
  }
  westeurope: {
    platformFaultDomainCount: 3
  }
}
var normalizedLocation = replace(toLower(commonVmSettings.location), ' ', '')
var platformFaultDomainCount = (contains(locations, normalizedLocation) ? locations[normalizedLocation].platformFaultDomainCount : 2)
var vmAcceleratedNetworking = [
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D64_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D64s_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_M8ms'
  'Standard_M16ms'
  'Standard_M32ts'
  'Standard_M32ls'
  'Standard_M32ms'
  'Standard_M64s'
  'Standard_M64ls'
  'Standard_M64ms'
  'Standard_M128s'
  'Standard_M128ms'
  'Standard_M64'
  'Standard_M64m'
  'Standard_M128'
  'Standard_M128m'
]
var networkSecurityGroupName = '${commonVmSettings.namespacePrefix}standard-lb-nsg'
var standardInternalLoadBalancer = (networkSettings.internalSku == 'Standard')
var standardExternalLoadBalancer = (networkSettings.externalSku == 'Standard')
var standardInternalOrExternalLoadBalancer = (standardInternalLoadBalancer || standardExternalLoadBalancer)

module masterNodes '../machines/master-nodes-resources.bicep' = if (topologySettings.dataNodesAreMasterEligible == 'No') {
  name: 'master-nodes'
  params: {
    vm: {
      shared: commonVmSettings
      namespace: '${commonVmSettings.namespacePrefix}master-'
      installScript: osSettings.extensionSettings.master
      size: topologySettings.vmSizeMasterNodes
      storageAccountType: 'Standard_LRS'
      count: 3
      backendPools: []
      imageReference: osSettings.imageReference
      platformFaultDomainCount: platformFaultDomainCount
      acceleratedNetworking: ((topologySettings.vmMasterNodeAcceleratedNetworking == 'Default') ? (contains(vmAcceleratedNetworking, topologySettings.vmSizeMasterNodes) ? 'Yes' : 'No') : topologySettings.vmMasterNodeAcceleratedNetworking)
      nsg: ''
      standardInternalLoadBalancer: false
    }
    elasticTags: elasticTags
  }
}

module networkSecurityGroup '../networks/network-security-group-resources.bicep' = {
  name: 'network-security-group'
  params: {
    resourceGroupLocation: commonVmSettings.location
    nsgName: networkSecurityGroupName
    elasticTags: elasticTags
    standardInternalOrExternalLoadBalancer: standardInternalOrExternalLoadBalancer
    standardExternalLoadBalancer: standardExternalLoadBalancer
  }
}

module clientNodes '../machines/client-nodes-resources.bicep' = if (topologySettings.vmClientNodeCount > 0) {
  name: 'client-nodes'
  params: {
    vm: {
      shared: commonVmSettings
      namespace: '${commonVmSettings.namespacePrefix}client-'
      installScript: osSettings.extensionSettings.client
      size: topologySettings.vmSizeClientNodes
      count: topologySettings.vmClientNodeCount
      storageAccountType: 'Standard_LRS'
      backendPools: topologySettings.loadBalancerBackEndPools
      imageReference: osSettings.imageReference
      platformFaultDomainCount: platformFaultDomainCount
      acceleratedNetworking: ((topologySettings.vmClientNodeAcceleratedNetworking == 'Default') ? (contains(vmAcceleratedNetworking, topologySettings.vmSizeClientNodes) ? 'Yes' : 'No') : topologySettings.vmClientNodeAcceleratedNetworking)
      nsg: (standardInternalOrExternalLoadBalancer ? networkSecurityGroupName : '')
      standardInternalLoadBalancer: standardInternalLoadBalancer
    }
    elasticTags: elasticTags
  }
}

module dataNodes '../machines/data-nodes-resources.bicep' = {
  name: 'data-nodes'
  params: {
    vm: {
      shared: commonVmSettings
      namespace: '${commonVmSettings.namespacePrefix}data-'
      installScript: osSettings.extensionSettings.data
      size: topologySettings.vmSizeDataNodes
      storageAccountType: topologySettings.vmDataNodeStorageAccountType
      count: topologySettings.vmDataNodeCount
      backendPools: topologySettings.dataLoadBalancerBackEndPools
      imageReference: osSettings.imageReference
      platformFaultDomainCount: platformFaultDomainCount
      acceleratedNetworking: ((topologySettings.vmDataNodeAcceleratedNetworking == 'Default') ? (contains(vmAcceleratedNetworking, topologySettings.vmSizeDataNodes) ? 'Yes' : 'No') : topologySettings.vmDataNodeAcceleratedNetworking)
      nsg: ((standardInternalOrExternalLoadBalancer && (topologySettings.vmClientNodeCount == 0)) ? networkSecurityGroupName : '')
      standardInternalLoadBalancer: standardInternalLoadBalancer
    }
    storageSettings: topologySettings.dataNodeStorageSettings
    elasticTags: elasticTags
  }
}

module jumpbox '../machines/jumpbox-resources.bicep' = if (toLower(topologySettings.jumpbox) == 'yes') {
  name: 'jumpbox'
  params: {
    credentials: commonVmSettings.credentials
    location: commonVmSettings.location
    vmName: '${commonVmSettings.namespacePrefix}jumpbox'
    networkSettings: networkSettings
    osSettings: osSettings
    elasticTags: elasticTags
  }
}

module kibana '../machines/kibana-resources.bicep' = if (topologySettings.kibana == 'Yes') {
  name: 'kibana'
  params: {
    credentials: commonVmSettings.credentials
    location: commonVmSettings.location
    vmName: '${commonVmSettings.namespacePrefix}kibana'
    networkSettings: networkSettings
    osSettings: osSettings
    vmSize: topologySettings.vmSizeKibana
    acceleratedNetworking: ((topologySettings.vmKibanaAcceleratedNetworking == 'Default') ? (contains(vmAcceleratedNetworking, topologySettings.vmSizeKibana) ? 'Yes' : 'No') : topologySettings.vmKibanaAcceleratedNetworking)
    elasticTags: elasticTags
  }
}

module logstash '../machines/logstash-resources.bicep' = if (topologySettings.logstash == 'Yes') {
  name: 'logstash'
  params: {
    vm: {
      shared: commonVmSettings
      namespace: '${commonVmSettings.namespacePrefix}logstash-'
      installScript: osSettings.extensionSettings.logstash
      size: topologySettings.vmSizeLogstash
      storageAccountType: 'Standard_LRS'
      count: topologySettings.vmLogstashCount
      backendPools: []
      imageReference: osSettings.imageReference
      platformFaultDomainCount: platformFaultDomainCount
      acceleratedNetworking: ((topologySettings.vmLogstashAcceleratedNetworking == 'Default') ? (contains(vmAcceleratedNetworking, topologySettings.vmSizeLogstash) ? 'Yes' : 'No') : topologySettings.vmLogstashAcceleratedNetworking)
      nsg: ''
      standardInternalLoadBalancer: false
    }
    elasticTags: elasticTags
  }
}

output jumpboxFqdn string = topologySettings.jumpbox == 'yes' ? jumpbox.outputs.fqdn : ''
