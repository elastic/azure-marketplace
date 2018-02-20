# Getting Started

Run the following to bring down all the dependencies

```bash
$ npm install
```

# Build

To build the project call

```bash
$ npm run build
```

This will patch the templates according to the configured `build/allowedValues.json` and generate the various data node templates as well as doing several sanity checks and assertions.

The result will be a distribution zip under `dist/elasticsearch-marketplace-DATE.zip` ready to be uploaded to the publisher portal.


## Development

New features should be developed on separate branches and merged back into `master` once complete. To aid in the development process, a gulp task is configured to update all of the github template urls to point at a specific branch so that UI definition and web based deployments can be tested. To run the task

```sh
npm run links
```

will update the links to point to the name of the current branch. Once ready to merge back into `master`, a specific branch name can be passed with

```sh
npm run links -- --branch master
```

If you fork the repository, you can update the links to point to your own github repository using

```sh
npm run links -- --repo <username>/<repo> --branch <branch>
```

where

- `<username>` is your github username and `<repo>` is the name of the Azure Marketplace github repository. Defaults to the remote origin repository.
- `<branch>` is the name of the branch. Defaults to the name of the current branch 

## Test

For this you need to create a [Create a Service Principal - Azure CLI](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/get-started/create-service-principal.md).

Then copy the `.test.example.json` file and enter your details

```bash
$ cp build/.test.example.json build/.test.json
```

`.test.json` is git ignored but always take extra care not to commit this file or a copy of it.


```bash
$ npm test
```

Will login to azure create resource group in the form of `test-[scenario]-[date]` and do an online validation of the template using the scenario's parameters.
When done (failures or not) this command will clean up the resource groups and logout of azure.

```bash
$ npm run deploy-all
```

Same as `npm test` but will try and deploy all scenarios expected to be valid once all the scenarios have been validated.
It will do some post install checks on the deployed cluster if it can.

```bash
$ npm run azure-cleanup
```
Will remove all resource-groups starting with `test-*`

## Automated UI tests

The automated ui tests are not (yet) part of the main test command to run them:

```bash
$ npm run headless
```
