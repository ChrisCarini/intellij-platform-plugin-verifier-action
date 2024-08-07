# IntelliJ Platform Plugin Verifier Action
A [GitHub Action](https://help.github.com/en/actions) for executing the [JetBrains intellij-plugin-verifier](https://github.com/JetBrains/intellij-plugin-verifier).

[![GitHub Marketplace](https://img.shields.io/github/v/release/ChrisCarini/intellij-platform-plugin-verifier-action?label=Marketplace&logo=GitHub)](https://github.com/marketplace/actions/intellij-platform-plugin-verifier)
[![GitHub Marketplace](https://img.shields.io/github/contributors/ChrisCarini/intellij-platform-plugin-verifier-action?label=Contributors&logo=GitHub)](https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/graphs/contributors)
[![GitHub Marketplace](https://img.shields.io/github/release-date/ChrisCarini/intellij-platform-plugin-verifier-action?label=Last%20Release&logo=GitHub)](https://github.com/ChrisCarini/intellij-platform-plugin-verifier-action/releases)
[![All Contributors](https://img.shields.io/github/all-contributors/ChrisCarini/intellij-platform-plugin-verifier-action?color=ee8449&style=flat-square)](#contributors)

# Usage
Add the action to your [GitHub Action Workflow file](https://help.github.com/en/actions/configuring-and-managing-workflows/configuring-a-workflow#creating-a-workflow-file) - the only thing you _need_ to specify are the JetBrains products & versions you wish to run against.

A minimal example of a workflow step is below:
```yaml
  - name: Verify Plugin on IntelliJ Platforms
    uses: ChrisCarini/intellij-platform-plugin-verifier-action@latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    with:
      ide-versions: |
        ideaIC:2019.3
```

## Installation

1) Create a `.yml` (or `.yaml`) file in your GitHub repository's `.github/workflows` folder. We will call this file `compatibility.yml` below.
1) Copy the below contents into `compatibility.yml` 
    ```yaml
    name: IntelliJ Platform Plugin Compatibility
    
    on:
      push:
    
    jobs:
      compatibility:
        name: Ensure plugin compatibility against 2019.3 for IDEA Community, IDEA Ultimate, PyCharm Community, GoLand, CLion, and the latest EAP snapshot of IDEA Community.
        runs-on: ubuntu-latest
        steps:
          - name: Check out repository
            uses: actions/checkout@v1
    
          - name: Setup Java 1.8
            uses: actions/setup-java@v1
            with:
              java-version: 1.8
    
          - name: Build the plugin using Gradle
            run: ./gradlew buildPlugin
    
          - name: Verify Plugin on IntelliJ Platforms
            id: verify
            uses: ChrisCarini/intellij-platform-plugin-verifier-action@latest
            env:
              GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            with:
              ide-versions: |
                ideaIC:2019.3
                ideaIU:2019.3
                pycharmPC:2019.3
                goland:2019.3
                clion:2019.3
                ideaIC:LATEST-EAP-SNAPSHOT
    
          - name: Get log file path and print contents
            run: |
              echo "The verifier log file [${{steps.verify.outputs.verification-output-log-filename}}] contents : " ;
              cat ${{steps.verify.outputs.verification-output-log-filename}}
    ```

### GitHub Token Authentication

In order to
prevent [GitHub Rate limiting](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting),
setting the `GITHUB_TOKEN` environment variable is **highly** encouraged.

_**Without**_ the `GITHUB_TOKEN` set, the requests are considered 'unauthenticated requests' by the GitHub API, and are
subject to 60 requests per hour for the originating IP
address. [GitHub-hosted runners are hosted in Azure, and have the same IP address ranges as Azure datacenters.](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#ip-addresses)
As a side effect of this, if the particular IP address of the GitHub-runner executing your GitHub Workflow has made 60
requests per hour, the API call to resolve the latest version of the `intellij-plugin-verifier` will fail, and this
action will not complete successfully.

_**With**_ the `GITHUB_TOKEN`
set, [each repository using this GitHub action will be allowed 1,000 requests per hour](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
(which is needed to resolve the latest version of the `intellij-plugin-verifier`). This should be ample for most
repositories.

## Options

This GitHub Action exposes 3 input options, only one of which is required.

| Input | Description | Usage | Default |
| :---: |  :--------- | :---: | :-----: |
| `verifier-version`  | The version of the [JetBrains intellij-plugin-verifier](https://github.com/JetBrains/intellij-plugin-verifier). The default of `LATEST` will automatically pull the most recently released version from GitHub - a specific version of the `intellij-plugin-verifier` can be optionally be pinned if desired. | *Optional* | `LATEST` |
| `plugin-location`  | The path to the `zip`-distribution of the plugin(s), generated by executing `./gradlew buildPlugin` | *Optional* | `build/distributions/*.zip` |
| `ide-versions`  | Releases of IntelliJ Platform IDEs and versions that should be used to validate against, formatted as a multi-line string as shown in the examples. Formatted as `<ide>:<version>` - see below for details. If you would prefer to have the list of IDE and versions stored in a file, see the **Configuration file for `<ide>:<version>`** section below for details. | *Required* | |
| `failure-levels`  | The different failure levels to set for the verifier. | *Required* | `COMPATIBILITY_PROBLEMS INVALID_PLUGIN`|

An example using all the available options is below:
```yaml
  - name: Verify Plugin on IntelliJ Platforms
    id: verify
    uses: ChrisCarini/intellij-platform-plugin-verifier-action@latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    with:
      verifier-version: '1.255'
      plugin-location: 'build/distributions/sample-intellij-plugin-*.zip'
      ide-versions: |
        ideaIC:LATEST-EAP-SNAPSHOT
      failure-levels: |
        COMPATIBILITY_PROBLEMS
        INVALID_PLUGIN
        NOT_DYNAMIC
``` 

### `verifier-version`

This optional input allows users to pin a specific version of `intellij-plugin-verifier` to be used during validation.

**WARNING:** Due to the deprecation fo Bintray services on 2021-05-01, JetBrains moved the verifier artifacts to their own
Maven repository (
See [`intellij-plugin-verifier` version `1.255` release notes](https://github.com/JetBrains/intellij-plugin-verifier/releases/tag/v1.255)
for details.). If you wish to specify a `verifier-version` in this GitHub Action, please ensure you are using **both**:
1) `intellij-plugin-verifier` version `1.255` or later

    **AND**

2) `intellij-platform-plugin-verifier-action` version `2.0.0` or later

### `plugin-location`

This optional input allows users to specify a different location for the plugin(s) `.zip` file. The default 
assumes that [gradle-intellij-plugin](https://github.com/JetBrains/gradle-intellij-plugin/) is being used to build
 the plugin(s).

### `ide-versions`

This required input sets which IDEs and versions the plugins will be validated against.

You can identify the value for `<ide>` and `<version>` as follows.

1) Navigate to the [IntelliJ 'Releases' Repository](https://www.jetbrains.com/intellij-repository/releases/)
   - **Note:** If you wish to find a snapshot of an IDE, please use the [IntelliJ 'Snapshots' Repository](https://www.jetbrains.com/intellij-repository/snapshots/).
1) Find the IDE and version you wish to use.
1) Copy the URL for the `.zip`.
1) Take **only** the `.zip` filename from the URL; example below:
    ```
    https://www.jetbrains.com/intellij-repository/releases/com/jetbrains/intellij/pycharm/pycharmPY/2019.3/pycharmPY-2019.3.zip
   ```
    becomes
    ```
    pycharmPY-2019.3.zip
    ```
1) Replace the `-` with a `:`, and remove the `.zip` from the end; example below:
    ```
    pycharmPY-2019.3.zip
   ```
    becomes
    ```
    pycharmPY:2019.3
    ```
1) This is the value you will use in `ide-versions`.

#### Some `<ide>` options
* [CLion](https://www.jetbrains.com/clion/) = `clion`
* [GoLand](https://www.jetbrains.com/go/) = `goland`
* [IntelliJ IDEA](https://www.jetbrains.com/idea/)
    * IntelliJ IDEA Community = `ideaIC`
    * IntelliJ IDEA Ultimate = `ideaIU`
* [PyCharm](https://www.jetbrains.com/pycharm/)
    * PyCharm Community = `pycharmPC`
    * PyCharm Professional = `pycharmPY`
* [Rider](https://www.jetbrains.com/rider/) = `riderRD`

#### Some `<version>` options
* Major versions (ie, `2019.3`)
* Minor versions (ie, `2019.3.4`)
* Specific build versions (ie, `193.6911.18`)
* `SNAPSHOT` versions
    * versions ending in `*-SNAPSHOT`
    * versions ending in `*-EAP-SNAPSHOT`
    * versions ending in `*-EAP-CANDIDATE-SNAPSHOT`
    * versions ending in `*-CUSTOM-SNAPSHOT`
* Latest EAP version (ie, `LATEST-EAP-SNAPSHOT`)

#### Configuration file for `<ide>:<version>`
If you would like to keep your GitHub Action workflow file tidy and free from constant changes, you can pass a relative 
file path to a file containing the IDE and versions. Below are the respective excerpts to use this feature.

**Workflow File:**
```yaml
- uses: actions/checkout@v2 # Your repository must be checked out in order to access the `ide_versions_file.txt` configuration file.
- name: Verify plugin on IntelliJ Platforms
  id: verify
  uses: ChrisCarini/intellij-platform-plugin-verifier-action@latest
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    ide-versions: .github/workflows/ide_versions_file.txt
```
**`.github/workflows/ide_versions_file.txt`**
```
ideaIC:2019.3
ideaIU:2019.3
pycharmPC:2019.3
goland:2019.3
clion:2019.3
ideaIC:LATEST-EAP-SNAPSHOT
```

(**Note:** The sample above will yield an execution identical to the one provided in the `Installation` section above.)

### `failure-levels`

This required input sets which plugin verifier failures to cause a failure in this action.

#### Valid options
|           Value           |  Search String                                                             |
| :-------------------------| :------------------------------------------------------------------------- |
| COMPATIBILITY_WARNINGS    | "Compatibility warnings"                                                   |
| COMPATIBILITY_PROBLEMS    | "Compatibility problems"                                                   |
| DEPRECATED_API_USAGES     | "Deprecated API usages"                                                    |
| EXPERIMENTAL_API_USAGES   | "Experimental API usages"                                                  |
| INTERNAL_API_USAGES       | "Internal API usages"                                                      |
| OVERRIDE_ONLY_API_USAGES  | "Override-only API usages"                                                 |
| NON_EXTENDABLE_API_USAGES | "Non-extendable API usages"                                                |
| PLUGIN_STRUCTURE_WARNINGS | "Plugin structure warnings"                                                |
| MISSING_DEPENDENCIES      | "Missing dependencies"                                                     |
| INVALID_PLUGIN            | "The following files specified for the verification are not valid plugins" |
| NOT_DYNAMIC               | "Plugin cannot be loaded/unloaded without IDE restart"                     |

**Note:** The default values are `COMPATIBILITY_PROBLEMS` and `INVALID_PLUGIN` for backwards compatibility. These were
the two default checks as of authoring this capability. This may change in the future, but a minor version bump (at a
minimum) will happen should that occur.

### `mute-plugin-problems`

This optional input sets which plugins problems will be ignored. Multiple values can be passed in as a comma-separated string.

See https://github.com/JetBrains/intellij-plugin-verifier?tab=readme-ov-file#check-plugin for more details.

#### Valid options

    - `ForbiddenPluginIdPrefix`
    - `TemplateWordInPluginId`
    - `TemplateWordInPluginName`

## Results
The results of the execution are captured in a file for use in subsequent steps if you so choose.

You will need to give the `intellij-platform-plugin-verifier-action` step an `id`.

You can then access the verifier output file by using `${{steps.<id>.outputs.verification-output-log-filename}}`.

In the below example, we use set the `id` to `verify` - this example will print the filename as well as the contents of the file as a subsequent step to the validation:

```yaml
      - name: Verify Plugin on IntelliJ Platforms
        id: verify
        uses: ChrisCarini/intellij-platform-plugin-verifier-action@latest
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          ide-versions: |
            ideaIC:2019.3

      - name: Get log file path and print contents
        run: |
          echo "The verifier log file [${{steps.verify.outputs.verification-output-log-filename}}] contents : " ;
          cat ${{steps.verify.outputs.verification-output-log-filename}}
```

(**Note:** The file contents will include both `stdout` and `stderr` output from the plugin verification CLI.)

# Examples

As examples of using this plugin you can check out following projects:

- [Automatic Power Saver](https://plugins.jetbrains.com/plugin/11941-automatic-power-saver) - Automatically enable / disable power save mode on window focus changes.
- [Environment Variable Settings Summary](https://plugins.jetbrains.com/plugin/10998-environment-variable-settings-summary) - Provides all system environment variables for troubleshooting.
- [Logshipper](https://plugins.jetbrains.com/plugin/11195-logshipper) - Ship your IDE logs to a logstash service.
- [intellij-sample-notification](https://plugins.jetbrains.com/plugin/10924-intellij-sample-notification) - Displays a simple notification upon Project Open.

# Contributing

Contributions welcomed! Feel free to open a PR, or issue.

## Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ChrisCarini"><img src="https://avatars.githubusercontent.com/u/6374067?v=4?s=100" width="100px;" alt="Chris Carini"/><br /><sub><b>Chris Carini</b></sub></a><br /><a href="#bug-ChrisCarini" title="Bug reports">🐛</a> <a href="#code-ChrisCarini" title="Code">💻</a> <a href="#doc-ChrisCarini" title="Documentation">📖</a> <a href="#example-ChrisCarini" title="Examples">💡</a> <a href="#ideas-ChrisCarini" title="Ideas, Planning, & Feedback">🤔</a> <a href="#maintenance-ChrisCarini" title="Maintenance">🚧</a> <a href="#question-ChrisCarini" title="Answering Questions">💬</a> <a href="#review-ChrisCarini" title="Reviewed Pull Requests">👀</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/peterlin741"><img src="https://avatars.githubusercontent.com/u/58699538?v=4?s=100" width="100px;" alt="Peter Lin"/><br /><sub><b>Peter Lin</b></sub></a><br /><a href="#bug-peterlin741" title="Bug reports">🐛</a> <a href="#code-peterlin741" title="Code">💻</a> <a href="#ideas-peterlin741" title="Ideas, Planning, & Feedback">🤔</a> <a href="#userTesting-peterlin741" title="User Testing">📓</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/takanuva15"><img src="https://avatars.githubusercontent.com/u/6986426?v=4?s=100" width="100px;" alt="takanuva15"/><br /><sub><b>takanuva15</b></sub></a><br /><a href="#bug-takanuva15" title="Bug reports">🐛</a> <a href="#code-takanuva15" title="Code">💻</a> <a href="#infra-takanuva15" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-takanuva15" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sadv1r"><img src="https://avatars.githubusercontent.com/u/5000487?v=4?s=100" width="100px;" alt="Dmitry"/><br /><sub><b>Dmitry</b></sub></a><br /><a href="#bug-sadv1r" title="Bug reports">🐛</a> <a href="#code-sadv1r" title="Code">💻</a> <a href="#infra-sadv1r" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-sadv1r" title="Maintenance">🚧</a> <a href="#userTesting-sadv1r" title="User Testing">📓</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.yanncebron.com/"><img src="https://avatars.githubusercontent.com/u/570887?v=4?s=100" width="100px;" alt="Yann Cébron"/><br /><sub><b>Yann Cébron</b></sub></a><br /><a href="#bug-YannCebron" title="Bug reports">🐛</a> <a href="#ideas-YannCebron" title="Ideas, Planning, & Feedback">🤔</a> <a href="#maintenance-YannCebron" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/serejke"><img src="https://avatars.githubusercontent.com/u/6849689?v=4?s=100" width="100px;" alt="Sergei Patrikeev"/><br /><sub><b>Sergei Patrikeev</b></sub></a><br /><a href="#infra-serejke" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-serejke" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://chrzanow.ski"><img src="https://avatars.githubusercontent.com/u/108333?v=4?s=100" width="100px;" alt="Jakub Chrzanowski"/><br /><sub><b>Jakub Chrzanowski</b></sub></a><br /><a href="#ideas-hsz" title="Ideas, Planning, & Feedback">🤔</a> <a href="#infra-hsz" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-hsz" title="Maintenance">🚧</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://dwojciechowski.com/"><img src="https://avatars.githubusercontent.com/u/18571662?v=4?s=100" width="100px;" alt="Dominik Wojciechowski"/><br /><sub><b>Dominik Wojciechowski</b></sub></a><br /><a href="#ideas-d-wojciechowski" title="Ideas, Planning, & Feedback">🤔</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/filiphr"><img src="https://avatars.githubusercontent.com/u/6012094?v=4?s=100" width="100px;" alt="Filip Hrisafov"/><br /><sub><b>Filip Hrisafov</b></sub></a><br /><a href="#bug-filiphr" title="Bug reports">🐛</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.halirutan.de"><img src="https://avatars.githubusercontent.com/u/511683?v=4?s=100" width="100px;" alt="Patrick Scheibe"/><br /><sub><b>Patrick Scheibe</b></sub></a><br /><a href="#bug-halirutan" title="Bug reports">🐛</a> <a href="#ideas-halirutan" title="Ideas, Planning, & Feedback">🤔</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://unthrottled.io"><img src="https://avatars.githubusercontent.com/u/15972415?v=4?s=100" width="100px;" alt="Alex Simons"/><br /><sub><b>Alex Simons</b></sub></a><br /><a href="#bug-Unthrottled" title="Bug reports">🐛</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/glex85"><img src="https://avatars.githubusercontent.com/u/54181288?v=4?s=100" width="100px;" alt="glex85"/><br /><sub><b>glex85</b></sub></a><br /><a href="#bug-glex85" title="Bug reports">🐛</a> <a href="#userTesting-glex85" title="User Testing">📓</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/etanshaul"><img src="https://avatars.githubusercontent.com/u/1735744?v=4?s=100" width="100px;" alt="Etan Shaul"/><br /><sub><b>Etan Shaul</b></sub></a><br /><a href="#ideas-etanshaul" title="Ideas, Planning, & Feedback">🤔</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/le-yams"><img src="https://avatars.githubusercontent.com/u/5181744?v=4?s=100" width="100px;" alt="Yann"/><br /><sub><b>Yann</b></sub></a><br /><a href="#bug-le-yams" title="Bug reports">🐛</a> <a href="#code-le-yams" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/drewbrokke"><img src="https://avatars.githubusercontent.com/u/6403097?v=4?s=100" width="100px;" alt="Drew Brokke"/><br /><sub><b>Drew Brokke</b></sub></a><br /><a href="#code-drewbrokke" title="Code">💻</a> <a href="#doc-drewbrokke" title="Documentation">📖</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

## Debugging
This action has [GitHub Actions Debug Logging](https://help.github.com/en/actions/configuring-and-managing-workflows/managing-a-workflow-run#enabling-step-debug-logging).

To enable, set the following secret in the repository that contains the workflow using this action to `true`.
- `ACTIONS_STEP_DEBUG`

You can find this under the repositories `Settings -> Secrets` menu.
