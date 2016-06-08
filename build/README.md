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

# Test

```bash
$ npm test
```
Will do a live validation of the ARM template by calling `azure template validate`, it won't actually start the deploys. For this you need to create a [Create a Service Principal - Azure CLI](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/get-started/create-service-principal.md).



# Automated ui tests

The automated ui tests are not (yet) part of the main test command to run them please

```bash
$ cp build\ui-tests-config.example.json ui-tests-config.json
```

and alter it with your details **IMPORTANT** this file is ignored in git **NEVER** check this file in to source control

```bash
$ npm run headless
```
