# Flows

You can find documentation of the existing Flows here. An overview of the complete project and links to other documentation can be found in the [README](../README.md).

# Goal

A huge part of the logic to support the [Fastlane commons vision](../README.md#Goal) is to provide Flows. A flow should normally be the only Commons function which is called from a project during a build job. They perform the usual workflows across all apps. Diferences between projects are handled with the [configuration](Configuration.md).


# Flows

Note: internal lanes should normally only be called from Fastlane commons code internally.

## App

### smf\_deploy\_app

This flow is meant to be called from the Fastfile of a project and performs all steps which are needed to deploy one ore multiple app build variants.

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Iterates through all declared build variants | |
| Performs the deploy provess for each build variant | smf\_deploy\_build\_variant |

### smf\_deploy\_build\_variant [internal]

This internal flow contains all the steps which are needed to deploy one app build variant.

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |

##### Parameters

| Name | Description |
|:---|---|
| *bulk\_deploy\_params* | A map which contains the current index and total count of multiple build variants |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Resets Flags which are created during the build job to support multiple build variants in a row |
| Generates MetaJSON | | ☑️ |
| Installs the Pods | smf\_install\_pods\_if\_project\_contains\_podfile |
| Increments the build number | smf\_increment\_build\_number | ☑️ |
| Verifies that the Git tag is not already existing | smf\_verify\_git\_tag\_is\_not\_already\_existing |
| Verifies that common App Store Connect upload errors aren't present | smf\_verify\_common\_itc\_upload\_errors | ☑️ |
| Syncs strings with PhraseApp | smf\_sync\_strings\_with\_phrase\_app |
| Archives the app | smf\_archive\_ipa |
| Push generated code which changed - might happen eg. with PhraseApp sync and R.swift in combination | smf\_commit\_generated\_code |
| Store build errors and warnings in MetaJSON | | ☑️ |
| Performs the unit tests and stores the code coverage in MetaJSON (optioanl) |
| - Send a failure message to the CI HipChat room in case this step fails |
| Commits the incremented build number | smf\_commit\_build\_number |
| Genereates special simulator apps for UI tests | smf\_build\_simulator\_app | ☑️ |
| Creates the change log based on Git commits | smf\_collect\_changelog |
| Uploads the app version to HockeyApp | smf\_upload\_ipa\_to\_hockey | ☑️ |
| Disables the download of the former Beta app version on HockeyApp | smf\_disable\_former\_hockey\_entry | ☑️ |
| Sends the push notifications for SMF HockeyApp with OneSingal | smf\_send\_ios\_hockey\_app\_apn |
|  - Sends a failure message to the CI HipChat room in case this step fails |
| Creates the Git tag | smf\_add\_git\_tag |
| Pushes the changes to the remote repo |
| Creates the GitHub release | smf\_create\_github\_release |
| Sends notifications about the success | smf\_send\_deploy\_success\_notifications |
| Performs the Fastlane App Store Connect precheck | smf\_itunes\_precheck | ☑️ |
| Uploads the app to App Store Connect | smf\_upload\_ipa\_to\_testflight | ☑️ |
| - Waits for the processing in App Store Connect | | ☑️ |
| Sends notifications to the HipChat room about the App Store Connect result |

## Pod

### smf\_publish\_pod

This flow is meant to be called from the Fastfile of a project and performs all steps which are needed to publish a new Pod version. It supports the public Specs repo as well as private ones.

##### Preconditions

| Precondition |
|:---|
| A bump type is set |
| A git branch is set |
| Failure notifications are enabled - if wanted |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Unlocks the Jenkins keychains | | ☑️ |
| Verifies the Git repo is on the chosen branch |
| Bumps version number.<br>Depending on the project configuration:<br>- major, minor, patch<br>- internal, breaking | | ☑️ |
| Verifies that the Git tag is not already existing | smf\_verify\_git\_tag\_is\_not\_already\_existing |
| Generates MetaJSON | smf\_generate\_meta\_json | ☑️ |
| - Sends a failure message to the CI HipChat room in case MetaJSON couldn't be created|
| Commits the version bump |
| Creates the change log based on Git commits | smf\_collect\_changelog |
| Creates the Git tag | smf\_add\_git\_tag |
| Pushes the changes to a temporary branch of the remote repo |
| Performs Pod push to a private or public Pod Specs repo | smf\_pod\_push |
| - Deletes the temporary branch on the remote repo in case Pod push failed |
| - Sends notifications about the build failure |
| Pushes the changes to the real remote branch |
| Removes the temporary branch on the remote repo |
| Creates the GitHub release | smf\_create\_github\_release |
| Sends notifications about the success | smf\_send\_deploy\_success\_notifications |
| Updates the local Pod repo |

## UI-Tests

### smf\_perform\_ui\_tests\_with\_tag\_name

This flow is meant to be called from the Fastfile of a project and performs all steps which are needed for separated UI tests based on a GitHub release name.

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |
| The GitHub release contains the device and simulator apps |

##### Parameters

| Name | Description |
|:---|---|
| *simulators* | A comma seperated String which contains the type of all simulators to use |
| *github\_token* | The GitHub access token to use |
| *report\_sync\_destination* | The path to the folder where the report should be stored |
| *tag\_name* | The name of the GitHub release which should be tested |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Fetches the assets of the release | smf\_fetch\_assets\_for\_tag |
| Performs the ui tests on all connected real devices and the specified simulators | smf\_perform\_ui\_tests\_with\_assets |

### smf\_perform\_ui\_tests\_from\_github\_webhook

This flow is meant to be called from the Fastfile of a project and performs all steps which are needed for separated UI tests based on GitHub release webhook content.

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |
| The GitHub release contains the device and simulator apps |
| A webhook is connected to the Jenkins build job |

##### Parameters

| Name | Description |
|:---|---|
| *simulators* | A comma separated String which contains the type of all simulators to use
| *github\_token* | The GitHub access token to use
| *report\_sync\_destination* | The path to the folder where the report should be stored
| *payload* | The complete payload of the GitHub webhook

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Performs the ui tests on all connected real devices and the specified simulators | smf\_perform\_ui\_tests\_with\_assets |

### smf\_perform\_ui\_tests\_with\_assets [internal]

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |
| The GitHub release contains the device and simulator apps |

##### Parameters

| Name | Description |
|:---|---|
| *assets* | An array of asset maps (from GitHub Releases) which should be used |
| *tag\_name* | The name of the GitHub release which should be tested |
| *report\_sync\_destination* | The path to the folder where the report should be stored |
| *github\_token* | The GitHub access token to use |
| *simulators* | A comma separated String which contains the type of all simulators to use |
 
##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Verifies that the given tag (aka app) is configured to be tested |
| - Stops the build job in case the tag (aka app) shouldn't be tested |
| Downloads the provisioning profiles | smf\_download\_provisioning\_profiles\_if\_needed |
| Downloads the asset files | smf\_download\_asset |
| Performs the UI tests on all connected devices and specified simulators | smf\_perform\_all\_ui\_tests |

### smf\_perform\_all\_ui\_tests [internal]

This internal flow prepares the simulators and devices to the point that the tests can be performed. Also the clean up is down. In between the tests are executed, the report created and notifications send.

##### Preconditions

| Precondition |
|:---|
| A build variant ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |
| The GitHub release contains the device and simulator apps |

##### Parameters

| Name | Description |
|:---|---|
| *simulator\_build\_asset\_path* | The path to the downloaded simulator asset |
| *device\_build\_asset\_path* | The path to the downloaded real device asset |
| *report\_sync\_destination* | The path to the folder where the report should be stored |
| *report\_name* | The name of report |
| *simulators* | A comma separated String which contains the type of all simulators to use |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Installs Pods | smf\_install\_pods\_if\_project\_contains\_podfile |
| Shuts down simulators to avoid the case that too many simulators are open (would prevent testing) | smf\_shutdown\_simulators |
| Installs the app on the specified simulators | smf\_install\_app\_on\_simulators |
| Installs the app on all connected real devices | smf\_install\_app\_on\_devices |
| Starts the UI tests including the report creation and notifications | smf\_perform\_uitests\_on\_given\_destinations |
| Uninstalls the app on the specified simulators afterwards | smf\_uninstall\_app\_on\_simulators |
| Uninstalls the app on all connected real devices afterwards | smf\_uninstall\_app\_on\_devices |

## Shared

### smf\_check\_pr

This flow is meant to be called from the Fastfile of a project and performs all steps which are needed to check a pull request. Multiple build variants are supported.

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Iterates through all build variants and performs the following steps | | |
| Archives IPA | smf\_archive\_ipa\_if\_scheme\_is\_provided | ☑️ |
| Performs unit tests | smf\_perform\_unit\_tests | ☑️ |
| Runs Danger | smf\_run\_danger | ☑️ |

### smf\_send\_deploy\_success\_notifications [internal]

This internal flow collects the change-log and sends the deploy success notifications.

##### Preconditions

| Precondition |
|:---|
| A build variant or bump type ist set |
| A git branch is set |
| Failure notifications are enabled |

##### Parameters

| Name | Description |
|:---|---|
| *app\_link* | The URL of the uploaded app. If none is provided, the result of the HockeyApp lane is taken |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Creates the change log based on Git commits | | |
| Sends mail to contributors | smf\_send\_mail\_to\_contributors | ☑️
| Sends notifications to a HipChat room | | ☑️ |

### smf\_handle\_exception [internal]

This internal flow collects the change-log, does some cleanup and sends the build job exception notification.

Note: Not all exception notifications are sent from this lane. It's only used if no other place is caching the failure. In those cases custom exception notifications might be send and the build job continues afterwards.

##### Preconditions

| Precondition |
|:---|
| A build variant or bump type ist set |
| A git branch is set |
| Failure notifications are enabled - if wanted |

##### Parameters

| Name | Description |
|:---|---|
| *message* | The message to show |
| *exception* | The exception which occurred |

##### Tasks in order of their execution

| Task | Logic is extracted to lane / function | Optional? |
|:---|---|---|
| Deletes the uploaded app version from HockeyApp |
| Creates the change log based on Git commits |
| Sends mail to contributors | smf\_send\_mail\_to\_contributors |
| Sends notifications to a HipChat room | | ☑️ |