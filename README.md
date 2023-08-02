# Business Central/NAV ARM Templates

In order to deploy ARM templates from your fork, use:
`https://freddyk.azurewebsites.net/api/deploy?template=https://raw.githubusercontent.com/<githubusername>/nav-arm-templates/<branch>/<template>.json`

Where
- `<githubusername>` is your GitHub user name (location of the fork)
- `<branch>` is the branch you want to deploy from
- `<template>` is the name of the template to use

## Available templates

| Name | Description |
|---|---|
| getbc | Get Azure VM with Business Central on Docker with standard questionnaire |
| getbcext | Get Azure VM with Business Central on Docker with extended questionnaire |
| buildagent | Get Azure VM pre-configured as Build Agent for GitHub or Azure DevOps |
| getnav | Get Azure VM with NAV on Docker with standard questionnaire |
| getnavext | Get Azure VM with NAV on Docker with extended questionnaire |

**Note:** You can add parameters for prepopulating fields in the ARM template.

## Examples
- getbc -> https://freddyk.azurewebsites.net/api/deploy?template=https://raw.githubusercontent.com/freddydk/nav-arm-templates/master/getbc.json&nchbranch=preview&vmname=myvm
- buildagent -> https://freddyk.azurewebsites.net/api/deploy?template=https://raw.githubusercontent.com/freddydk/nav-arm-templates/master/buildagent.json&nchbranch=preview

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
