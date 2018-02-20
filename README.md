# Elasticsearch Azure Marketplace offering

This repository consists of:

* [src/mainTemplate.json](src/mainTemplate.json) - The main Azure Resource Management (ARM) template. The template itself is composed of many nested linked templates with the main template acting as the entry point.
* [src/createUiDefinition](src/createUiDefinition.json) - UI definition file for our Azure Marketplace offering. This file produces an output JSON that the ARM template can accept as input parameters.

## Building

After pulling the source, call `npm install` once to pull in all devDependencies.

You may edit [build/allowedValues.json](build/allowedValues.json), which the build will use to patch the ARM template and Marketplace UI definition.

Run `npm run build`; this will validate EditorConfig settings, JSON files, patch the allowedValues and create a zip in the `dist` folder.

For more details around developing the template, take a look at the [Development README](build/README.md)

## Azure Marketplace

The Azure Marketplace Elasticsearch offering offers a simplified UI over the full power of the ARM template. 

It will always bootstrap a cluster complete with a trial license of Elastic's commercial [X-Pack plugins](https://www.elastic.co/products/x-pack).

Did you know that you can apply for a **free basic license**? Go check out our [subscription options](https://www.elastic.co/subscriptions)

Deploying through the Marketplace is great and easy way to get your feet wet for a first time with Elasticsearch (on Azure) but in the long run, you'll want to deploy 
the templates directly though the Azure CLI or PowerShell SDKs. <a href="#command-line-deploy">Check out the examples.</a>

---

### VERY IMPORTANT
**This template does not configure SSL/TLS for communication with Elasticsearch through an external load balancer. It is strongly recommended that you secure
communication before using in production.**

You can secure external access to the cluster with TLS by using `gateway` as the `loadBalancerType` and supplying a PFX certificate with the `appGatewayCertBlob` parameter. This sets
the cluster up to use [Application Gateway](https://azure.microsoft.com/en-au/services/application-gateway/) for load balancing and SSL offload.

You can secure external access from the browser to Kibana with TLS by supplying a certificate and private key with `kibanaCertBlob` and `kibanaKeyBlob`, respectively.

---

![Example UI Flow](images/ui.gif)

You can view the UI in developer mode by [clicking here](https://portal.azure.com/#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}}). If you feel something is cached improperly use [this client unoptimized link instead](https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}})

## Reporting bugs

Have a look at this [screenshot](images/error-output.png) to see how you can navigate to the deployment error status message.
Please create an issue with that message and in which resource it occured on our [github issues](https://github.com/elastic/azure-marketplace/issues) 

## ARM template

The output from the Azure Marketplace UI is fed directly to the ARM deployment template. You can use the ARM template on its own without going through the MarketPlace. In fact, there are many features in the ARM template that are not exposed within the Marketplace such as configuring

- Azure Storage account to use for Snapshot/Restore
- Application Gateway to use for TLS and SSL offload
- The number and size of disks to attach to each data node VM

Check out our [examples repository](https://github.com/elastic/azure-marketplace-examples) for examples of common scenarios and also take a look at the following blog posts for further information

- [Spinning up a cluster with Elastic's Azure Marketplace template](https://www.elastic.co/blog/spinning-up-a-cluster-with-elastics-azure-marketplace-template)
- [Elasticsearch and Kibana deployments on Azure](https://www.elastic.co/blog/elasticsearch-and-kibana-deployments-on-azure)

### Parameters

<table>
  <tr><th>Parameter</td><th>Type</th><th>Description</th><th>Default Value</th></tr>

  <tr><td>artifactsBaseUrl</td><td>string</td>
    <td>The base url of the Elastic ARM template.
    </td><td>Raw content of the current branch</td></tr>

  <tr><td>esVersion</td><td>string</td>
    <td>A valid supported Elasticsearch version. See <a href="https://github.com/elastic/azure-marketplace/blob/master/src/mainTemplate.json#L15">this list for supported versions</a>
    </td><td>The latest version of Elasticsearch supported by the ARM template version</td></tr>

  <tr><td>esClusterName</td><td>string</td>
    <td> The name of the Elasticsearch cluster. Required
    </td><td><code>""</code></td></tr>

  <tr><td>loadBalancerType</td><td>string</td>
    <td> The load balancer to set up to access the cluster. Can be <code>internal</code>, <code>external</code> or <code>gateway</code>. 
    <ul>
    <li>By choosing <code>internal</code>, only an internal load balancer is deployed. Useful when connecting to the cluster happens from inside the Virtual Network</li>
    <li>By choosing <code>external</code>, both internal and external load balancers will be deployed. Kibana communicates with the cluster through the internal
    load balancer.</li>
    <li>By choosing <code>gateway</code>, <a href="https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-introduction">Application Gateway</a> will be deployed for load balancing, 
    allowing a PFX certificate to be supplied for transport layer security to and from Application Gateway, and providing SSL offload. 
    An internal load balancer will also deployed. Application Gateway and Kibana communicate with the cluster through the internal
    load balancer.</li>
    </ul>
    <p><strong>If you are setting up Elasticsearch or Kibana on a publicly available IP address, it is highly recommended to secure access to the cluster with a product like 
    <a href="https://www.elastic.co/products/x-pack/security">Elastic's Security</a>, in addition to configuring transport layer security.</strong></p>
    </td><td><code>internal</code></td></tr>

  <tr><td>azureCloudPlugin</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to install the Azure Cloud plugin for snapshot/restore. 
    When set to <code>Yes</code>, both <code>azureCloudeStorageAccountName</code> 
    and <code>azureCloudStorageAccountKey</code> must be specified to configure the plugin correctly.
    </td><td><code>No</code></td></tr>

  <tr><td>azureCloudStorageAccountName</td><td>string</td>
    <td> The name of an existing storage account to use for snapshots with Azure Cloud plugin. 
    Must be a valid Azure Storage Account name.
    </td><td><code>""</code></td></tr>

  <tr><td>azureCloudStorageAccountKey</td><td>securestring</td>
    <td> The access key of an existing storage account to use for snapshots with Azure Cloud plugin.
    </td><td><code>""</code></td></tr>

  <tr><td>xpackPlugins</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to install a trial license of the commercial <see href="https://www.elastic.co/products/x-pack">X-Pack</a>
    plugins: Monitoring, Security, Alerting, Graph (Elasticsearch 2.3.0+) and Machine Learning (5.5.0+).
    </td><td><code>Yes</code></td></tr>

  <tr><td>esAdditionalPlugins</td><td>string</td>
    <td>Additional elasticsearch plugins to install.  Each plugin must be separated by a semicolon. e.g. <code>analysis-icu;mapper-attachments</code>
    </td><td><code>""</code></td></tr>

  <tr><td>esAdditionalYaml</td><td>string</td>
    <td>Additional configuration for Elasticsearch yaml configuration file. Each line must be separated by a newline character <code>\n</code> e.g. <code>"action.auto_create_index: .security\nindices.queries.cache.size: 5%"</code>. <strong>This is an expert level feature - It is recommended that you run your additional yaml through a <a href="http://www.yamllint.com/">linter</a> before starting a deployment.</strong>
    </td><td><code>""</code></td></tr>

  <tr><td>kibana</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to provision a machine with a public IP that
    has Kibana installed on it. If you have opted to also install the Elasticsearch plugins using <code>xpackPlugins</code> then 
    a trial license of the commercial <see href="https://www.elastic.co/products/x-pack">X-Pack</a> Kibana plugins as well as <a href="https://www.elastic.co/guide/en/sense/current/introduction.html">Sense Editor (Kibana 4.x)</a> are also installed.
    </td><td><code>Yes</code></td></tr>

  <tr><td>vmSizeKibana</td><td>string</td>
    <td>Azure VM size of the Kibana instance. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_A2</code></td></tr>

  <tr><td>kibanaCertBlob</td><td>string</td>
    <td>A Base-64 encoded form of the certificate (.crt) to secure HTTPS communication between the browser and Kibana.</td><td><code>""</code></td></tr>

  <tr><td>kibanaKeyBlob</td><td>securestring</td>
    <td>A Base-64 encoded form of the private key (.key) to secure HTTPS communication between the browser and Kibana.</td><td><code>""</code></td></tr>

  <tr><td>kibanaKeyPassphrase</td><td>securestring</td>
    <td>The passphrase to decrypt the private key. Optional as the key may not be encrypted. Supported only in 5.3.0+</td><td><code>""</code></td></tr>

  <tr><td>jumpbox</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to optionally add a virtual machine with a public IP to the deployment, which you can use to connect and manage virtual machines on the internal network.
    <br /><br />
    NOTE: If you are deploying Kibana, the Kibana virtual machine can act
    as a jumpbox.
  </td><td><code>No</code></td></tr>

  <tr><td>vmHostNamePrefix</td><td>string</td>
    <td>The prefix to use for hostnames when naming virtual machines in the cluster. Hostnames are used for resolution of master nodes on the network, so if you are deploying a cluster into an existing virtual network containing an existing Elasticsearch cluster, be sure to set this to a unique prefix, to differentiate the hostnames of this cluster from an existing cluster. Can be up to 5 characters in length, must begin with an alphanumeric character and can contain alphanumeric and hyphen characters.
    </td><td><code>""</code></td></tr>

  <tr><td>vmSizeDataNodes</td><td>string</td>
    <td>Azure VM size of the data nodes. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_D1</code></td></tr>

  <tr><td>vmDataDiskCount</td><td>int</td>
    <td>Number of disks to attach to each data node in RAID 0 setup. 
    Must be one of <code>0</code>, <code>1</code>, <code>2</code>, <code>4</code>, <code>8</code>, <code>16</code>, <code>32</code>, <code>40</code>. 
    If the number of disks selected is more than can be attached to the data node VM size, 
    the maximum number of disks that can be attached for the data node VM size will be used. Equivalent to
    taking <code>min(vmDataDiskCount, max supported disks for data node VM size)</code> 
    <ul>
    <li>When 1 disk is selected, the disk is not RAIDed.</li>
    <li>When 0 disks are selected, no disks will be attached to each data node; instead, the temporary disk will be used to store Elasticsearch data. 
    <strong>The temporary disk is ephemeral in nature and not persistent. Consult <a href="https://blogs.msdn.microsoft.com/mast/2013/12/06/understanding-the-temporary-drive-on-windows-azure-virtual-machines/">Microsoft Azure documentation on temporary disks</a> 
    to understand the trade-offs in using it for storage.</strong>
    </li>
    </ul>
    </td><td><code>40</code><br />i.e. the max supported disks for data node VM size</td></tr>

  <tr><td>vmDataDiskSize</td><td>string</td>
    <td>The disk size of each attached disk. Choose <code>Large</code> (1023Gb), <code>Medium</code> (512Gb) or <code>Small</code> (128Gb).
    For Premium Storage, disk sizes equate to <a href="https://docs.microsoft.com/en-us/azure/storage/storage-premium-storage#premium-storage-disks-limits">P30, P20 and P10</a> 
    storage disk types, respectively.
    </td>
  </td><td><code>Large</code></td></tr>

  <tr><td>vmDataNodeCount</td><td>int</td>
    <td>The number of data nodes you wish to deploy. Must be greater than 0. 
    </td><td><code>3</code></td></tr>

  <tr><td>storageAccountType</td><td>string</td>
    <td>The storage account type of the attached disks. Choose either <code>Default</code> or <code>Standard</code>. 
    The <code>Default</code> storage account type will be Premium Storage for VMs that 
    support Premium Storage and Standard Storage for those that do not.
    </td><td><code>Default</code></td></tr>

  <tr><td>dataNodesAreMasterEligible</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> to make all data nodes master eligible. This can be useful for small Elasticsearch clusters however, for larger clusters it is recommended to have dedicated master nodes. 
    When <code>Yes</code> no dedicated master nodes will be provisioned.
    </td><td><code>No</code></td></tr>

  <tr><td>vmSizeMasterNodes</td><td>string</td>
    <td>Azure VM size of dedicated master nodes. See <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>. By default the template deploys 3 dedicated master nodes, unless <code>dataNodesAreMasterEligible</code> is set to <code>Yes</code>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_D1</code></td></tr>

  <tr><td>vmClientNodeCount</td><td>int</td>
    <td> The number of client nodes to provision. Must be a positive integer. By default, the data nodes are added to the backendpool of the loadbalancer but 
    if you provision client nodes, these will be added to the loadbalancer instead. Client nodes can be useful in offloading the <emphasis>gather</emphasis> process from data nodes and are necessary to scale an Elasticsearch cluster deployed with this template beyond 100 data nodes (the maximum number of VMs that can be added to a load balancer backendpool).
    </td><td><code>0</code></td></tr>

  <tr><td>vmSizeClientNodes</td><td>string</td>
    <td> Azure VM size of the client nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    <strong>Check that the size you choose is <a href="https://azure.microsoft.com/en-au/regions/services/">available in the region you choose</a></strong>.
    </td><td><code>Standard_D1</code></td></tr>

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
    <ul>
    <li>for 5.x+, built-in <code>elastic</code> user</li>
    <li>for 2.x, the <code>es_admin</code> user, with <code>admin</code> role</li>
    </ul>
    must be &gt; 6 characters
    </td><td><code>""</code></td></tr>

  <tr><td>securityReadPassword</td><td>securestring</td>
    <td>Security password for the <code>es_read</code> user with user (read-only) role, must be &gt; 6 characters
    </td><td><code>""</code></td></tr>

  <tr><td>securityKibanaPassword</td><td>securestring</td>
    <td>Security password Kibana. 
    <ul>
    <li>for 5.x+, built-in <code>kibana</code> user</li>
    <li>for 2.x, the <code>es_kibana</code> user with <code>kibana4_server role</code></li>
    </ul>
     must be &gt; 6 characters
    </td><td><code>""</code></td></tr>

  <tr><td>securityLogstashPassword</td><td>securestring</td>
    <td>Security password for 5.2.0+ built-in <code>logstash_system</code> user. Only used in 5.2.0+.
    <br />
    must be &gt; 6 characters
    </td><td><code>""</code></td></tr>

  <tr><td>location</td><td>string</td>
    <td>The location where to provision all the items in this template. Defaults to the special <code>[resourceGroup().location]</code> value which means it will inherit the location
    from the resource group. Any other value must be a valid <a href="https://azure.microsoft.com/regions/">Azure region</a>.
    </td><td><code>[resourceGroup().location]</code></td></tr>

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
    <td>A Base-64 encoded form of the PFX certificate for the Application Gateway. 
    This certificate is used to secure HTTPS connections to and from the Application Gateway.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>""</code></td></tr>   

   <tr><td>appGatewayCertPassword</td><td>securestring</td>
    <td>The password for the PFX certificate for the Application Gateway. Defaults to <code>""</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing.</strong>
    </td><td><code>""</code></td></tr> 
    
   <tr><td>appGatewayWafStatus</td><td>string</td>
    <td>The firewall status of the Application Gateway, either <code>Enabled</code> or <code>Disabled</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing and using appGatewayTier <code>WAF<code>.</strong>
    </td><td><code>Enabled</code></td></tr> 

   <tr><td>appGatewayWafMode</td><td>string</td>
    <td>The firewall mode of the Application Gateway, either <code>Detection</code> or <code>Prevention</code>.
    <strong>Required when selecting <code>gateway</code> for load balancing and using appGatewayTier <code>WAF<code>.</strong>
    </td><td><code>Detection</code></td></tr>   

  <tr><td>userCompany</td><td>string</td>
    <td>The name of your company.
    </td><td><code>""</code></td></tr>

  <tr><td>userEmail</td><td>string</td>
    <td>Your email address
    </td><td><code>""</code></td></tr>

  <tr><td>userFirstName</td><td>string</td>
    <td>Your first name
    </td><td><code>""</code></td></tr>

  <tr><td>userLastName</td><td>string</td>
    <td>Your last name
    </td><td><code>""</code></td></tr>

  <tr><td>userJobTitle</td><td>string</td>
    <td>Your job title. Pick the nearest one that matches from <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">the list of job titles</a>
    </td><td><code>Other</code></td></tr>

  <tr><td>userCountry</td><td>string</td>
    <td>The country in which you are based.
    </td><td><code>""</code></td></tr>

</table>

### Command line deploy

You can deploy using the template directly from Github using the Azure CLI or Azure PowerShell

#### Azure CLI

1. Log into Azure

  ```sh
  azure login
  ```

2. Ensure you are in arm mode

  ```sh
  azure config mode arm
  ```

3. Create a resource group `<name>` in a `<location>` (e.g `westeurope`) where we can deploy too

  ```sh
  azure group create <name> <location>
  ```

4. Use our published template directly using `--template-uri`

```sh
azure group deployment create --template-uri https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json --parameters-file parameters/password.parameters.json -g <name>
```

or if your are executing commands from a clone of this repo using `--template-file`

```sh
azure group deployment create --template-file src/mainTemplate.json --parameters-file parameters/password.parameters.json -g <name>
```

where `<name>` refers to the resource group you just created.

**NOTE**

The `--parameters-file` can specify a different location for the items that get provisioned inside of the resource group. Make sure these are the same prior to deploying if you need them to be. Omitting location from the parameters file is another way to make sure the resources get deployed in the same location as the resource group.

#### Azure PowerShell

1. Log into Azure

  ```powershell
  Login-AzureRmAccount
  ```

2. Select a Subscription Id

  ```powershell
  Select-AzureRmSubscription -SubscriptionId "<subscriptionId>"
  ```

3. Define the parameters object for your deployment

  ```powershell
  $clusterParameters = @{
      "artifactsBaseUrl"="https://raw.githubusercontent.com/elastic/azure-marketplace/master/src"
      "esVersion" = "6.2.1"
      "esClusterName" = "elasticsearch"
      "loadBalancerType" = "internal"
      "vmDataDiskCount" = 1
      "adminUsername" = "russ"
      "adminPassword" = "Password1234"
      "securityAdminPassword" = "Password123"
      "securityReadPassword" = "Password123"
      "securityKibanaPassword" = "Password123"
      "securityLogstashPassword" = "Password123"
  }
  ```

4. Create a resource group `<name>` in a `<location>` (e.g `westeurope`) where we can deploy too

  ```powershell
  New-AzureRmResourceGroup -Name "<name>" -Location "<location>"
  ```

5. Use our template directly from Github

  ```powershell
  New-AzureRmResourceGroupDeployment -Name "<deployment name>" -ResourceGroupName "<name>" -TemplateUri "https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json" -TemplateParameterObject $clusterParameters
  ```

### Targeting a specific template version

You can target a specific version of the template by modifying the URI of the template and the artifactsBaseUrl parameter of the template. 

For example, to target the `5.0.1` tag release with PowerShell

```powershell
$templateVersion = "5.0.1"
$templateBaseUrl = "https://raw.githubusercontent.com/elastic/azure-marketplace/$templateVersion/src"

$clusterParameters = @{
    "artifactsBaseUrl"= $templateBaseUrl
    "esVersion" = "5.0.0"
    "adminUsername" = "russ"
    "adminPassword" = "Password1234"
    "securityAdminPassword" = "Password123"
    "securityReadPassword" = "Password123"
    "securityKibanaPassword" = "Password123"
    "securityLogstashPassword" = "Password123"
}

New-AzureRmResourceGroup -Name "<name>" -Location "<location>"
New-AzureRmResourceGroupDeployment -Name "<deployment name>" -ResourceGroupName "<name>" -TemplateUri "$templateBaseUrl/mainTemplate.json" -TemplateParameterObject $clusterParameters
```

Targeting a specific template version is recommended for repeatable deployments.

### Web based deploy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FmainTemplate.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

The above button will take you to the autogenerated web based UI based on the parameters from the ARM template.

# License

This project is [MIT Licensed](https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt) and is based heavily on the [Elasticsearch azure quick start arm template](https://github.com/Azure/azure-quickstart-templates/tree/master/elasticsearch)
