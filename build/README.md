# Getting Started

Run the following to bring down all the dependencies

```bash
$ npm install
```

## Build

To build the project call

```bash
npm run build
```

This will patch the templates according to the configured `build/allowedValues.json` and generate the various data node templates as well as doing several sanity checks and assertions.

The result will be a distribution zip under `dist/elasticsearch-marketplace-<date>.zip` ready to be uploaded to the publisher portal.

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

## Testing

For this you need to create a [Create a Service Principal - Azure CLI](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/get-started/create-service-principal.md).

Then copy the `.test.example.json` file and enter the credentials for the Service Principal into `.test.json`

```bash
cp build/.test.example.json build/.test.json
```

`.test.json` is git ignored but **always take extra care not to commit this file or make a copy of it**.

Now that the test file is set up, tests can be run with

```bash
npm run test
```

Which will login to the Azure account accessible by the Service Principal account and create a
resource group with the name `test-<machinename>-<scenario>-<date>` and perform online validation
of the template using the scenarios parameters.
When done, the command will clean up the resource groups and logout of azure.

Tests use the template checked into the github repository branch, so be sure to push any changes that need to be tested up to GitHub.

### Testing a specific version

By default, tests always use the last version specified in the versions array in `build/allowedValues.json`, but you can specify a version using

```bash
npm run test -- --version 6.2.4
```

A random value from the versions array can also be used

```bash
npm run test -- --version random
```

### Specifying tests to run

All test scenarios in `build/arm-tests` are run by default. Specific tests can be targeted with

```bash
npm run test -- --test 3d.*
```

where the `--test` parameter is a regular expression to include tests to run.

### Deploying tests

the `test` command will simply validate that the template parameters are valid, but a deployment can be performed with

```bash
npm run deploy-all
```

This is similar to `test` but will try and deploy all scenarios with `isValid:true`, once all the scenarios have been validated.
Some post install checks are performed on the deployed cluster to assert successful deployment.

**NOTE:** Be sure that you have sufficient core quota in the subscription and location into which you're deploying.

### Cleaning up resource groups

Both `test` and `deploy-all` will attempt to clean up the resource groups created as part of a test run, but sometimes this
may not happen e.g. testing process stopped part-way through. When this happens, you can run

```bash
npm run azure-cleanup
```

to remove all resource-groups starting with `test-*`

## Automated UI tests

The automated ui tests are not (yet) part of the main test command to run them:

```bash
npm run headless
```
