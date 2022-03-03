@description('The base URI where artifacts required by this template are located including a trailing \'/\'')
param _artifactsLocation string

@description('The sasToken required to access _artifactsLocation.  When the template is deployed using the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured.')
@secure()
param _artifactsLocationSasToken string = ''

@description('The Elasticsearch settings')
param esSettings object

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object

@description('Shared VM settings')
param commonVmSettings object

@description('Aggregate for topology variable')
param topologySettings object

@description('Network settings')
param networkSettings object

@description('The storage settings for the Azure Cloud plugin')
@secure()
param azureCloudStorageAccount object

@description('The public IP address for Kibana')
param kibanaIp string

@description('The shared storage settings')
@secure()
param sharedStorageAccount object

var quote = '\''
var doublequote = '"'
var backslash = '\\'
var escapedQuote = '${quote}${doublequote}${quote}${doublequote}${quote}'
var namespacePrefix = topologySettings.vmHostNamePrefix
var kibanaDomainName = ((!empty(esSettings.samlMetadataUri)) ? ((!empty(esSettings.samlServiceProviderUri)) ? esSettings.samlServiceProviderUri : kibanaIp) : '')
var loadBalancerIp = '${((networkSettings.https == 'Yes') ? 'https' : 'http')}://${topologySettings.vNetLoadBalancerIp}:9200'
var dataNodeShortOpts = {
  No: 'z'
  Yes: ''
}
var dataNodeShortOpt = dataNodeShortOpts[topologySettings.dataNodesAreMasterEligible]
var dedicatedMasterNodesShortOpts = {
  No: 'd'
  Yes: ''
}
var dedicatedMasterNodesShortOpt = dedicatedMasterNodesShortOpts[topologySettings.dataNodesAreMasterEligible]
var installAzureCloudPluginShortOpts = {
  No: ''
  Yes: 'j'
}
var installAzureCloudPluginShortOpt = installAzureCloudPluginShortOpts[azureCloudStorageAccount.install]
var azureCloudStorageName = ((azureCloudStorageAccount.install == 'Yes') ? (empty(azureCloudStorageAccount.name) ? sharedStorageAccount.name : azureCloudStorageAccount.name) : '')
var azureCloudStorageKey = ((azureCloudStorageAccount.install == 'Yes') ? (empty(azureCloudStorageAccount.key) ? sharedStorageAccount.key : azureCloudStorageAccount.key) : '')
var azureCloudStorageSuffix = ((azureCloudStorageAccount.install == 'Yes') ? (empty(azureCloudStorageAccount.name) ? sharedStorageAccount.suffix : azureCloudStorageAccount.suffix) : '')
var installPluginsShortOpts = {
  No: ''
  Yes: 'l'
}
var installPluginsShortOpt = installPluginsShortOpts[esSettings.installPlugins]
var commonShortOpts = '${dedicatedMasterNodesShortOpt}${installPluginsShortOpt}${installAzureCloudPluginShortOpt}n '
var commonInstallParams = '${quote}${esSettings.clusterName}${quote} -v ${quote}${esSettings.version}${quote} -m ${esSettings.heapSize} -A ${quote}${replace(esSettings.securityAdminPwd, quote, escapedQuote)}${quote} -R ${quote}${replace(esSettings.securityRemoteMonitoringPwd, quote, escapedQuote)}${quote} -K ${quote}${replace(esSettings.securityKibanaPwd, quote, escapedQuote)}${quote} -S ${quote}${replace(esSettings.securityLogstashPwd, quote, escapedQuote)}${quote} -F ${quote}${replace(esSettings.securityBeatsPwd, quote, escapedQuote)}${quote} -M ${quote}${replace(esSettings.securityApmPwd, quote, escapedQuote)}${quote} -B ${quote}${replace(esSettings.securityBootstrapPwd, quote, escapedQuote)}${quote} -Z ${topologySettings.vmDataNodeCount} -p ${quote}${namespacePrefix}${quote} -a ${quote}${azureCloudStorageName}${quote} -k ${quote}${azureCloudStorageKey}${quote} -E ${quote}${azureCloudStorageSuffix}${quote} -L ${quote}${esSettings.installAdditionalPlugins}${quote} -C ${quote}${replace(replace(esSettings.yamlConfiguration, quote, escapedQuote), '${backslash}${doublequote}', doublequote)}${quote} -D ${quote}${topologySettings.vNetLoadBalancerIp}${quote} -H ${quote}${esSettings.httpCertBlob}${quote} -G ${quote}${replace(esSettings.httpCertPassword, quote, escapedQuote)}${quote} -V ${quote}${esSettings.httpCaCertBlob}${quote} -J ${quote}${replace(esSettings.httpCaCertPassword, quote, escapedQuote)}${quote} -T ${quote}${esSettings.transportCaCertBlob}${quote} -W ${quote}${replace(esSettings.transportCaCertPassword, quote, escapedQuote)}${quote} -N ${quote}${replace(esSettings.transportCertPassword, quote, escapedQuote)}${quote} -O ${quote}${esSettings.samlMetadataUri}${quote} -P ${quote}${kibanaDomainName}${quote}'
var ubuntuScripts = [
  uri(_artifactsLocation, 'scripts/elasticsearch-install.sh${_artifactsLocationSasToken}')
  uri(_artifactsLocation, 'scripts/kibana-install.sh${_artifactsLocationSasToken}')
  uri(_artifactsLocation, 'scripts/logstash-install.sh${_artifactsLocationSasToken}')
  uri(_artifactsLocation, 'scripts/vm-disk-utils-0.1.sh${_artifactsLocationSasToken}')
  uri(_artifactsLocation, 'scripts/java-install.sh${_artifactsLocationSasToken}')
]

var ubuntuSettings = {
  imageReference: {
    publisher: 'Canonical'
    offer: 'UbuntuServer'
    sku: '16.04.0-LTS'
    version: 'latest'
  }
  managementPort: 22
  extensionSettings: {
    master: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: ubuntuScripts
      }
      protectedSettings: {
        commandToExecute: 'bash elasticsearch-install.sh -x${commonShortOpts}${commonInstallParams}'
      }
    }
    client: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: ubuntuScripts
      }
      protectedSettings: {
        commandToExecute: 'bash elasticsearch-install.sh -y${commonShortOpts}${commonInstallParams}'
      }
    }
    data: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: ubuntuScripts
      }
      protectedSettings: {
        commandToExecute: 'bash elasticsearch-install.sh -${dataNodeShortOpt}${commonShortOpts}${commonInstallParams}'
      }
    }
    kibana: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: ubuntuScripts
      }
      protectedSettings: {
        commandToExecute: 'bash kibana-install.sh -${installPluginsShortOpt}n ${quote}${esSettings.clusterName}${quote} -v ${quote}${esSettings.version}${quote} -u ${quote}${loadBalancerIp}${quote} -S ${quote}${replace(esSettings.securityKibanaPwd, quote, escapedQuote)}${quote} -C ${quote}${topologySettings.kibanaCertBlob}${quote} -K ${quote}${topologySettings.kibanaKeyBlob}${quote} -P ${quote}${replace(topologySettings.kibanaKeyPassphrase, quote, escapedQuote)}${quote} -Y ${quote}${replace(replace(topologySettings.kibanaYaml, quote, escapedQuote), '${backslash}${doublequote}', doublequote)}${quote} -H ${quote}${esSettings.httpCertBlob}${quote} -G ${quote}${replace(esSettings.httpCertPassword, quote, escapedQuote)}${quote} -V ${quote}${esSettings.httpCaCertBlob}${quote} -J ${quote}${replace(esSettings.httpCaCertPassword, quote, escapedQuote)}${quote} -U ${quote}${kibanaDomainName}${quote}'
      }
    }
    logstash: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: ubuntuScripts
      }
      protectedSettings: {
        commandToExecute: 'bash logstash-install.sh -${installPluginsShortOpt}v ${quote}${esSettings.version}${quote} -m ${topologySettings.logstashHeapSize} -u ${quote}${loadBalancerIp}${quote} -S ${quote}${replace(esSettings.securityLogstashPwd, quote, escapedQuote)}${quote} -L ${quote}${topologySettings.logstashPlugins}${quote} -c ${quote}${topologySettings.logstashConf}${quote} -K ${quote}${replace(topologySettings.logstashKeystorePwd, quote, escapedQuote)}${quote} -Y ${quote}${replace(replace(topologySettings.logstashYaml, quote, escapedQuote), '${backslash}${doublequote}', doublequote)}${quote} -H ${quote}${esSettings.httpCertBlob}${quote} -G ${quote}${replace(esSettings.httpCertPassword, quote, escapedQuote)}${quote} -V ${quote}${esSettings.httpCaCertBlob}${quote} -J ${quote}${replace(esSettings.httpCaCertPassword, quote, escapedQuote)}${quote}'
      }
    }
  }
}

module elasticSearchNodes '../partials/node-resources.bicep' = {
  name: 'elasticsearch-nodes'
  params: {
    osSettings: ubuntuSettings
    commonVmSettings: commonVmSettings
    topologySettings: topologySettings
    networkSettings: networkSettings
    elasticTags: elasticTags
  }
}

output jumpboxFqdn string = elasticSearchNodes.outputs.jumpboxFqdn
