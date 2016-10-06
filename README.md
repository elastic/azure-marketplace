# Elasticsearch Azure Marketplace offering

This repository consists of:

* [src/mainTemplate.json](src/mainTemplate.json) - Entry Azure Resource Management (ARM) template.
* [src/createUiDefinition](src/createUiDefinition.json) - UI definition file for our market place offering. This file produces an output JSON that the ARM template can accept as input parameters.

## Building

After pulling call `npm install` once, this will pull in all devDependencies.

You may edit [build/allowedValues.json](build/allowedValues.json), which the build will use these to patch the arm template and ui definition.

Run `npm run build`, this will validate EditorConfig settings, validate JSON files, patch the allowedValues and then create a zip in the `dist` folder.

### Development

New features should be developed on separate branches and merged back into `master` once complete. To aid in the development process, a gulp task is configured to update all of the github template urls to point at a specific branch so that UI definition and web based deployments can be tested. To run the task

```sh
npm run links
```

will update the links to point to the name of the current branch. Once ready to merge back into `master`, a specific branch name can be passed with

```sh
npm run links -- --branch master
```

## Marketplace

The market place Elasticsearch offering offers a simplified UI over the full power of the ARM template. 
It will always install a cluster complete with the X-Pack plugins [Shield](https://www.elastic.co/products/shield), [Watcher](https://www.elastic.co/products/watcher) and [Marvel](https://www.elastic.co/products/marvel), and for Elasticsearch 2.3.0+, [Graph](https://www.elastic.co/products/graph). 

Additionally, the [Azure Cloud plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/cloud-azure.html) is installed to support snapshot and restore.

![Example UI Flow](images/ui.gif)

You can view the UI in developer mode by [clicking here](https://portal.azure.com/#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}}). If you feel something is cached improperly use [this client unoptimized link instead](https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}})

## Reporting bugs

Have a look at this [screenshot](images/error-output.png) to see how you can navigate to the deployment error status message.
Please create an issue with that message and in which resource it occured on our [github issues](https://github.com/elastic/azure-marketplace/issues) 

## ARM template

The output from the market place UI is fed directly to the ARM template. You can use the ARM template on its own without going through the market place.

### Parameters

<table>
  <tr><th>Parameter</td><th>Type</th><th>Description</th></tr>
  <tr><td>esVersion</td><td>string</td>
    <td>A valid supported Elasticsearch version see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/mainTemplate.json#L16-L23">this list for supported versions</a>
    </td></tr>

  <tr><td>esClusterName</td><td>string</td>
    <td> The name of the Elasticsearch cluster
    </td></tr>

  <tr><td>cloudAzureStorageAccountName</td><td>string</td>
    <td> The name of the storage account to use for snapshots with Azure Cloud plugin. 
    Must be between 3 and 24 alphanumeric lowercase characters. Defaults to <code>essnapshot</code>.
    </td></tr>

  <tr><td>cloudAzureStorageAccountExistingResourceGroup</td><td>string</td>
    <td> The resource group name when using an existing storage account with Azure Cloud plugin.
    <strong>Required when using an existing Storage account for Azure Cloud plugin</strong>
    </td></tr>

  <tr><td>cloudAzureStorageAccountNewType</td><td>string</td>
    <td> The type of storage account when creating a new storage account for Azure Cloud plugin. Defaults to <code>Standard_LRS</code>.
    <strong>Required when using a new Storage Account for Azure Cloud plugin</strong>
    </td></tr>

  <tr><td>cloudAzureStorageAccountNewOrExisting</td><td>string</td>
    <td> Whether to use an <code>existing</code> storage account or create a <code>new</code> storage account for Azure Cloud plugin.
    Defaults to <code>new</code>.
    </td></tr>

  <tr><td>cloudAzureStorageAccountNewUnique</td><td>string</td>
    <td> Whether the new storage account to use for snapshots has been validated to be unique. 
    If set to <code>Yes</code> then the storage account name will be taken verbatim; if set to <code>No</code> then 
    the first 11 characters of the storage account name provided in <code>cloudAzureStorageAccountName</code> 
    will be taken as a prefix to a randomly generated unique storage account name.
    <strong>Required when using a new Storage Account for Azure Cloud plugin</strong>
    </td></tr>

  <tr><td>vNetNewOrExisting</td><td>string</td>
    <td>Whether the Virtual Network is <code>new</code> or <code>existing</code>. An <code>existing</code> Virtual Network in
    another Resource Group in the same Location can be used. Defaults to <code>new</code>
    </td></tr>

  <tr><td>vNetName</td><td>string</td>
    <td>The name of the Virtual Network. Defaults to <code>es-net</code>
    </td></tr>

  <tr><td>vNetSubnetName</td><td>string</td>
    <td>The name of the subnet to which Elasticsearch nodes will be attached. Defaults to <code>es-subnet</code>
    </td></tr>

  <tr><td>vNetLoadBalancerIp</td><td>string</td>
    <td>The internal static IP address to use when configuring the internal load balancer. Must be an available
    IP address on the provided subnet name. Defaults to <code>10.0.0.4</code>. 
    </td></tr>

  <tr><td>vNetExistingResourceGroup</td><td>string</td>
    <td>The name of the Resource Group in which the Virtual Network resides when using an existing Virtual Network.
    <strong>Required when using an existing Virtual Network</strong>
    </td></tr>

  <tr><td>vNetNewAddressPrefix</td><td>string</td>
    <td>The address prefix when creating a new Virtual Network. Defaults to <code>10.0.0.0/16</code>. <strong>Required when creating a new Virtual Network</strong>
    </td></tr>

  <tr><td>vNetNewSubnetAddressPrefix</td><td>string</td>
    <td>The address space of the subnet. Defaults to <code>10.0.0.0/24</code>. <strong>Required when creating a new Virtual Network</strong>
    </td></tr>

  <tr><td>esPlugins</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> whether to install the X-Pack
    plugins: Shield, Watcher, Marvel and Graph (Elasticsearch version permitting), as well as Azure Cloud.
    </td></tr>

  <tr><td>kibana</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> provision an extra machine with a public IP that
    has Kibana installed on it. If you have opted to also install the Elasticsearch plugins using <code>esPlugins</code> then the Marvel and Sense Kibana apps get installed as well.
    </td></tr>

  <tr><td>jumpbox</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> Optionally add a virtual machine to the deployment which you can use to connect and manage virtual machines on the internal network.
    </td></tr>

  <tr><td>vmHostNamePrefix</td><td>string</td>
    <td>The prefix to use for hostnames when naming virtual machines in the cluster. Hostnames are used for resolution of master nodes so if you are deploying a cluster into an existing virtual network containing an existing Elasticsearch cluster, be sure to set this to a unique prefix, to differentiate the hostnames of this cluster from an existing cluster. Can be up to 5 characters in length, must begin with an alphanumeric character and can contain alphanumeric and hyphen characters.
    </td></tr>

  <tr><td>vmSizeDataNodes</td><td>string</td>
    <td>Azure VM size of the data nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>
    </td></tr>

  <tr><td>vmDataNodeCount</td><td>int</td>
    <td>The number of data nodes you wish to deploy. Should be greater than 0.
    </td></tr>

  <tr><td>dataNodesAreMasterEligible</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> Make all data nodes master eligible, this can be useful for small Elasticsearch clusters. When <code>Yes</code> no dedicated master nodes will be provisioned
    </td></tr>

  <tr><td>vmSizeMasterNodes</td><td>string</td>
    <td>Azure VM size of the master nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>. By default the template deploys 3 dedicated master nodes, unless <code>dataNodesAreMasterEligible</code> is set to <code>Yes</code>
    </td></tr>

  <tr><td>vmClientNodeCount</td><td>int</td>
    <td> The number of client nodes to provision. Defaults 0 and can be any positive integer. By default the data nodes are directly exposed on the loadbalancer. If you provision client nodes, only these will be added to the loadbalancer.
    </td></tr>

  <tr><td>vmSizeClientNodes</td><td>string</td>
    <td> Azure VM size of the client nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported sizes</a>.
    </td></tr>

  <tr><td>adminUsername</td><td>string</td>
    <td>Admin username used when provisioning virtual machines. Must be a valid Linux username i.e. <a target="_blank" href="https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-usernames/#_ubuntu">avoid any of the following usernames for Ubuntu</a> 
    </td></tr>

  <tr><td>authenticationType</td><td>object</td>
    <td>Either <code>password</code> or <code>sshPublicKey</code>  
    </td></tr>

  <tr><td>adminPassword</td><td>object</td>
    <td>When <code>authenticationType</code> is <code>password</code> this sets the OS level user's password
    </td></tr>

  <tr><td>sshPublicKey</td><td>object</td>
    <td>When <code>authenticationType</code> is <code>sshPublicKey</code> this sets the OS level sshKey that can be used to login.
    </td></tr>

  <tr><td>shieldAdminPassword</td><td>securestring</td>
    <td>Shield password for the <code>es_admin</code> user with admin role, must be &gt; 6 characters
    </td></tr>

  <tr><td>shieldReadPassword</td><td>securestring</td>
    <td>Shield password for the <code>es_read</code> user with user (read-only) role, must be &gt; 6 characters
    </td></tr>

  <tr><td>shieldKibanaPassword</td><td>securestring</td>
    <td>Shield password for the <code>es_kibana</code> user with kibana4 role, must be &gt; 6 characters
    </td></tr>

  <tr><td>location</td><td>string</td>
    <td>The location where to provision all the items in this template. Defaults to the special <code>ResourceGroup</code> value which means it will inherit the location
    from the resource group see <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">this list for supported locations</a>.
    </td></tr>

  <tr><td>userCompany</td><td>string</td>
    <td>The name of your company.
    </td></tr>

  <tr><td>userEmail</td><td>string</td>
    <td>Your email address
    </td></tr>

  <tr><td>userFirstName</td><td>string</td>
    <td>Your first name
    </td></tr>

  <tr><td>userLastName</td><td>string</td>
    <td>Your last name
    </td></tr>

  <tr><td>userJobTitle</td><td>string</td>
    <td>Your job title. Pick the nearest one that matches from <a href="https://github.com/elastic/azure-marketplace/blob/master/build/allowedValues.json">the list of job titles</a>
    </td></tr>

  <tr><td>userCountry</td><td>string</td>
    <td>The country in which you are based.
    </td></tr>

</table>

### Command line deploy

first make sure you are logged into azure

```shell
$ azure login
```

Then make sure you are in arm mode

```shell
$ azure config mode arm
```

Then create a resource group `<name>` in a `<location>` (e.g `westeurope`) where we can deploy too

```shell
$ azure group create <name> <location>
```

Next we can either use our published template directly using `--template-uri`

> $ azure group deployment create --template-uri https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json --parameters-file parameters/password.parameters.json -g name

or if your are executing commands from a clone of this repo using `--template-file`

> $ azure group deployment create --template-file src/mainTemplate.json --parameters-file parameters/password.parameters.json -g name

`<name>` in these last two examples refers to the resource group you just created.

**NOTE**

The `--parameters-file` can specify a different location for the items that get provisioned inside of the resource group. Make sure these are the same prior to deploying if you need them to be. Omitting location from the parameters file is another way to make sure the resources get deployed in the same location as the resource group.

### Web based deploy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FmainTemplate.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

The above button will take you to the autogenerated web based UI based on the parameters from the ARM template.

It should be pretty self explanatory except for password which only accepts a json object. Luckily the web UI lets you paste json in the text box. Here's an example:

> {"sshPublicKey":null,"authenticationType":"password", "password":"Elastic12"}


# License

This project is [MIT Licensed](https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt) and is based heavily on the [Elasticsearch azure quick start arm template](https://github.com/Azure/azure-quickstart-templates/tree/master/elasticsearch)
