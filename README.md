# Elastic Stack Azure Marketplace offering

Easily deploy the Elastic Stack of Elasticsearch, Kibana and Logstash to Azure.

This readme provides an overview of usage and features. For more comprehensive documentation, 
please refer to the [**Azure Marketplace and ARM template documentation**](https://www.elastic.co/guide/en/elastic-stack-deploy/current/index.html)

This repository consists of:

* [src/mainTemplate.json](src/mainTemplate.json) - The main Azure Resource Management (ARM) template. 
The template itself is composed of many nested linked templates, with the main template acting as the entry point.
* [src/createUiDefinition](src/createUiDefinition.json) - UI definition file for our Azure Marketplace offering. 
This file produces an output JSON that the ARM template can accept as input parameters.

## Building

After pulling the source, call the following _once_

```sh
npm install
```

to pull in all devDependencies. You may edit the [build/allowedValues.json](build/allowedValues.json) file, which the build uses to patch the ARM template and Marketplace UI definition. Then, run

```sh
npm run build
```

which will validate EditorConfig settings, lint JSON files, patch the template using `build/allowedValues.json`, and create a zip in the `dist` folder.
For more details around developing the template, take a look at the [Development README](build/README.md)

## Azure Marketplace

The [Azure Marketplace Elastic Stack offering](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/elastic.elasticsearch) offers a simplified UI and installation experience over the full power of the ARM template.

It will always bootstrap an Elasticsearch cluster complete with a trial license of the [Elastic Stack's platinum features](https://www.elastic.co/products/stack).

Deploying through the Marketplace is great and easy way to get your feet wet for the first time with Elasticsearch on Azure, but in the long run, you'll want to deploy the templates directly from GitHub using the Azure CLI or PowerShell SDKs.
<a href="#command-line-deploy">Check out the CLI examples.</a>

---

![Example UI Flow](images/ui.gif)

You can view the UI in developer mode by [clicking here](https://portal.azure.com/#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}}). If you feel something is cached improperly use [this client unoptimized link instead](https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}})

## Reporting bugs

Have a look at this [screenshot](images/error-output.png) to see how you can
navigate to the deployment error status message.
Please create an issue with that message and in which resource it occured on our
[github issues](https://github.com/elastic/azure-marketplace/issues)

## ARM template

The output from the Azure Marketplace UI is fed directly to the ARM deployment
template. You can use the ARM template independently, without going through the
Marketplace. In fact, there are many features in the ARM template that are
not exposed within the Marketplace UI, such as configuring

* Azure Storage account to use with Azure Repository plugin for Snapshot/Restore
* Application Gateway to use for SSL/TLS and SSL offload

Check out our [**examples repository**](https://github.com/elastic/azure-marketplace-examples)
for examples of common scenarios and also take a look at the following blog
posts for further information

* [Spinning up a cluster with Elastic's Azure Marketplace template](https://www.elastic.co/blog/spinning-up-a-cluster-with-elastics-azure-marketplace-template)
* [Elasticsearch and Kibana deployments on Azure](https://www.elastic.co/blog/elasticsearch-and-kibana-deployments-on-azure)
* [SAML based Single Sign-On with Elasticsearch and Azure Active Directory](https://www.elastic.co/blog/saml-based-single-sign-on-with-elasticsearch-and-azure-active-directory?blade=tw&hulk=social)

### Elastic Stack features (formerly known as X-Pack)

Starting with Elasticsearch, Kibana and Logstash 6.3.0, The template deploys with Elastic Stack features bundled as part of the deployment, and
includes the free features under the [Basic license](https://www.elastic.co/subscriptions) level.
The [`xpackPlugins`](#x-pack) parameter determines whether a self-generated trial license is applied,
offering a trial period of 30 days to the Platinum license features. A value of `Yes` applies a trial license, a value of `No` applies the Basic license.
The license level applied determines the Elastic Stack features activated to use.

For Elasticsearch, Kibana and Logstash prior to 6.3.0, The [`xpackPlugins`](#x-pack) parameter determines whether X-Pack plugins are installed
and a self-generated trial license is applied. In difference to 6.3.0 however, a value of `No` for `xpackPlugins` means that 
X-Pack plugins are not installed, and therefore does not provide the free features under the Basic license level, offering the Open Source features only.
For these versions, you can install X-Pack plugins and [**register for a free Basic license** to apply to the deployment](https://register.elastic.co/), in 
order to use the free features available under the Basic license level.

## Parameters

The ARM template accepts a _lot_ of parameters, but don't fear! Most of them are **optional** and only used
in conjunction with other parameters. Where a parameter value is not explicitly provided, it will take the default
value defined in the template.

<table>
  <tr><th>Parameter</td><th>Type</th><th>Description</th><th>Default Value</th></tr>

  <tr><td>_artifactsLocation</td><td>string</td>
    <td>The base URI where artifacts required by this template are located, including a trailing '/'.
    <strong>Use to target a specific branch or release tag</strong></td><td>Raw content of the current branch</td></tr>

  <tr><td>_artifactsLocationSasToken</td><td>securestring</td>
    <td>The sasToken required to access <code>_artifactsLocation</code>. When the template is deployed using 
    the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured."</td>
    <td><code>""</code></td></tr>

  <tr><td>location</td><td>string</td>
    <td>The location where to provision all the items in this template. Defaults to inheriting the location
    from the resource group. Any other value must be a valid <a href="https://azure.microsoft.com/regions/">Azure region</a>.
    </td><td><code>[resourceGroup().location]</code></td></tr>

  <tr><td>vmHostNamePrefix</td><td>string</td>
    <td>The prefix to use for hostnames when naming virtual machines in the cluster. Hostnames are used for resolution of master nodes on the network, so if you are deploying a cluster into an existing virtual network containing an existing Elasticsearch cluster, be sure to set this to a unique prefix, to differentiate the hostnames of this cluster from an existing cluster. Can be up to 5 characters in length, must begin with an alphanumeric character and can contain alphanumeric and hyphen characters.
    </td><td><code>""</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Elasticsearch related settings</strong></td></tr>

  <tr><td>esVersion</td><td>string</td>
    <td>A valid supported Elasticsearch version for the target template version. See <a href="https://github.com/elastic/azure-marketplace/blob/master/src/mainTemplate.json">this list for supported versions</a>.
    <strong>Required</strong></td><td>Latest version supported by target template version</td></tr>

  <tr><td>esClusterName</td><td>string</td>
    <td> The name of the Elasticsearch cluster. <strong>Required</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>loadBalancerType</td><td>string</td>
    <td> The load balancer to set up to access the cluster. Can be <code>internal</code>, <code>external</code> or <code>gateway</code>. 
    <ul>
    <li>By choosing <code>internal</code>, only an internal load balancer is deployed. Useful when connecting to the cluster happens from inside the Virtual Network</li>
    <li>By choosing <code>external</code>, both internal and external load balancers will be deployed. Kibana communicates with the cluster through the internal
    load balancer.</li>
    <li>By choosing <code>gateway</code>, <a href="https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-introduction">Application Gateway</a> will be deployed for load balancing, 
    allowing a PKCS#12 archive (.pfx/.p12) containing the certificate and key to be supplied for SSL/TLS to and from Application Gateway, and providing SSL offload.
    An internal load balancer will also deployed. Application Gateway and Kibana communicate with the cluster through the internal
    load balancer.</li>
    </ul>
    <p><strong>If you are setting up Elasticsearch or Kibana on a publicly available IP address, it is highly recommended to secure access to the cluster with a product like 
    <a href="https://www.elastic.co/products/x-pack/security">Elastic Stack Security</a>, in addition to configuring SSL/TLS.</strong></p>
    </td><td><code>internal</code></td></tr>

  <tr><td>loadBalancerInternalSku</td><td>string</td>
    <td>The internal load balancer SKU. Can be <code>Basic</code> or <code>Standard</code>.</td>
    </td><td><code>Basic</code></td>. When the <code>Standard</code> load balanacer is selected,
    and the <code>loadBalancerType</code> is <code>internal</code>, A Network Security Group is also deployed
    and a public IP address attached to each VM network interface card in the backend pool, to allow
    outbound internet traffic to install the Elastic Stack and dependencies.
  </tr>

  <tr><td>loadBalancerExternalSku</td><td>string</td>
    <td>The external load balancer SKU. Can be <code>Basic</code> or <code>Standard</code>.
      Only relevant when <code>loadBalancerType</code> is <code>external</code>. When the <code>Standard</code> 
      load balancer SKU is selected, the public IP address SKU attached to the external load balancer 
      will also be <code>Standard</code>. A Network Security Group is also deployed, to allow inbound internet traffic
      to the load balancer backend pool.
    </td>
    </td><td><code>Basic</code></td>
  </tr>

  <tr><td id="x-pack">xpackPlugins</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to install a trial license of the <a href="https://www.elastic.co/products/x-pack">Elastic Stack features (formerly X-Pack)</a>
    such as <a href="https://www.elastic.co/products/stack/monitoring">Monitoring</a>, <a href="https://www.elastic.co/products/stack/security">Security</a>, <a href="https://www.elastic.co/products/stack/alerting">Alerting</a>, <a href="https://www.elastic.co/products/stack/graph">Graph</a>, <a href="https://www.elastic.co/products/stack/machine-learning">Machine Learning (5.5.0+)</a> and <a href="https://www.elastic.co/products/stack/elasticsearch-sql">SQL</a>. If also installing Kibana, it will have <a href="https://www.elastic.co/products/stack/reporting">Reporting</a> and Profiler installed.
    <br /><br />
    A value of <code>No</code> for Elasticsearch and Kibana prior to 6.3.0,
    will include only the Open Source features.
    <br /><br />
    A value of <code>No</code> for Elasticsearch and Kibana 6.3.0+
    will include the <a href="https://www.elastic.co/subscriptions">free Basic license features.</a>
    </td><td><code>Yes</code></td></tr>

  <tr><td>azureCloudPlugin</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to install the Azure Repository plugin for snapshot/restore. 
    When set to <code>Yes</code>, at least <code>azureCloudStorageAccountName</code> 
    must be specified to configure the plugin correctly.
    </td><td><code>No</code></td></tr>

  <tr><td>azureCloudStorageAccountName</td><td>string</td>
    <td> The name of an existing storage account to use for snapshots with Azure Repository plugin. 
    Must be a valid Azure Storage Account name.
    </td><td><code>""</code></td></tr>

  <tr><td>azureCloudStorageAccountResourceGroup</td><td>string</td>
    <td> The name of an existing resource group containing the storage account <code>azureCloudStorageAccountName</code> 
    to use for snapshots with Azure Repository plugin. Must be a valid Resource Group name.
    </td><td><code>""</code></td></tr>

  <tr><td>esAdditionalPlugins</td><td>string</td>
    <td>Additional Elasticsearch plugins to install. Each plugin must be separated by a semicolon. e.g. <code>analysis-icu;mapper-attachments</code>
    </td><td><code>""</code></td></tr>

  <tr><td>esAdditionalYaml</td><td>string</td>
    <td>Additional configuration for Elasticsearch yaml configuration file. Each line must be separated by a newline character <code>\n</code> e.g. <code>"action.auto_create_index: +.*\nindices.queries.cache.size: 5%"</code>. <br /><br /><strong>This is an expert level feature - It is recommended that you run your additional yaml through a <a href="http://www.yamllint.com/">linter</a> before starting a deployment.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esHeapSize</td><td>integer</td>
    <td>The size, <em>in megabytes</em>, of memory to allocate on each Elasticsearch node for the JVM heap. If unspecified, 50% of the available memory will be allocated to Elasticsearch heap, up to a maximum of 31744MB (~32GB). 
    Take a look at <a href="https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html" target="_blank">the Elasticsearch documentation</a> for more information. <br /><br /> <strong>This is an expert level feature - setting a heap size too low, or larger than available memory on the Elasticsearch VM SKU will fail the deployment.</strong>
    </td><td><code>0</code></td></tr>

  <tr><td>esHttpCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the certificate and key to secure communication for HTTP layer to Elasticsearch. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esHttpCertPassword</td><td>securestring</td>
    <td>The password for the PKCS#12 archive (.p12/.pfx) containing the certificate and key to secure communication for HTTP layer to Elasticsearch. Optional as the archive may not be protected with a password. <br /><br />
    If using <code>esHttpCaCertBlob</code>, this password will be used to protect the generated PKCS#12 archive on each node.
    <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esHttpCaCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of a PKCS#12 archive (.p12/.pfx) containing the Certificate Authority (CA) certificate and key to use to generate certificates on each Elasticsearch node, to secure communication for the HTTP layer to Elasticsearch. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esHttpCaCertPassword</td><td>securestring</td>
    <td>The password for the PKCS#12 archive (.p12/.pfx) containing the Certificate Authority (CA) certificate and key to secure communication for HTTP layer to Elasticsearch. Optional as the archive may not be be protected with a password. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>
  
  <tr><td>esTransportCaCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of a PKCS#12 archive (.p12/.pfx) containing the Certificate Authority (CA) certificate and key to use to generate certificates on each Elasticsearch node, to secure communication for Transport layer to Elasticsearch. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esTransportCaCertPassword</td><td>securestring</td>
    <td>The password for the PKCS#12 archive (.p12/.pfx) containing the Certificate Authority (CA) certificate and key to secure communication for Transport layer to Elasticsearch. Optional as the archive may not be be protected with a password. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>esTransportCertPassword</td><td>securestring</td>
    <td>The password to protect the generated PKCS#12 archive on each node. <strong><code>xpackPlugins</code> must be <code>Yes</code>, or <code>esVersion</code> must be 6.8.0 or above (and less than 7.0.0) or 7.1.0 and above.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>samlMetadataUri</td><td>string</td>
    <td>The URI from which the metadata file for the Identity Provider can be retrieved to configure SAML Single-Sign-On. For Azure Active Directory, this can be found in the Single-Sign-On settings of the Enterprise Application, and will look something like <code>https://login.microsoftonline.com/&lt;guid&gt;/federationmetadata/2007-06/federationmetadata.xml?appid=&lt;guid&gt;</code><ul>
    <li><strong>Supported only for Elasticsearch 6.2.0+</strong></li>
    <li><strong>Kibana must be installed</strong></li>
    <li><strong>X-Pack plugin must be installed with a level of license that enables the SAML realm.</strong></li>
    <li><strong>SSL/TLS must be configured for HTTP layer of Elasticsearch</strong></li></ul>
    </td><td><code>""</code></td></tr>

  <tr><td>samlServiceProviderUri</td><td>string</td>
    <td>The public URI for the Service Provider to configure SAML Single-Sign-On. If <code>samlMetadataUri</code> is provided but no value is provided for <code>samlServiceProviderUri</code>, the public domain name for the deployed Kibana instance will be used.<ul>
    <li><strong>Supported only for Elasticsearch 6.2.0+</strong></li>
    <li><strong>Kibana must be installed</strong></li>
    <li><strong>SSL/TLS must be configured for HTTP layer of Elasticsearch</strong></li></ul>
    </td><td><code>""</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong><a href="https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#master-node">Master node</a> related settings</strong></td></tr>

  <tr><td>vmSizeMasterNodes</td><td>string</td>
    <td>Azure VM size of dedicated master nodes. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>. By default the template deploys 3 dedicated master nodes, unless <code>dataNodesAreMasterEligible</code> is set to <code>Yes</code>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_DS1_v2</code></td></tr>

  <tr><td>vmMasterNodeAcceleratedNetworking</td><td>string</td>
    <td>Whether to enable <a href="https://azure.microsoft.com/en-us/blog/maximize-your-vm-s-performance-with-accelerated-networking-now-generally-available-for-both-windows-and-linux/">accelerated networking</a> for Master nodes, which enables single root I/O virtualization (SR-IOV) 
    to a VM, greatly improving its networking performance. Valid values are
    <ul>
      <li><code>Default</code>: enables accelerated networking for VMs known to support it</li>
      <li><code>Yes</code>: enables accelerated networking.</li>
      <li><code>No</code>: does not enable accelerated networking</li>
    </ul>
    </td><td><code>Default</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong><a href="https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#data-node">Data node</a> related settings</strong></td></tr>

  <tr><td>dataNodesAreMasterEligible</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to make all data nodes master eligible. This can be useful for small Elasticsearch clusters however, for larger clusters it is recommended to have dedicated master nodes.
    When <code>Yes</code> no dedicated master nodes will be provisioned.
    </td><td><code>No</code></td></tr>

  <tr><td>vmSizeDataNodes</td><td>string</td>
    <td>Azure VM size of the data nodes. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_DS1_v2</code></td></tr>

  <tr><td>vmDataNodeAcceleratedNetworking</td><td>string</td>
    <td>Whether to enable <a href="https://azure.microsoft.com/en-us/blog/maximize-your-vm-s-performance-with-accelerated-networking-now-generally-available-for-both-windows-and-linux/">accelerated networking</a> for Data nodes, which enables single root I/O virtualization (SR-IOV) 
    to a VM, greatly improving its networking performance. Valid values are
    <ul>
      <li><code>Default</code>: enables accelerated networking for VMs known to support it</li>
      <li><code>Yes</code>: enables accelerated networking.</li>
      <li><code>No</code>: does not enable accelerated networking</li>
    </ul>
    </td><td><code>Default</code></td></tr>

  <tr><td>vmDataNodeCount</td><td>int</td>
    <td>The number of data nodes you wish to deploy. <strong>Must be greater than 0</strong>.
    </td><td><code>3</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Data node disk related settings</strong></td></tr>

  <tr><td>vmDataDiskCount</td><td>int</td>
    <td>Number of <a href="https://azure.microsoft.com/en-au/services/managed-disks/">managed disks</a> to attach to each data node in RAID 0 setup.
    Must be equal to or greater than <code>0</code>.
    <p>If the number of disks selected is more than can be attached to the data node VM (SKU) size,
    the maximum number of disks that can be attached for the data node VM (sku) size will be used. Equivalent to
    taking <code>min(vmDataDiskCount, max supported disks for data node VM size)</code></p>
    <ul>
    <li>When 1 disk is selected, the disk is not RAIDed.</li>
    <li>When 0 disks are selected, no disks will be attached to each data node. Instead, the temporary disk will be used to store Elasticsearch data.
    <strong>The temporary disk is ephemeral in nature and not persistent. Consult <a href="https://blogs.msdn.microsoft.com/mast/2013/12/06/understanding-the-temporary-drive-on-windows-azure-virtual-machines/">Microsoft Azure documentation on temporary disks</a>
    to understand the trade-offs in using it for storage.</strong>
    </li>
    </ul>
    </td><td><a href="https://docs.microsoft.com/en-us/azure/virtual-machines/linux/sizes">Maximum number supported disks for data node VM size</a></td></tr>

  <tr><td>vmDataDiskSize</td><td>string</td>
    <td>The disk size of each attached disk. Choose <code>32TiB</code>, <code>16TiB</code>, <code>8TiB</code>, <code>4TiB</code>, <code>2TiB</code>, <code>1TiB</code>, <code>512GiB</code>, <code>256GiB</code>, <code>128GiB</code>, <code>64GiB</code> or <code>32GiB</code>.
    For Premium Storage, disk sizes equate to <a href="https://docs.microsoft.com/en-us/azure/storage/storage-premium-storage#premium-storage-disks-limits">P80, P70, P60, P50, P40, P30, P20, P15, P10 and P6</a>
    storage disk types, respectively.
    </td>
  </td><td><code>1TiB</code></td></tr>

  <tr><td>storageAccountType</td><td>string</td>
    <td>The storage account type of the attached disks. Choose either <code>Default</code> or <code>Standard</code>. 
    The <code>Default</code> storage account type will be Premium Storage for VMs that 
    support Premium Storage and Standard Storage for those that do not. <code>Standard</code> will use Standard Storage.
    </td><td><code>Default</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong><a href="https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#coordinating-only-node">Coordinating node</a> related settings</strong></td></tr>

  <tr><td>vmClientNodeCount</td><td>int</td>
    <td> The number of coordinating nodes to provision. Must be a positive integer. By default, the data nodes are added to the backend pool of the loadbalancer but
    if you provision coordinating nodes, these will be added to the loadbalancer instead. Coordinating nodes can be useful in offloading the <em>gather</em> process from data nodes and are necessary to scale an Elasticsearch cluster deployed with this template beyond 100 data nodes (the maximum number of VMs that can be added to a load balancer backend pool).
    </td><td><code>0</code></td></tr>

  <tr><td>vmSizeClientNodes</td><td>string</td>
    <td> Azure VM size of the coordinating nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_DS1_v2</code></td></tr>

  <tr><td>vmClientNodeAcceleratedNetworking</td><td>string</td>
    <td>Whether to enable <a href="https://azure.microsoft.com/en-us/blog/maximize-your-vm-s-performance-with-accelerated-networking-now-generally-available-for-both-windows-and-linux/">accelerated networking</a> for coordinating nodes, which enables single root I/O virtualization (SR-IOV) 
    to a VM, greatly improving its networking performance. Valid values are
    <ul>
      <li><code>Default</code>: enables accelerated networking for VMs known to support it</li>
      <li><code>Yes</code>: enables accelerated networking.</li>
      <li><code>No</code>: does not enable accelerated networking</li>
    </ul>
    </td><td><code>Default</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Security related settings</strong></td></tr>

  <tr><td>adminUsername</td><td>string</td>
    <td>Admin username used when provisioning virtual machines. Must be a valid Linux username i.e. <a target="_blank" href="https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-usernames/#ubuntu">avoid any of the following usernames for Ubuntu</a>
    </td><td><code>""</code></td></tr>

  <tr><td>authenticationType</td><td>string</td>
    <td>The authentication type for the Admin user. Either <code>password</code> or <code>sshPublicKey</code>
    </td><td><code>password</code></td></tr>

  <tr><td>adminPassword</td><td>securestring</td>
    <td>When <code>authenticationType</code> is <code>password</code> this sets the OS level user's password
    </td><td><code>""</code></td></tr>

  <tr><td>sshPublicKey</td><td>securestring</td>
    <td>When <code>authenticationType</code> is <code>sshPublicKey</code> this sets the OS level sshKey that can be used to login.
    </td><td><code>""</code></td></tr>

  <tr><td>securityBootstrapPassword</td><td>securestring</td>
    <td>Security password for 6.x <a href="https://www.elastic.co/guide/en/x-pack/current/setting-up-authentication.html#bootstrap-elastic-passwords"><code>bootstrap.password</code> key</a> that is added to the keystore. If no value is supplied, a 13 character password
    will be generated using the ARM template <code>uniqueString()</code> function. The bootstrap password is used to seed the built-in
    users. Used only in 6.0.0+
    </td><td><code>""</code></td></tr>

  <tr><td>securityAdminPassword</td><td>securestring</td>
    <td>Security password Admin user.
    <br />
    This is the built-in <code>elastic</code> user.
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>

  <tr><td>securityKibanaPassword</td><td>securestring</td>
    <td>Security password Kibana.
    <br />
     This is the built-in <code>kibana</code> user.
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>

  <tr><td>securityLogstashPassword</td><td>securestring</td>
    <td>This is the built-in <code>logstash_system</code> user.
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>

  <tr><td>securityBeatsPassword</td><td>securestring</td>
    <td>This is the built-in <code>beats_system</code> user. Valid for Elasticsearch 6.3.0+
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>

  <tr><td>securityApmPassword</td><td>securestring</td>
    <td>This is the built-in <code>apm_system</code> user. Valid for Elasticsearch 6.5.0+
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>
  
  <tr><td>securityRemoteMonitoringPassword</td><td>securestring</td>
    <td>This is the built-in <code>remote_monitoring_user</code> user. Valid for Elasticsearch 6.5.0+
    <br />
    should be a minimum of 12 characters, and must be greater than 6 characters.
    </td><td><code>""</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Kibana related settings</strong></td></tr>

  <tr><td>kibana</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to provision a machine with Kibana installed and a public IP address to access it.
    </td><td><code>Yes</code></td></tr>

  <tr><td>vmSizeKibana</td><td>string</td>
    <td>Azure VM size of the Kibana instance. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you select is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_A2_v2</code></td></tr>

  <tr><td>vmKibanaAcceleratedNetworking</td><td>string</td>
    <td>Whether to enable <a href="https://azure.microsoft.com/en-us/blog/maximize-your-vm-s-performance-with-accelerated-networking-now-generally-available-for-both-windows-and-linux/">accelerated networking</a> for Kibana, which enables single root I/O virtualization (SR-IOV) 
    to a VM, greatly improving its networking performance. Valid values are
    <ul>
      <li><code>Default</code>: enables accelerated networking for VMs known to support it</li>
      <li><code>Yes</code>: enables accelerated networking.</li>
      <li><code>No</code>: does not enable accelerated networking</li>
    </ul>
    </td><td><code>Default</code></td></tr>

  <tr><td>kibanaCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of the certificate (.crt) in PEM format to secure HTTPS communication between the browser and Kibana.</td><td><code>""</code></td></tr>

  <tr><td>kibanaKeyBlob</td><td>securestring</td>
    <td>A Base-64 encoded form of the private key (.key) in PEM format to secure HTTPS communication between the browser and Kibana.</td><td><code>""</code></td></tr>

  <tr><td>kibanaKeyPassphrase</td><td>securestring</td>
    <td>The passphrase to decrypt the private key. Optional as the key may not be encrypted.</td><td><code>""</code></td></tr>

  <tr><td>kibanaAdditionalYaml</td><td>string</td>
    <td>Additional configuration for Kibana yaml configuration file. Each line must be separated by a <code>\n</code> newline character e.g. <code>"server.name: \"My server\"\nkibana.defaultAppId: home"</code>. <br /><br /><strong>This is an expert level feature - It is recommended that you run your additional yaml through a <a href="http://www.yamllint.com/">linter</a> before starting a deployment.</strong></td><td><code>""</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Logstash related settings</strong></td></tr>

  <tr><td>logstash</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to provision Logstash VMs.
    </td><td><code>No</code></td></tr>

  <tr><td>vmSizeLogstash</td><td>string</td>
    <td>Azure VM size of the Logstash instance. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you select is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_DS1_v2</code></td></tr>

  <tr><td>vmLogstashCount</td><td>int</td>
    <td>The number of Logstash instances
    </td><td><code>1</code></td></tr>

  <tr><td>vmLogstashAcceleratedNetworking</td><td>string</td>
    <td>Whether to enable <a href="https://azure.microsoft.com/en-us/blog/maximize-your-vm-s-performance-with-accelerated-networking-now-generally-available-for-both-windows-and-linux/">accelerated networking</a> for Logstash, which enables single root I/O virtualization (SR-IOV) 
    to a VM, greatly improving its networking performance. Valid values are
    <ul>
      <li><code>Default</code>: enables accelerated networking for VMs known to support it</li>
      <li><code>Yes</code>: enables accelerated networking.</li>
      <li><code>No</code>: does not enable accelerated networking</li>
    </ul>
    </td><td><code>Default</code></td></tr>

  <tr><td>logstashHeapSize</td><td>integer</td>
    <td>The size, <em>in megabytes</em>, of memory to allocate for the JVM heap for Logstash. If unspecified, Logstash will be configured with the default heap size for the distribution and version. 
    Take a look at <a href="https://www.elastic.co/guide/en/logstash/current/tuning-logstash.html#profiling-the-heap" target="_blank">the Logstash documentation</a> on profiling heap size for more information. <br /><br /> <strong>This is an expert level feature - setting a heap size too low, or larger than available memory on the Logstash VM SKU will fail the deployment.</strong>
    </td><td><code>0</code></td></tr>

  <tr><td>logstashConf</td><td>securestring</td>
    <td>A Base-64 encoded form of a <a href="https://www.elastic.co/guide/en/logstash/current/configuration-file-structure.html#configuration-file-structure" target="_blank">Logstash config file</a> to deploy.
    </td><td><code>""</code></td></tr>  

  <tr><td>logstashKeystorePassword</td><td>securestring</td>
    <td>The password to protect the Logstash keystore. If no value is supplied, a value will be generated using the ARM template <code>uniqueString()</code> function. Used only in 6.2.0+
    </td><td><code>""</code></td></tr>  

  <tr><td>logstashAdditionalPlugins</td><td>string</td>
    <td>Additional Logstash plugins to install. Each plugin must be separated by a semicolon. e.g. <code>logstash-input-heartbeat;logstash-input-twitter</code>
    </td><td><code>""</code></td></tr>

  <tr><td>logstashAdditionalYaml</td><td>string</td>
    <td>Additional configuration for Logstash yaml configuration file. Each line must be separated by a newline character <code>\n</code> e.g. <code>"pipeline.batch.size: 125\npipeline.batch.delay: 50"</code>. <br /><br /><strong>This is an expert level feature - It is recommended that you run your additional yaml through a <a href="http://www.yamllint.com/">linter</a> before starting a deployment.</strong>
    </td><td><code>""</code></td></tr>  

  <tr><td colspan="4" style="font-size:120%"><strong>Jumpbox related settings</strong></td></tr>

  <tr><td>jumpbox</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to optionally add a virtual machine with a public IP to the deployment, which you can use to connect and manage virtual machines on the internal network.
    <strong>NOTE:</strong> If you are deploying Kibana, the Kibana VM can act
    as a jumpbox, so a separate jumpbox VM is not needed.
  </td><td><code>No</code></td></tr>

  <tr><td colspan="4" style="font-size:120%"><strong>Virtual network related settings</strong></td></tr>

  <tr><td>vNetNewOrExisting</td><td>string</td>
    <td>Whether the Virtual Network is <code>new</code> or <code>existing</code>. An <code>existing</code> Virtual Network in
    another Resource Group in the same Location can be used.
    </td><td><code>new</code></td></tr>

  <tr><td>vNetName</td><td>string</td>
    <td>The name of the Virtual Network.
    <strong>The Virtual Network must already exist when using an <code>existing</code> Virtual Network</strong>
    </td><td><code>es-net</code></td></tr>

  <tr><td>vNetExistingResourceGroup</td><td>string</td>
    <td>The name of the Resource Group in which the Virtual Network resides when using an existing Virtual Network.
    <strong>Required when using an <code>existing</code> Virtual Network</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>vNetNewAddressPrefix</td><td>string</td>
    <td>The address prefix when creating a new Virtual Network. <strong>Required when creating a new Virtual Network</strong>
    </td><td><code>10.0.0.0/24</code></td></tr>

  <tr><td>vNetLoadBalancerIp</td><td>string</td>
    <td>The internal static IP address to use when configuring the internal load balancer. Must be an available
    IP address on the provided <code>vNetClusterSubnetName</code>.
    </td><td><code>10.0.0.4</code></td></tr>

  <tr><td>vNetClusterSubnetName</td><td>string</td>
    <td>The name of the subnet to which Elasticsearch nodes will be attached.
    <strong>The subnet must already exist when using an <code>existing</code> Virtual Network</strong>
    </td><td><code>es-subnet</code></td></tr>

  <tr><td>vNetNewClusterSubnetAddressPrefix</td><td>string</td>
    <td>The address space of the subnet.
    <strong>Required when creating a <code>new</code> Virtual Network</strong>
    </td><td><code>10.0.0.0/25</code></td></tr>

  <tr><td>vNetAppGatewaySubnetName</td><td>string</td>
    <td>Subnet name to use for the Application Gateway. 
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong><br />
    <strong>The subnet must already exist when using an <code>existing</code> Virtual Network</strong>
    </td><td><code>es-gateway-subnet</code></td></tr>

  <tr><td>vNetNewAppGatewaySubnetAddressPrefix</td><td>string</td>
    <td>The address space of the Application Gateway subnet.
    <strong>Required when creating a <code>new</code> Virtual Network and selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>10.0.0.128/28</code></td></tr>

   <tr><td colspan="4" style="font-size:120%"><strong>Application Gateway related settings</strong></td></tr>

   <tr><td>appGatewayTier</td><td>string</td>
    <td>The tier of the Application Gateway, either <code>Standard</code> or <code>WAF</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>Standard</code></td></tr>

   <tr><td>appGatewaySku</td><td>string</td>
    <td>The size of the Application Gateway. Choose <code>Small</code>, <code>Medium</code> or <code>Large</code>. 
    When choosing appGatewayTier <code>WAF</code>, the size must be at least <code>Medium</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>Medium</code></td></tr>

   <tr><td>appGatewayCount</td><td>int</td>
    <td>The number instances of the Application Gateway. Can be a value between <code>1</code> and <code>10</code>.
    A minimum of <code>2</code> is recommended for production.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>2</code></td></tr>

   <tr><td>appGatewayCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of the PKCS#12 archive (.p12/.pfx) containing the certificate and key for Application Gateway.
    This certificate is used to secure HTTPS connections to and from the Application Gateway.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>""</code></td></tr>

   <tr><td>appGatewayCertPassword</td><td>securestring</td>
    <td>The password for the PKCS#12 archive (.p12/.pfx) containing the certificate and key for Application Gateway.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>appGatewayEsHttpCertBlob</td><td>securestring</td>
    <td>The Base-64 encoded public certificate (.cer) used to secure the HTTP layer of Elasticsearch. Used by the Application Gateway to whitelist certificates used by the backend pool. Required when using <code>esHttpCertBlob</code> to secure the HTTP layer of Elasticsearch and selecting <code>gateway</code> for load balancing. <strong>X-Pack plugin must be installed</strong>
    </td><td><code>""</code></td></tr>

   <tr><td>appGatewayWafStatus</td><td>string</td>
    <td>The firewall status of the Application Gateway, either <code>Enabled</code> or <code>Disabled</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing and using appGatewayTier <code>WAF<code>.</strong>
    </td><td><code>Enabled</code></td></tr>

   <tr><td>appGatewayWafMode</td><td>string</td>
    <td>The firewall mode of the Application Gateway, either <code>Detection</code> or <code>Prevention</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing and using appGatewayTier <code>WAF<code>.</strong>
    </td><td><code>Detection</code></td></tr>

</table>

### Web based deploy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FmainTemplate.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

The above button will take you to the autogenerated web based UI based on the 
parameters from the ARM template.

### Command line deploy

You can deploy using the template directly from Github using the Azure CLI or Azure PowerShell

### Azure CLI 1.0

Azure CLI 1.0 is no longer supported as the `apiVersion`s of resources are newer than those
supported by the last release. It's recommended to update to [Azure CLI 2.0](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest).

### Azure CLI 2.0

1. Log into Azure

```sh
  az login
```
2. Create a resource group `<name>` in a `<location>` (e.g `westeurope`) where we can deploy too

  ```sh
  az group create --name <name> --location <location>
  ```

3. Use our template directly from GitHub using `--template-uri`

```sh
az group deployment create \
  --resource-group <name> \
  --template-uri https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json \
  --parameters @parameters/password.parameters.json
```

where `<name>` refers to the resource group you just created.

### Azure PowerShell

1. Log into Azure

  ```powershell
  Login-AzureRmAccount
  ```

2. Select a Subscription Id

  ```powershell
  Select-AzureRmSubscription -SubscriptionId "<subscriptionId>"
  ```

3. Define the parameters object for your deployment as a PowerShell hashtable. The keys
  correspond the parameters defined in the [Parameters section](#parameters)

  ```powershell
  $branch = "master"
  $esVersion = "7.6.0"

  $clusterParameters = @{
      "_artifactsLocation" = "https://raw.githubusercontent.com/elastic/azure-marketplace/$branch/src/"
      "esVersion" = $esVersion
      "esClusterName" = "elasticsearch"
      "loadBalancerType" = "internal"
      "vmDataDiskCount" = 1
      "adminUsername" = "russ"
      "adminPassword" = "Password1234"
      "securityBootstrapPassword" = "Password1234"
      "securityAdminPassword" = "Password1234"     
      "securityKibanaPassword" = "Password1234"
      "securityLogstashPassword" = "Password1234"
      "securityBeatsPassword" = "Password1234"
      "securityApmPassword" = "Password1234"
      "securityRemoteMonitoringPassword" = "Password1234"
  }
  ```

4. Create a resource group `<name>` in a `<location>` (e.g `westeurope`) where we can deploy too

  ```powershell
  New-AzureRmResourceGroup -Name "<name>" -Location "<location>"
  ```

5. Use our template directly from GitHub

  ```powershell
  New-AzureRmResourceGroupDeployment -Name "<deployment name>" -ResourceGroupName "<name>" -TemplateUri "https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json" -TemplateParameterObject $clusterParameters
  ```

## Targeting a specific template version

You can target a specific version of the template by modifying the URI of the template and 
the `_artifactsLocation` parameter of the template to point to a specific tagged release.

**Targeting a specific template version is recommended for repeatable production deployments.**

For example, to target the [`7.6.0` tag release with PowerShell](https://github.com/elastic/azure-marketplace/tree/7.6.0)

```powershell
$templateVersion = "7.6.0"
$_artifactsLocation = "https://raw.githubusercontent.com/elastic/azure-marketplace/$templateVersion/src/"

# minimum parameters required to deploy
$clusterParameters = @{
  "_artifactsLocation" = $_artifactsLocation
  "esVersion" = "7.6.0"
  "adminUsername" = "russ"
  "adminPassword" = "Password1234"
  "securityBootstrapPassword" = "Password1234"
  "securityAdminPassword" = "Password1234"
  "securityKibanaPassword" = "Password1234"
  "securityLogstashPassword" = "Password1234"
  "securityBeatsPassword" = "Password1234"
  "securityApmPassword" = "Password1234"
  "securityRemoteMonitoringPassword" = "Password1234"
}

$resourceGroup = "my-azure-cluster"
$location = "Australia Southeast"
$name = "my-azure-cluster"

New-AzureRmResourceGroup -Name $resourceGroup -Location $location
New-AzureRmResourceGroupDeployment -Name $name -ResourceGroupName $resourceGroup -TemplateUri "$_artifactsLocation/mainTemplate.json" -TemplateParameterObject $clusterParameters
```

## Configuring TLS

**It is strongly recommended that you secure communication using Transport Layer Security when using the template**. 
The Elastic Stack security features can provide Basic Authentication, 
Role Based Access control, and Transport Layer Security (TLS)
for both Elasticsearch and Kibana. For more details, please refer to 
[the Security documentation](https://www.elastic.co/guide/en/elastic-stack-deploy/current/azure-arm-template-security.html).

For Elasticsearch versions 6.8.0+ (and less than 7.0.0), and 7.1.0+, the Elastic Stack security features
that allow configuring TLS and role based access control are available in the free basic license tier. 
For all other versions, the Elastic Stack security features require a license level higher than basic; 
They can be configured with a trial license, which provides access to the Security features for 30 days.

### TLS for Kibana

You can secure external access from the browser to Kibana with TLS by supplying
a certificate and private key in PEM format with `kibanaCertBlob` and
`kibanaKeyBlob` parameters, respectively.

### TLS for Elasticsearch Transport layer

You can secure communication between nodes in the cluster with TLS on the
Transport layer. Configuring TLS for the Transport layer requires
`xPackPlugins` be set to `Yes`, or an Elasticsearch version 6.8.0+ (and less than 7.0.0) or 7.1.0+.

You must supply a PKCS#12 archive with the `esTransportCaCertBlob` parameter (and optional
passphrase with `esTransportCaCertPassword`) containing the CA cert which should be used to generate
a certificate for each node within the cluster. An optional
passphrase can be passed with `esTransportCertPassword` to encrypt the generated certificate
on each node.

One way to generate a PKCS#12 archive containing a CA certificate and key is using 
[Elastic's `elasticsearch-certutil` command](https://www.elastic.co/guide/en/elasticsearch/reference/current/certutil.html).
The simplest command to generate a CA certificate is

```sh
./elasticsearch-certutil ca
```

and follow the instructions.

### TLS for Elasticsearch HTTP layer

You can secure external access to the cluster with TLS with an external
loadbalancer or Application Gateway. Configuring TLS for the HTTP layer requires
`xPackPlugins` be set to `Yes`, or an Elasticsearch version 6.8.0+ (and less than 7.0.0) or 7.1.0+.

#### External load balancer

If you choose `external` as the value for `loadBalancerType`, you must either

* supply a PKCS#12 archive containing the key and certificate with the `esHttpCertBlob` parameter (and optional 
passphrase with `esHttpCertPassword`) containing the certs and private key to
secure the HTTP layer. This certificate will be used by all nodes within the cluster, and

**_or_**

* supply a PKCS#12 archive containing the key and certificate with the `esHttpCaCertBlob` parameter (and optional 
passphrase with `esHttpCaCertPassword`) containing the CA which should be used to generate
a certificate for each node within the cluster to secure the HTTP layer.
Kibana will be configured to trust the CA and perform hostname verification for presented
certificates. One way to generate a PKCS#12 archive is using [Elastic's certutil command](https://www.elastic.co/guide/en/elasticsearch/reference/current/certutil.html).

#### Application Gateway

If you choose `gateway` as the value for `loadBalancerType`, you must

* supply a PKCS#12 archive containing the key and certificate with the `appGatewayCertBlob` parameter (and optional 
passphrase with `appGatewayCertPassword`) to secure communication to Application Gateway.
One way to generate a PKCS#12 archive is using [Elastic's certutil command](https://www.elastic.co/guide/en/elasticsearch/reference/current/certutil.html)

[Application Gateway](https://azure.microsoft.com/en-au/services/application-gateway/)
performs SSL offload, so communication from Application Gateway to
Elasticsearch is not encrypted with TLS by default. TLS to Application Gateway may be sufficient for your 
needs, but if you would like end-to-end encryption by also configuring TLS for Elasticsearch HTTP layer, you can

* supply a PKCS#12 archive containing the key and certificate with the `esHttpCertBlob` parameter (and optional 
passphrase with `esHttpCertPassword`) containing the certs and private key to
secure the HTTP layer. This certificate will be used by all nodes within the cluster, and
Kibana will be configured to trust the certificate CA (if CA certs are present within the archive).
One way to generate a PKCS#12 archive is using [Elastic's certutil command](https://www.elastic.co/guide/en/elasticsearch/reference/current/certutil.html), and you must
specify a `--dns <name>` argument with a name that matches that in the `--name <name>` argument.

**_and_**

* supply the public certificate in PEM format from the PKCS#12 archive
passed with `esHttpCertBlob` parameter, using the `appGatewayEsHttpCertBlob` parameter.
Application Gateway whitelists certificates used by VMs in the backend pool. This can
be extracted from the PKCS#12 archive of the `esHttpCertBlob` parameter using
[`openssl pkcs12`](https://www.openssl.org/docs/man1.0.2/apps/pkcs12.html)

    ```sh
    openssl pkcs12 -in http_cert.p12 -out http_public_cert.cer -nokeys
    ```

    and provide the passphrase for the archive when prompted.

**IMPORTANT**: When configuring [end-to-end encryption with Application Gateway](https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-end-to-end-ssl-powershell),
the certificate to secure the HTTP layer **must** include a x509v3 Subject Alternative Name
extension with a DNS entry that matches the Subject CN, to work with Application
Gateway's whitelisting mechanism. This can be checked using
[`openssl x509`](https://www.openssl.org/docs/man1.0.2/apps/x509.html)

```sh
openssl x509 -in http_public_cert.cer -text -noout
```

which will output something similar to

```text
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            // omitted for brevity ...
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN=Elastic Certificate Tool Autogenerated CA
        Validity
            Not Before: Jul  5 02:37:40 2018 GMT
            Not After : Jul  4 02:37:40 2021 GMT
        Subject: CN=custom
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (2048 bit)
                Modulus:
                    // omitted for brevity ...
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Subject Key Identifier:
                // omitted for brevity ...
            X509v3 Authority Key Identifier:
                // omitted for brevity ...

            X509v3 Subject Alternative Name:
                DNS:custom
            X509v3 Basic Constraints:
                CA:FALSE
    Signature Algorithm: sha256WithRSAEncryption
         // omitted for brevity ...
```

_Without_ this, Application Gateway will return [502 Bad Gateway errors](https://docs.microsoft.com/en-gb/azure/application-gateway/application-gateway-troubleshooting-502),
as the health probe for the backend pool will fail when the whitelisted certificate does
not contain this certificate extension.
You can typically understand if there is a problem with the key format when

1. TLS has been configured on the HTTP layer
2. Kibana is able to communicate to the cluster correctly _but_ Application Gateway returns 502 errors.

This may not always be the case, but can be indicative. You should also check the description for Backend Health
of the Application Gateway in the Azure portal.

### Passing certificate parameters

Parameters such as <code>esHttpCertBlob</code> and <code>kibanaCertBlob</code> must be provided in Base-64 encoded form. A Base-64 encoded value can be obtained using

1. [base64](https://linux.die.net/man/1/base64) on Linux, or [openssl](https://www.openssl.org/docs/man1.0.2/apps/openssl.html) on Linux and MacOS

    base64

    ```sh
    httpCert=$(base64 http-cert.p12) 
    ```

    openssl

    ```sh
    httpCert=$(openssl base64 -in http-cert.p12)
    ```

    and including the value assigned to <code>$httpCert</code> in the parameters.json file as the value for certificate parameter passed to the Azure CLI command

2. PowerShell on Windows

    ```powershell
    $httpCert = [Convert]::ToBase64String([IO.File]::ReadAllBytes("c:\http-cert.p12"))
    ```

    and then pass this in the template parameters object passed to the Azure PowerShell command

    ```powershell
    $clusterParameters = @{
        # Other parameters skipped for brevity
        "esHttpCertBlob"= $httpCert
    }
    ```

## License

This project is [MIT Licensed](https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt) and was originally forked from 
the [Elasticsearch Azure quick start arm template](https://github.com/Azure/azure-quickstart-templates/tree/master/elasticsearch)
