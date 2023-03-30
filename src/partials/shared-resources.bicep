@description('Location where resources will be provisioned')
param location string

@description('Storage account used for share virtual machine images')
param storageAccountName string

@description('Existing storage account used to configure Azure Repository plugin')
param azureCloudStorageAccount object = {
  name: ''
  resourceGroup: ''
  install: 'No'
}

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {}
  tags: {
    provider: toUpper(elasticTags.provider)
  }
}

output sharedStorageAccountId string = storageAccount.id
output sharedStorageAccountSuffix string = replace(replace(storageAccount.properties.primaryEndpoints.blob, 'https://${storageAccountName}.blob.', ''), '/', '')
output existingStorageAccountSuffix string = (((!empty(azureCloudStorageAccount.name)) && (azureCloudStorageAccount.install == 'Yes')) ? replace(replace(reference(resourceId(azureCloudStorageAccount.resourceGroup, 'Microsoft.Storage/storageAccounts', azureCloudStorageAccount.name), '2019-04-01').primaryEndpoints.blob, 'https://${azureCloudStorageAccount.name}.blob.', ''), '/', '') : '')
