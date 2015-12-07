# Elasticsearch Azure Marketplace offering

This repository consists of:

* [src/mainTemplate.json](src/mainTemplate.json) - Entry Azure Resource Management (ARM) template.
* [src/createUiDefinition](src/createUiDefinition.json) - UI definition file for our market place offering. This file produces an output JSON that the ARM template can accept as input parameters JSON.

## Building

After pulling call `npm install` once, this will pull in all devDependencies.

You may edit [src/allowedValues.json](src/allowedValues.json) the build will use these to patch the arm template and ui definition.

Run `npm run build`, this will validate EditorConfig settings, validate JSON files, patch the allowedValues and then create a zip in the `dist` folder.

## Marketplace

The market place Elasticsearch offering offers a simplified UI over the full power of the ARM template. It will always install a cluster complete with the elasticsearch plugins Shield, Watcher & Marvel.

![Example UI Flow](images/ui.gif)

TODO gif that shows how to find us on the real azure market place.

You can view the UI in developer mode by [clicking here](https://portal.azure.com/#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}}). If you feel something is cached improperly use [this client unoptimized link instead](https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/{"initialData":{},"providerConfig":{"createUiDefinition":"https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json"}})

## ARM template

The output from the market place UI is fed directly to the ARM template. You can use the ARM template on its own without going through the market place.

### Parameters

<table>
  <tr><th>Parameter</td><th>Type</th><th>Description</th></tr>
  <tr><td>esVersion</td><td>enum</td>
    <td>A valid supported Elasticsearch version see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/mainTemplate.json#L8">this list for supported versions</a>
    </td></tr>
  <tr><td>esClusterName</td><td>string</td>
    <td> The name of the Elasticsearch cluster
    </td></tr>

  <tr><td>loadBalancerType</td><td>string</td>
    <td>Whether the loadbalancer should be <code>internal</code> or <code>external</code>
    If you run <code>external</code> you should also install the shield plugin and look into setting up SSL on your endpoint
    </td></tr>

  <tr><td>esPlugins</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> whether to install the elasticsearch suite of
    plugins (Shield, Watcher, Marvel)
    </td></tr>

  <tr><td>kibana</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> provision an extra machine with a public IP that
    has Kibana installed on it. If you have opted to also install the Elasticsearch plugins using <code>esPlugins</code> then the Marvel and Sense Kibana apps get installed as well.
    </td></tr>

  <tr><td>jumpbox</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> Optionally add a virtual machine to the deployment which you can use to connect and manage virtual machines on the internal network.
    </td></tr>

  <tr><td>vmSizeDataNodes</td><td>string</td>
    <td>Azure VM size of the data nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/allowedValues.json">this list for supported sizes</a>
    </td></tr>

  <tr><td>vmDataNodeCount</td><td>int</td>
    <td>The number of data nodes you wish to deploy. Should be greater than 0.
    </td></tr>

  <tr><td>dataNodesAreMasterEligible</td><td>string</td>
    <td>Either <code>Yes</code> or <code>No</code> Make all data nodes master eligible, this can be useful for small Elasticsearch clusters. When <code>Yes</code> no dedicated master nodes will be provisioned
    </td></tr>

  <tr><td>vmSizeMasterNodes</td><td>string</td>
    <td>Azure VM size of the master nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/allowedValues.json">this list for supported sizes</a>. By default the template deploys 3 dedicated master nodes, unless <code>dataNodesAreMasterEligible</code> is set to <code>Yes</code>
    </td></tr>

  <tr><td>vmClientNodeCount</td><td>int</td>
    <td> The number of client nodes to provision. Defaults 0 and can be any positive integer. By default the data nodes are directly exposed on the loadbalancer. If you provision client nodes, only these will be added to the loadbalancer.
    </td></tr>

  <tr><td>vmSizeClientNodes</td><td>string</td>
    <td> Azure VM size of the client nodes see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/allowedValues.json">this list for supported sizes</a>.
    </td></tr>

  <tr><td>adminUsername</td><td>string</td>
    <td>Admin username used when provisioning virtual machines
    </td></tr>

  <tr><td>authenticationType</td><td>object</td>
    <td>Either <em>password</em> or <em>sshPublicKey</em>  
    </td></tr>

  <tr><td>adminPassword</td><td>object</td>
    <td>When <em>authenticationType</em> is <em>password</em> this sets the OS level user's password
    </td></tr>

  <tr><td>sshPublicKey</td><td>object</td>
    <td>When <em>authenticationType</em> is <em>sshPublicKey</em> this sets the OS level sshKey that can be used to login.
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
    from the resource group see <a href="https://github.com/elastic/azure-marketplace/blob/master/src/allowedValues.json">this list for supported locations</a>.
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
