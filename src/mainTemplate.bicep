@description('The base URI where artifacts required by this template are located, including a trailing \'/\'')
param _artifactsLocation string = 'https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/'

@description('The sasToken required to access _artifactsLocation. When the template is deployed using the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured.')
@secure()
param _artifactsLocationSasToken string = ''

@description('Unique identifiers to allow the Azure Infrastructure to understand the origin of resources deployed to Azure. You do not need to supply a value for this.')
param elasticTags object = {
  provider: '648D2193-0CE0-4EFB-8A82-AF9792184FD9'
  tracking: 'pid-B2C934E3-29F3-4194-BFD2-4F1370B78E0C'
}

@description('Elastic Stack version to install')
@allowed([
  '6.8.14'
  '7.4.2'
  '7.5.2'
  '7.6.2'
  '7.7.1'
  '7.8.1'
  '7.9.3'
  '7.10.2'
  '7.11.1'
  '7.17.0'
])
param esVersion string = '7.11.1'

@description('The name of the Elasticsearch cluster')
param esClusterName string = 'elasticsearch'

@description('Set up an internal or external load balancer, or use Application Gateway (gateway) for load balancing and SSL offload. If you are setting up Elasticsearch on a publicly available endpoint, it is *strongly recommended* to secure your nodes with a product like the Elastic Stack\'s Security features')
@allowed([
  'internal'
  'external'
  'gateway'
])
param loadBalancerType string = 'internal'

@description('The internal load balancer SKU type.')
@allowed([
  'Basic'
  'Standard'
])
param loadBalancerInternalSku string = 'Basic'

@description('The external load balancer SKU type. Only valid when loadBalancerType is \'external\'')
@allowed([
  'Basic'
  'Standard'
])
param loadBalancerExternalSku string = 'Basic'

@description('Choose whether to install Azure Repository plugin. The plugin allows a Azure storage account to be used for snapshot and restore. If azureCloudStorageAccountName and azureCloudStorageAccountKey are not supplied, will use the shared storage account deployed.')
@allowed([
  'Yes'
  'No'
])
param azureCloudPlugin string = 'No'

@description('The name of an existing storage account to use for snapshots with Azure Repository plugin. Must be between 3 and 24 alphanumeric lowercase or characters or numbers.')
@maxLength(24)
param azureCloudStorageAccountName string = ''

@description('The name of an existing resource group in which the storage account to use for snapshots with Azure Repository plugin is located. Must be 90 character or less')
@maxLength(90)
param azureCloudStorageAccountResourceGroup string = ''

@description('Install a trial license to enable access to the Elastic Stack platinum features for 30 days. For Elastisearch less than version 6.3.0, a value of \'Yes\' enables these features by installing the X-Pack plugin into each deployed Elastic Stack product. For Elastisearch less than version 6.3.0, a value of \'No\' does not install the X-Pack plugin and the Elastic Stack is deployed with features available under OSS. For Elasticsearch 6.3.0+, a value of \'No\' deploys the Elastic Stack with the basic license level features available.')
@allowed([
  'Yes'
  'No'
])
param xpackPlugins string = 'Yes'

@description('Additional Elasticsearch plugins to install.  Each plugin must be separated by a semicolon. e.g. analysis-icu;ingest-geoip')
param esAdditionalPlugins string = ''

@description('Additional configuration for Elasticsearch yaml configuration file. Each line must be separated by a newline character e.g. action.auto_create_index: .security\nindices.queries.cache.size:5%')
param esAdditionalYaml string = ''

@description('The size, in megabytes, of memory to allocate on each Elasticsearch node for the JVM heap. If unspecified, 50% of the available memory will be allocated to Elasticsearch heap, up to a maximum of 31744MB (~32GB).')
param esHeapSize int = 0

@description('A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure HTTP layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
param esHttpCertBlob string = ''

@description('The password for the PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure HTTP layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
@secure()
param esHttpCertPassword string = ''

@description('A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure HTTP layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
param esHttpCaCertBlob string = ''

@description('The password for the PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure HTTP layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
@secure()
param esHttpCaCertPassword string = ''

@description('A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure Transport layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
param esTransportCaCertBlob string = ''

@description('The password for the PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure Transport layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
@secure()
param esTransportCaCertPassword string = ''

@description('The password for the generated certificate used to secure Transport layer of Elasticsearch. Requires xpackPlugins be set to \'Yes\' or esVersion to be >= 6.8.0 and < 7.0.0, or >= 7.1.0')
@secure()
param esTransportCertPassword string = ''

@description('The URI from which the metadata file for the Identity Provider can be retrieved to configure SAML Single-Sign-On')
param samlMetadataUri string = ''

@description('The public URI for the Service Provider to configure SAML Single-Sign-On. If samlMetadataUri is provided but a value is not provided for samlServiceProviderUri, the public domain name for the Kibana instance will be used')
param samlServiceProviderUri string = ''

@description('Provision a machine with Kibana on it')
@allowed([
  'Yes'
  'No'
])
param kibana string = 'Yes'

@description('Size of the Kibana node')
@allowed([
  'Standard_A2_v2'
  'Standard_A4_v2'
  'Standard_A8_v2'
  'Standard_A2m_v2'
  'Standard_A4m_v2'
  'Standard_A8m_v2'
  'Standard_D1_v2'
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_D2as_v4'
  'Standard_D4as_v4'
  'Standard_D8as_v4'
  'Standard_D16as_v4'
  'Standard_D32as_v4'
  'Standard_D2_v3'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D48_v3'
  'Standard_D64_v3'
  'Standard_DS1_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  'Standard_E2_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_E2as_v4'
  'Standard_E4as_v4'
  'Standard_E8as_v4'
  'Standard_E16as_v4'
  'Standard_E20as_v4'
  'Standard_E32as_v4'
  'Standard_F1'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F1s'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_G1'
  'Standard_G2'
  'Standard_G3'
  'Standard_G4'
  'Standard_G5'
  'Standard_GS1'
  'Standard_GS2'
  'Standard_GS3'
  'Standard_GS4'
  'Standard_GS5'
  'Standard_L4s'
  'Standard_L8s'
  'Standard_L16s'
  'Standard_L32s'
  'Standard_L8s_v2'
  'Standard_L16s_v2'
  'Standard_L32s_v2'
  'Standard_L48s_v2'
  'Standard_L64s_v2'
  'Standard_L80s_v2'
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
])
param vmSizeKibana string = 'Standard_A2_v2'

@description('Whether to enable accelerated networking for Kibana, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Default'
  'Yes'
  'No'
])
param vmKibanaAcceleratedNetworking string = 'Default'

@description('A Base-64 encoded form of the PEM certificate (.crt) to secure HTTP communication between the browser and Kibana.')
param kibanaCertBlob string = ''

@description('A Base-64 encoded form of the PEM private key (.key) to secure HTTP communication between the browser and Kibana.')
@secure()
param kibanaKeyBlob string = ''

@description('The passphrase to decrypt the private key. Optional as the key may not be encrypted.')
@secure()
param kibanaKeyPassphrase string = ''

@description('Additional configuration for Kibana yaml configuration file. Each line must be separated by a newline character e.g. server.ssl.enabled: true\nkibana.defaultAppId: "home"')
param kibanaAdditionalYaml string = ''

@description('Provision machines with Logstash')
@allowed([
  'Yes'
  'No'
])
param logstash string = 'No'

@description('Size of the Logstash nodes')
@allowed([
  'Standard_A1_v2'
  'Standard_A2_v2'
  'Standard_A4_v2'
  'Standard_A8_v2'
  'Standard_A2m_v2'
  'Standard_A4m_v2'
  'Standard_A8m_v2'
  'Standard_D1_v2'
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_D2as_v4'
  'Standard_D4as_v4'
  'Standard_D8as_v4'
  'Standard_D16as_v4'
  'Standard_D32as_v4'
  'Standard_D2_v3'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D48_v3'
  'Standard_D64_v3'
  'Standard_DS1_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  'Standard_E2_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_E2as_v4'
  'Standard_E4as_v4'
  'Standard_E8as_v4'
  'Standard_E16as_v4'
  'Standard_E20as_v4'
  'Standard_E32as_v4'
  'Standard_F1'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F1s'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_G1'
  'Standard_G2'
  'Standard_G3'
  'Standard_G4'
  'Standard_G5'
  'Standard_GS1'
  'Standard_GS2'
  'Standard_GS3'
  'Standard_GS4'
  'Standard_GS5'
  'Standard_L4s'
  'Standard_L8s'
  'Standard_L16s'
  'Standard_L32s'
  'Standard_L8s_v2'
  'Standard_L16s_v2'
  'Standard_L32s_v2'
  'Standard_L48s_v2'
  'Standard_L64s_v2'
  'Standard_L80s_v2'
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
])
param vmSizeLogstash string = 'Standard_DS1_v2'

@description('The number of Logstash VMs to deploy')
@minValue(1)
param vmLogstashCount int = 1

@description('Whether to enable accelerated networking for Logstash, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Default'
  'Yes'
  'No'
])
param vmLogstashAcceleratedNetworking string = 'Default'

@description('The size, in megabytes, of memory to allocate to Logstash for the JVM heap. If unspecified, will default to 1GB')
param logstashHeapSize int = 0

@description('base 64 encoded form of a Logstash conf file to deploy.')
@secure()
param logstashConf string = ''

@description('Password for the Logstash keystore.')
@secure()
param logstashKeystorePassword string = ''

@description('Additional Logstash plugins to install.  Each plugin must be separated by a semicolon. e.g. logstash-input-azure_event_hubs;logstash-input-http_poller')
param logstashAdditionalPlugins string = ''

@description('Additional configuration for Logstash yaml configuration file. Each line must be separated by a newline character e.g. pipeline.batch.size: 125\npipeline.batch.delay: 50')
param logstashAdditionalYaml string = ''

@description('Optionally add a virtual machine to the deployment which can be used to connect and manage virtual machines within the cluster. Not required if installing Kibana, as Kibana can be used as a jumpbox')
@allowed([
  'Yes'
  'No'
])
param jumpbox string = 'No'

@description('The prefix to use for resources and hostnames when naming virtual machines in the cluster. Can be up to 5 characters in length, must begin with an alphanumeric character and can contain alphanumeric and hyphen characters. Hostnames are used for resolution of master nodes so if you are deploying a cluster into an existing virtual network containing an existing Elasticsearch cluster, be sure to set this to a unique prefix to differentiate the hostnames of this cluster from an existing cluster')
@maxLength(5)
param vmHostNamePrefix string = ''

@description('Size of the Elasticsearch data nodes')
@allowed([
  'Standard_A1_v2'
  'Standard_A2_v2'
  'Standard_A4_v2'
  'Standard_A8_v2'
  'Standard_A2m_v2'
  'Standard_A4m_v2'
  'Standard_A8m_v2'
  'Standard_D1_v2'
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_D2as_v4'
  'Standard_D4as_v4'
  'Standard_D8as_v4'
  'Standard_D16as_v4'
  'Standard_D32as_v4'
  'Standard_D2_v3'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D48_v3'
  'Standard_D64_v3'
  'Standard_DS1_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  'Standard_E2_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_E2as_v4'
  'Standard_E4as_v4'
  'Standard_E8as_v4'
  'Standard_E16as_v4'
  'Standard_E20as_v4'
  'Standard_E32as_v4'
  'Standard_F1'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F1s'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_G1'
  'Standard_G2'
  'Standard_G3'
  'Standard_G4'
  'Standard_G5'
  'Standard_GS1'
  'Standard_GS2'
  'Standard_GS3'
  'Standard_GS4'
  'Standard_GS5'
  'Standard_L4s'
  'Standard_L8s'
  'Standard_L16s'
  'Standard_L32s'
  'Standard_L8s_v2'
  'Standard_L16s_v2'
  'Standard_L32s_v2'
  'Standard_L48s_v2'
  'Standard_L64s_v2'
  'Standard_L80s_v2'
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
])
param vmSizeDataNodes string = 'Standard_DS1_v2'

@description('Whether to enable accelerated networking for data nodes, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Default'
  'Yes'
  'No'
])
param vmDataNodeAcceleratedNetworking string = 'Default'

@description('Number of disks to attach to each data node in RAID 0 setup. If the number of disks selected is more than can be attached to the data node VM size, the maximum number of disks that can be attached will be used. If 1 disk is selected, it is not RAIDed. If 0 disks are selected, the temporary disk will be used to store Elasticsearch data. IMPORTANT: The temporary disk is ephemeral in nature so be sure you know the trade-offs when choosing 0 disks.')
@minValue(0)
param vmDataDiskCount int = 64

@description('The disk size of each attached managed disk, 32GiB, 64GiB, 128GiB, 256 GiB, 512GiB, 1TiB, 2TiB, 4TiB, 8TiB, 16TiB and 32TiB. Default is 1TiB. For Premium Storage, this equates to P6, P10, P15, P20, P30, P40, P50, P60, P70 and P80, respectively.')
@allowed([
  '32GiB'
  '64GiB'
  '128GiB'
  '256GiB'
  '512GiB'
  '1TiB'
  '2TiB'
  '4TiB'
  '8TiB'
  '16TiB'
  '32TiB'
])
param vmDataDiskSize string = '1TiB'

@description('Number of Elasticsearch data nodes')
@minValue(1)
param vmDataNodeCount int = 3

@description('The storage account type of the attached managed disks and OS disks (Default or Standard). The Default storage account type will be Premium Storage for VMs that support Premium Storage and Standard HDD Storage for those that do not.')
@allowed([
  'Default'
  'Standard'
])
param storageAccountType string = 'Default'

@description('Make all data nodes master-eligible. This can be useful for small Elasticsearch cluster deployments, but for larger deployments it is recommended to use dedicated master nodes')
@allowed([
  'Yes'
  'No'
])
param dataNodesAreMasterEligible string = 'No'

@description('Size of the Elasticsearch master nodes, if data nodes are not master eligible, 3 master nodes of this size will be provisioned')
@allowed([
  'Standard_A1_v2'
  'Standard_A2_v2'
  'Standard_A4_v2'
  'Standard_A8_v2'
  'Standard_A2m_v2'
  'Standard_A4m_v2'
  'Standard_A8m_v2'
  'Standard_D1_v2'
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_D2as_v4'
  'Standard_D4as_v4'
  'Standard_D8as_v4'
  'Standard_D16as_v4'
  'Standard_D32as_v4'
  'Standard_D2_v3'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D48_v3'
  'Standard_D64_v3'
  'Standard_DS1_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  'Standard_E2_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_E2as_v4'
  'Standard_E4as_v4'
  'Standard_E8as_v4'
  'Standard_E16as_v4'
  'Standard_E20as_v4'
  'Standard_E32as_v4'
  'Standard_F1'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F1s'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_G1'
  'Standard_G2'
  'Standard_G3'
  'Standard_G4'
  'Standard_G5'
  'Standard_GS1'
  'Standard_GS2'
  'Standard_GS3'
  'Standard_GS4'
  'Standard_GS5'
  'Standard_L4s'
  'Standard_L8s'
  'Standard_L16s'
  'Standard_L32s'
  'Standard_L8s_v2'
  'Standard_L16s_v2'
  'Standard_L32s_v2'
  'Standard_L48s_v2'
  'Standard_L64s_v2'
  'Standard_L80s_v2'
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
])
param vmSizeMasterNodes string = 'Standard_DS1_v2'

@description('Whether to enable accelerated networking for master nodes, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Default'
  'Yes'
  'No'
])
param vmMasterNodeAcceleratedNetworking string = 'Default'

@description('Number of Elasticsearch coordinating nodes to provision. A value of 0 puts the data nodes in the load balancer backend pool')
@minValue(0)
param vmClientNodeCount int = 0

@description('Size of the Elasticsearch coordinating nodes')
@allowed([
  'Standard_A1_v2'
  'Standard_A2_v2'
  'Standard_A4_v2'
  'Standard_A8_v2'
  'Standard_A2m_v2'
  'Standard_A4m_v2'
  'Standard_A8m_v2'
  'Standard_D1_v2'
  'Standard_D2_v2'
  'Standard_D3_v2'
  'Standard_D4_v2'
  'Standard_D5_v2'
  'Standard_D11_v2'
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D15_v2'
  'Standard_D2as_v4'
  'Standard_D4as_v4'
  'Standard_D8as_v4'
  'Standard_D16as_v4'
  'Standard_D32as_v4'
  'Standard_D2_v3'
  'Standard_D4_v3'
  'Standard_D8_v3'
  'Standard_D16_v3'
  'Standard_D32_v3'
  'Standard_D48_v3'
  'Standard_D64_v3'
  'Standard_DS1_v2'
  'Standard_DS2_v2'
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_DS11_v2'
  'Standard_DS12_v2'
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_DS15_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_D48s_v3'
  'Standard_D64s_v3'
  'Standard_E2_v3'
  'Standard_E4_v3'
  'Standard_E8_v3'
  'Standard_E16_v3'
  'Standard_E32_v3'
  'Standard_E64_v3'
  'Standard_E64i_v3'
  'Standard_E2s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
  'Standard_E64s_v3'
  'Standard_E64is_v3'
  'Standard_E2as_v4'
  'Standard_E4as_v4'
  'Standard_E8as_v4'
  'Standard_E16as_v4'
  'Standard_E20as_v4'
  'Standard_E32as_v4'
  'Standard_F1'
  'Standard_F2'
  'Standard_F4'
  'Standard_F8'
  'Standard_F16'
  'Standard_F1s'
  'Standard_F2s'
  'Standard_F4s'
  'Standard_F8s'
  'Standard_F16s'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'
  'Standard_G1'
  'Standard_G2'
  'Standard_G3'
  'Standard_G4'
  'Standard_G5'
  'Standard_GS1'
  'Standard_GS2'
  'Standard_GS3'
  'Standard_GS4'
  'Standard_GS5'
  'Standard_L4s'
  'Standard_L8s'
  'Standard_L16s'
  'Standard_L32s'
  'Standard_L8s_v2'
  'Standard_L16s_v2'
  'Standard_L32s_v2'
  'Standard_L48s_v2'
  'Standard_L64s_v2'
  'Standard_L80s_v2'
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
])
param vmSizeClientNodes string = 'Standard_DS1_v2'

@description('Whether to enable accelerated networking for coordinating nodes, which enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. Valid only for specific VM SKUs')
@allowed([
  'Default'
  'Yes'
  'No'
])
param vmClientNodeAcceleratedNetworking string = 'Default'

@description('Admin username used when provisioning virtual machines')
param adminUsername string

@description('Choose a password or ssh public key for the Admin username used to access virtual machines')
@allowed([
  'password'
  'sshPublicKey'
])
param authenticationType string = 'password'

@description('Admin password')
@secure()
param adminPassword string = ''

@description('Admin ssh public key')
@secure()
param sshPublicKey string = ''

@description('Password for the bootstrap.password to add to the keystore in 6.x. If no value is supplied, a 13 character password will be generated using the uniqueString() function')
@secure()
param securityBootstrapPassword string

@description('Password for the built-in \'elastic\' user. Should be 12 characters or more, with a minimum of 6 characters')
@secure()
param securityAdminPassword string

@description('Password for the built-in \'kibana\' user. Should be 12 characters or more, with a minimum of 6 characters')
@secure()
param securityKibanaPassword string

@description('Password for the built-in \'logstash_system\' user. Should be 12 characters or more, with a minimum of 6 characters')
@secure()
param securityLogstashPassword string

@description('Password for the built-in \'beats_system\' user. Should be 12 characters or more, with a minimum of 6 characters. Required for Elasticsearch 6.3.0+ when xpackPlugins is \'Yes\'')
@secure()
param securityBeatsPassword string

@description('Password for the built-in \'apm_system\' user. Should be 12 characters or more, with a minimum of 6 characters. Required for Elasticsearch 6.5.0+ when xpackPlugins is \'Yes\'')
@secure()
param securityApmPassword string

@description('Password for the built-in \'remote_monitoring_user\' user. Should be 12 characters or more, with a minimum of 6 characters. Required for Elasticsearch 6.5.0+ when xpackPlugins is \'Yes\'')
@secure()
param securityRemoteMonitoringPassword string

@description('Location where resources will be provisioned. By default, the template deploys the resources to the same location as the resource group. If specified, must be a valid Azure location e.g. \'australiasoutheast\'')
param location string = resourceGroup().location

@description('Choose to create a new Virtual Network or use an existing one. If choosing an existing network, the subnet also needs to exist.')
@allowed([
  'new'
  'existing'
])
param vNetNewOrExisting string = 'new'

@description('Virtual Network Name')
param vNetName string = 'es-net'

@description('The name of the resource group for the existing Virtual Network. Required when using an existing Virtual Network')
param vNetExistingResourceGroup string = ''

@description('The address prefix size to use for a New Virtual Network. Required when creating a new Virtual Network')
param vNetNewAddressPrefix string = '10.0.0.0/24'

@description('The static IP address for the internal load balancer. This must be an available IP address in the specified subnet')
param vNetLoadBalancerIp string = '10.0.0.4'

@description('Subnet name to use for Elasticsearch nodes')
param vNetClusterSubnetName string = 'es-subnet'

@description('The address space of the subnet. Required when creating a new Virtual Network')
param vNetNewClusterSubnetAddressPrefix string = '10.0.0.0/25'

@description('Subnet name to use for the Application Gateway. Required when selecting Application Gateway for load balancing')
param vNetAppGatewaySubnetName string = 'es-gateway-subnet'

@description('The address space of the Application Gateway subnet. Required when creating a new Virtual Network and selecting Application Gateway for load balancing')
param vNetNewAppGatewaySubnetAddressPrefix string = '10.0.0.128/28'

@description('The tier of the Application Gateway. Required when selecting Application Gateway for load balancing')
@allowed([
  'Standard'
  'WAF'
])
param appGatewayTier string = 'Standard'

@description('The size of the Application Gateway. Medium or above is recommended for Production clusters, and required when using WAF tier')
@allowed([
  'Small'
  'Medium'
  'Large'
])
param appGatewaySku string = 'Medium'

@description('The number of instances of the Application Gateway. A minimum of 2 is recommended for Production clusters. Required when selecting Application Gateway for load balancing')
@minValue(1)
@maxValue(10)
param appGatewayCount int = 2

@description('A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the key and certificate for the Application Gateway. This certificate is used to secure HTTPS connections to the Application Gateway')
param appGatewayCertBlob string = ''

@description('The password for the PKCS#12 archive (.p12/.pfx) containing the key and certificate for the Application Gateway.')
@secure()
param appGatewayCertPassword string = ''

@description('The firewall status of the Application Gateway. Required when selecting Application Gateway for load balancing and using WAF tier.')
@allowed([
  'Enabled'
  'Disabled'
])
param appGatewayWafStatus string = 'Enabled'

@description('The firewall mode of the Application Gateway. Required when selecting Application Gateway for load balancing and using WAF tier.')
@allowed([
  'Detection'
  'Prevention'
])
param appGatewayWafMode string = 'Detection'

@description('The Base-64 encoded certificate (.cer) used to secure the HTTP layer of Elasticsearch. Used by the Application Gateway to whitelist certificates used by the backend pool. Must be set if using esHttpCertBlob to secure the HTTP layer of Elasticsearch')
param appGatewayEsHttpCertBlob string = ''

var esVersionMajor = int(split(esVersion, '.')[0])
var esVersionMinor = int(split(esVersion, '.')[1])
var resourceGroupLocation = location
var azureCloudStorageAccount = {
  name: azureCloudStorageAccountName
  resourceGroup: azureCloudStorageAccountResourceGroup
  install: azureCloudPlugin
}
var esSettings = {
  clusterName: esClusterName
  version: esVersion
  installPlugins: xpackPlugins
  installAdditionalPlugins: esAdditionalPlugins
  yamlConfiguration: esAdditionalYaml
  heapSize: esHeapSize
  httpCertBlob: esHttpCertBlob
  httpCertPassword: esHttpCertPassword
  httpCaCertBlob: esHttpCaCertBlob
  httpCaCertPassword: esHttpCaCertPassword
  transportCaCertBlob: esTransportCaCertBlob
  transportCaCertPassword: esTransportCaCertPassword
  transportCertPassword: esTransportCertPassword
  securityAdminPwd: securityAdminPassword
  securityKibanaPwd: securityKibanaPassword
  securityLogstashPwd: securityLogstashPassword
  securityBeatsPwd: securityBeatsPassword
  securityApmPwd: securityApmPassword
  securityRemoteMonitoringPwd: securityRemoteMonitoringPassword
  securityBootstrapPwd: ((!empty(securityBootstrapPassword)) ? securityBootstrapPassword : uniqueString(resourceGroup().id, deployment().name, securityAdminPassword))
  samlMetadataUri: samlMetadataUri
  samlServiceProviderUri: samlServiceProviderUri
}
var networkResourceGroupMap = {
  new: resourceGroup().name
  existing: vNetExistingResourceGroup
}
var dataSkuSettings = {
  Standard_A1_v2: {
    dataDisks: 2
    storageAccountType: 'Standard_LRS'
  }
  Standard_A2_v2: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_A4_v2: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_A8_v2: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_A2m_v2: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_A4m_v2: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_A8m_v2: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_D1_v2: {
    dataDisks: 2
    storageAccountType: 'Standard_LRS'
  }
  Standard_D2_v2: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_D3_v2: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_D4_v2: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_D5_v2: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_D11_v2: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_D12_v2: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_D13_v2: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_D14_v2: {
    dataDisks: 64
    storageAccountType: 'Standard_LRS'
  }
  Standard_D15_v2: {
    dataDisks: 64
    storageAccountType: 'Standard_LRS'
  }
  Standard_D2as_v4: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_D4as_v4: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_D8as_v4: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_D16as_v4: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_D32as_v4: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_D2_v3: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_D4_v3: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_D8_v3: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_D16_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_D32_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_D48_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_D64_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_DS1_v2: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS2_v2: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS3_v2: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS4_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS5_v2: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS11_v2: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS12_v2: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS13_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS14_v2: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_DS15_v2: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_D2s_v3: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_D4s_v3: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_D8s_v3: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_D16s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_D32s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_D48s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_D64s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E2_v3: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_E4_v3: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_E8_v3: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_E16_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_E32_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_E64_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_E64i_v3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_E2s_v3: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_E4s_v3: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_E8s_v3: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_E16s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E32s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E64s_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E64is_v3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E2as_v4: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_E4as_v4: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_E8as_v4: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_E16as_v4: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E20as_v4: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_E32as_v4: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_F1: {
    dataDisks: 2
    storageAccountType: 'Standard_LRS'
  }
  Standard_F2: {
    dataDisks: 4
    storageAccountType: 'Standard_LRS'
  }
  Standard_F4: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_F8: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_F16: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_F1s: {
    dataDisks: 2
    storageAccountType: 'Premium_LRS'
  }
  Standard_F2s: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_F4s: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_F8s: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_F16s: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_F2s_v2: {
    dataDisks: 4
    storageAccountType: 'Premium_LRS'
  }
  Standard_F4s_v2: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_F8s_v2: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_F16s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_F32s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_F64s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_F72s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_G1: {
    dataDisks: 8
    storageAccountType: 'Standard_LRS'
  }
  Standard_G2: {
    dataDisks: 16
    storageAccountType: 'Standard_LRS'
  }
  Standard_G3: {
    dataDisks: 32
    storageAccountType: 'Standard_LRS'
  }
  Standard_G4: {
    dataDisks: 64
    storageAccountType: 'Standard_LRS'
  }
  Standard_G5: {
    dataDisks: 64
    storageAccountType: 'Standard_LRS'
  }
  Standard_GS1: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_GS2: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_GS3: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_GS4: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_GS5: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_L4s: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_L8s: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_L16s: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_L32s: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_L8s_v2: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_L16s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_L32s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_L48s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_L64s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_L80s_v2: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_M8ms: {
    dataDisks: 8
    storageAccountType: 'Premium_LRS'
  }
  Standard_M16ms: {
    dataDisks: 16
    storageAccountType: 'Premium_LRS'
  }
  Standard_M32ts: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_M32ls: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_M32ms: {
    dataDisks: 32
    storageAccountType: 'Premium_LRS'
  }
  Standard_M64s: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M64ls: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M64ms: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M128s: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M128ms: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M64: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M64m: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M128: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
  Standard_M128m: {
    dataDisks: 64
    storageAccountType: 'Premium_LRS'
  }
}
var dataDiskSizes = {
  '32GiB': 32
  '64GiB': 64
  '128GiB': 128
  '256GiB': 256
  '512GiB': 512
  '1TiB': 1024
  '2TiB': 2048
  '4TiB': 4096
  '8TiB': 8192
  '16TiB': 16384
  '32TiB': 32767
}
var backendPoolConfigurations = {
  internal: [
    {
      id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${vmHostNamePrefix}internal-lb', 'LBBE')
    }
  ]
  external: [
    {
      id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${vmHostNamePrefix}internal-lb', 'LBBE')
    }
    {
      id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${vmHostNamePrefix}external-lb', 'LBBE')
    }
  ]
  gateway: [
    {
      id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${vmHostNamePrefix}internal-lb', 'LBBE')
    }
  ]
}
var lbBackEndPoolsAdded = {
  backendPools: backendPoolConfigurations[loadBalancerType]
}
var lbBackendPoolsRemoved = {
  backendPools: []
}
var dataLoadBalancerOptions = [
  lbBackEndPoolsAdded
  lbBackendPoolsRemoved
]
var clientResourceIndex = ((vmClientNodeCount + 2) % (vmClientNodeCount + 1))
var storageAccountOverrides = {
  Default: dataSkuSettings[vmSizeDataNodes].storageAccountType
  Standard: 'Standard_LRS'
}
var resolvedStorageAccountType = storageAccountOverrides[storageAccountType]
var tmpVmSizeDataDisks = dataSkuSettings[vmSizeDataNodes].dataDisks
var dataDiskOptions = [
  vmDataDiskCount
  tmpVmSizeDataDisks
]
var resolvedDataDiskCount = min(dataDiskOptions)
var kibanaHttps = (((length(kibanaKeyBlob) > 0) && (length(kibanaCertBlob) > 0)) ? 'Yes' : 'No')
var newSubNetStartAddress = (('new' == vNetNewOrExisting) ? first(split(vNetNewClusterSubnetAddressPrefix, '/')) : '')
var newSubNetStartAddressLastOctet = (('new' == vNetNewOrExisting) ? int(last(split(newSubNetStartAddress, '.'))) : 0)
var newSubNetStartAddressFirstOctets = (('new' == vNetNewOrExisting) ? substring(newSubNetStartAddress, 0, lastIndexOf(newSubNetStartAddress, '.')) : '')
var newSubNetReservedStartAddresses = [
  newSubNetStartAddress
  '${newSubNetStartAddressFirstOctets}.${string((newSubNetStartAddressLastOctet + 1))}'
  '${newSubNetStartAddressFirstOctets}.${string((newSubNetStartAddressLastOctet + 2))}'
  '${newSubNetStartAddressFirstOctets}.${string((newSubNetStartAddressLastOctet + 3))}'
]
var newSubNetFirstAvailableAddress = '${newSubNetStartAddressFirstOctets}.${string((newSubNetStartAddressLastOctet + 4))}'
var newOrExistingVNetLoadBalancerIp = (('existing' == vNetNewOrExisting) ? vNetLoadBalancerIp : (contains(newSubNetReservedStartAddresses, vNetLoadBalancerIp) ? newSubNetFirstAvailableAddress : vNetLoadBalancerIp))
var topologySettings = {
  dataNodesAreMasterEligible: dataNodesAreMasterEligible
  vmDataNodeCount: vmDataNodeCount
  vmSizeDataNodes: vmSizeDataNodes
  vmDataNodeStorageAccountType: dataSkuSettings[vmSizeDataNodes].storageAccountType
  vmDataNodeAcceleratedNetworking: vmDataNodeAcceleratedNetworking
  vmHostNamePrefix: vmHostNamePrefix
  vmClientNodeCount: vmClientNodeCount
  vmSizeClientNodes: vmSizeClientNodes
  vmClientNodeAcceleratedNetworking: vmClientNodeAcceleratedNetworking
  vNetLoadBalancerIp: newOrExistingVNetLoadBalancerIp
  vmSizeMasterNodes: vmSizeMasterNodes
  vmMasterNodeAcceleratedNetworking: vmMasterNodeAcceleratedNetworking
  vmSizeKibana: vmSizeKibana
  vmKibanaAcceleratedNetworking: vmKibanaAcceleratedNetworking
  kibana: kibana
  kibanaKeyBlob: kibanaKeyBlob
  kibanaKeyPassphrase: kibanaKeyPassphrase
  kibanaCertBlob: kibanaCertBlob
  kibanaHttps: kibanaHttps
  kibanaYaml: kibanaAdditionalYaml
  vmSizeLogstash: vmSizeLogstash
  vmLogstashCount: vmLogstashCount
  vmLogstashAcceleratedNetworking: vmLogstashAcceleratedNetworking
  logstash: logstash
  logstashHeapSize: logstashHeapSize
  logstashConf: logstashConf
  logstashPlugins: logstashAdditionalPlugins
  logstashYaml: logstashAdditionalYaml
  logstashKeystorePwd: ((!empty(logstashKeystorePassword)) ? logstashKeystorePassword : uniqueString(resourceGroup().id, deployment().name, securityLogstashPassword))
  jumpbox: jumpbox
  dataNodeStorageSettings: {
    accountType: resolvedStorageAccountType
    diskSize: dataDiskSizes[vmDataDiskSize]
    dataDisks: resolvedDataDiskCount
  }
  dataLoadBalancerBackEndPools: dataLoadBalancerOptions[clientResourceIndex].backendPools
  loadBalancerBackEndPools: lbBackEndPoolsAdded.backendPools
}
var networkSettings = {
  name: vNetName
  namespacePrefix: vmHostNamePrefix
  resourceGroup: networkResourceGroupMap[vNetNewOrExisting]
  location: resourceGroupLocation
  addressPrefix: vNetNewAddressPrefix
  https: ((((length(esHttpCertBlob) > 0) || (length(esHttpCaCertBlob) > 0)) && ((xpackPlugins == 'Yes') || ((esVersionMajor >= 7) && (esVersionMinor >= 1)) || ((esVersionMajor == 6) && (esVersionMinor >= 8)))) ? 'Yes' : 'No')
  subnet: {
    name: vNetClusterSubnetName
    addressPrefix: vNetNewClusterSubnetAddressPrefix
    loadbalancerIp: newOrExistingVNetLoadBalancerIp
  }
  applicationGatewaySubnet: {
    name: vNetAppGatewaySubnetName
    addressPrefix: vNetNewAppGatewaySubnetAddressPrefix
  }
  internalSku: loadBalancerInternalSku
  externalSku: loadBalancerExternalSku
}
var commonVmSettings = {
  namespacePrefix: vmHostNamePrefix
  storageAccountName: 'elastic${uniqueString(resourceGroup().id, deployment().name)}'
  location: resourceGroupLocation
  subnet: networkSettings.subnet
  subnetId: resourceId(networkSettings.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', networkSettings.name, networkSettings.subnet.name)
  credentials: {
    adminUsername: adminUsername
    password: adminPassword
    authenticationType: authenticationType
    sshPublicKey: sshPublicKey
  }
}

resource usageTracking 'Microsoft.Resources/deployments@2019-05-01' = {
  name: elasticTags.tracking
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
    }
  }
}

module shared './partials/shared-resources.bicep' = {
  name: 'shared'
  params: {
    location: resourceGroupLocation
    storageAccountName: commonVmSettings.storageAccountName
    azureCloudStorageAccount: azureCloudStorageAccount
    elasticTags: elasticTags
  }
}

module network './networks/virtual-network-resources.bicep' = if (vNetNewOrExisting == 'new') {
  name: 'network'
  params: {
    networkSettings: networkSettings
    loadBalancerType: loadBalancerType
    elasticTags: elasticTags
  }
}

module kibanaIp './ips/kibana-ip-resources.bicep' = if (kibana == 'Yes') {
  name: 'kibana-ip'
  params: {
    location: commonVmSettings.location
    namespace: '${commonVmSettings.namespacePrefix}kibana'
    https: topologySettings.kibanaHttps
    elasticTags: elasticTags
  }
}

module loadBalancer './loadbalancers/load-balancer-resources.bicep' = {
  name: 'load-balancer'
  params: {
    applicationGatewaySettings: {
      skuName: '${appGatewayTier}_${appGatewaySku}'
      tier: appGatewayTier
      instanceCount: appGatewayCount
      certBlob: appGatewayCertBlob
      certPassword: appGatewayCertPassword
      firewallStatus: appGatewayWafStatus
      firewallMode: appGatewayWafMode
      backendCert: appGatewayEsHttpCertBlob
      backendProtocol: (((length(esHttpCertBlob) > 0) || (length(esHttpCaCertBlob) > 0)) ? 'Https' : 'Http')
    }
    loadBalancerType: loadBalancerType
    appGatewayTier: appGatewayTier
    networkSettings: networkSettings
    elasticTags: elasticTags
  }
}

var existingStorageAccountResourceId = ((!empty(azureCloudStorageAccount.name)) && (azureCloudStorageAccount.install == 'Yes')) ? resourceId(azureCloudStorageAccount.resourceGroup, 'Microsoft.Storage/storageAccounts', azureCloudStorageAccount.name) : ''
var sharedStorageAccountResourceId = resourceId(resourceGroupLocation, 'Microsoft.Storage/storageAccounts', commonVmSettings.storageAccountName)

module ubuntuSettings './settings/ubuntuSettings.bicep' = {
  name: 'virtual-machines'
  params: {
    '_artifactsLocation': _artifactsLocation
    '_artifactsLocationSasToken': _artifactsLocationSasToken
    esSettings: esSettings
    topologySettings: topologySettings
    networkSettings: networkSettings
    azureCloudStorageAccount: {
      name: azureCloudStorageAccount.name
      resourceGroup: azureCloudStorageAccount.resourceGroup
      install: azureCloudStorageAccount.install
      key: !empty(existingStorageAccountResourceId) ? listKeys(existingStorageAccountResourceId, '2019-04-01').keys[0].value : ''
      suffix: shared.outputs.existingStorageAccountSuffix
    }
    kibanaIp: kibanaIp.outputs.fqdn
    sharedStorageAccount: {
      name: commonVmSettings.storageAccountName
      key: listKeys(sharedStorageAccountResourceId, '2019-04-01').keys[0].value
      suffix: shared.outputs.sharedStorageAccountSuffix
    }
  }
  dependsOn: [
    network
  ]
}

module elasticSearchNodes './partials/node-resources.bicep' = {
  name: 'elasticsearch-nodes'
  params: {
    osSettings: ubuntuSettings.outputs.ubuntuSettings
    commonVmSettings: commonVmSettings
    topologySettings: topologySettings
    networkSettings: networkSettings
    elasticTags: elasticTags
  }
  dependsOn: []
}

output loadbalancer string = loadBalancer.outputs.fqdn
output kibana string = kibana == 'Yes' ? kibanaIp.outputs.fqdn : ''
output jumpboxssh string = '${adminUsername}@${elasticSearchNodes.outputs.jumpboxFqdn}'
