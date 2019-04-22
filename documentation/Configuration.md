# Configuration

# Goal

A huge part of the logic to support the [Fastlane commons vision](../README.md#Goal) is the configuration json. It contains all the information which is needed to support different types of projects, enable or disables features in flows etc. As it's stored in a special file - which can be accessed everywhere in Fastlane Commons - it's easy to add new features without changing many lines of source code - e.g. in the projects Fastfile.

# Structure

The configuration is stored in a JSON file. There is a set of available keys, which you can find here. In general there is a separation of things which are depended on the complete project and depended on a single build variant.

## Project

The project configuration is nested in the root level key `project`.

|Key|Default Value|Mandatory|Description|
|---|---|---|---|
|project\_name|`nil`|☑️|The name of the Xcode project and / or workspace files|
|slack\_channel|`nil`||The name of the Slack channel (without `#`)|
|fastlane\_commons\_branch|`nil`|☑️|The branch which will be used to download Fastlane Commons|
|tag\_prefix|`"build/#{build\_variant}/"` (App) or `"releases/"` (Pod)||The prefix which is added to the Git tag of an app or Pod release|
|tag\_suffix|`nil`||The suffix which is added to the Git tag of an app or Pod release|
|github\_repo\_path|`nil`|☑️ (for UI Tests)| The GitHub repo path (<organisation/user>/<repo name>) of the project which contains the .app and .ipa to test against|
|use_custom_fastfile| `false` | | Optional Parameter that determines if the `Fastfile` will be overwritten in a PR |
|use_custom_gemfile| `false` | | Optional Parameter that determines if the `Gemfile`will be overwritten in a PR |

## Danger

The project configuration is nested in the root level key `danger_config`.

Each feature from Danger can be en- and disabled. You can see [default Danger config](../danger/danger_defaults.json) to learn about the existing keys and features. The Danger configuration of the project will be merged with the default configuration. If you only need to modify e.g. one feature, you can only declare this one and still all the other default values will be used.

If you need to have a special configuration for one build variant, you can create a custom root level key and declare its name in the build variant key `danger_config_name`. Otherwise `danger_config` is used.

## Build Variants

The build variants configuration is nested in the root level key `build_variants`. You need to add the build variants as map.

|Key|Default Value|Mandatory|Description|
|---|---|---|---|
|attach\_build\_outputs\_to\_github|`false`||If enabled, the build .ipa and simulator .app will be attached to the GitHub release. This is needed for the separated UI test setup. |
|bundle\_identifier|`nil`|☑️ (for Apps)||
|code\_signing\_identity| `nil` |☑️ (for Apps)|The name of the signing identity. E.g. "iPhone Distribution: Smart Mobile Factory GmbH"|
|disable\_concurrent\_testing|`false`||Disable concurrent testing of UI tests. |
|download\_provisioning\_profiles|`true`||If disabled, the provisioning profiles won't be downloaded during the build job.|
|export\_method|`nil`||The Xcode archive export method to use. This needs to be set for special cases only. |
|generateMetaJSON|`true`||If disabled, MetaJSON won't analyze the project. |
|hockeyapp\_id|`nil`||The identifier of the HockeyApp project which should be used to upload the app to.|
|icloud\_environment|`"Development"`|||
|itc\_apple\_id|`nil`||The Apple ID to use for App Store Connect.|
|itc\_skip\_version\_check|`true`||If enabled, the build won't check if there is a matching editable app version present in App Store Connect. |
|itc\_skip\_waiting|`false`||If enabled, the build job won't wait until App Store Connect processed the .ipa.|
|itc\_team\_id|`nil`||The team id to use for App Store Connect.|
|keychain\_enabled|`true`||If disabled, the Jenkins keychain won't be unlocked. This should be done if you want to run Fastlane locally without the Jenkins environment.|
|phrase\_app\_script|`nil`||The path to the script file which syncs the Strings with PhraseApp. E.g. "fastlane/sync\_hidrive\_strings.sh".|
|platform|original platform|☑️ (for macOS)|Can be used to modify the platform. This has to be done for macOS apps: "mac".|
|pods\_specs\_repo|`nil`|☑️ (for private Pods)|The url of the CocoaPods Specs Repo. This has to be set if it's not the official CocoaPods Specs Repo.|
|podspec\_path|`nil`|☑️ (for Pods)|The path to the Podspec file.|
|pr.archive\_ipa|`true` (App), `false` (Pod)||If enabled, a pull request check will archive the app to test if this is possible.|
|pr.perform\_unit\_tests|`true`||If enabled, a pull request check will perform the unit tests.|
|pr.run\_danger|`true`||If enabled, a pull request check will run Danger.|
|push\_generated\_code|`false` (no PhraseApp), `true` (with PhraseApp snyc)||If enabled, code which changed after a project was built will be committed. This needs be done if e.g. PhraseApp is combined with R.swift as code might change after the Strings have been synced.|
|scheme|`nil`|☑️ (for Apps)|The scheme which should be build.|
|should\_clean\_project|`true` (single or first build variant), `false` (second or later build variant in a row)||If disabled, xcodebuild won't be told to clean before building an app.|
|slack\_enabled|`true`||If disabled, no Slack notifications will be sentn. This should be done if you want to run Fastlane locally without the Jenkins environment.|
|target|`nil`||The target which is built. This is needed in some cases to read the version number.|
|team\_id|`nil`|☑️ (for Apps)|The Team ID to use for the Apple Member Center.|
|tests.device\_to\_test\_against|`nil`||Can be used to specify the target device for unit tests. This can be useful if e.g. only an iPad should be used for tests.|
|ui\_test.target.bundle\_identifier|`nil`||The bundle identifier of the app which a separated UI test should target.|
|ui\_test\_triggering\_github\_releases|`nil`||A regex which is used to match GitHub releases which are intended to trigger a separated UI test.|
|unit\_test\_scheme|scheme of the build variant||The scheme to use if unit tests are performed. This manual information is only needed in special cases.|
|upload\_bitcode|`true`||If disabled, Bitcode won't be uploaded.|
|upload\_itc|`false`||If enabled, the .ipa will be uploaded to App Store Connect.|
|use\_hockey|`true`||If disabled, the .ipa won't be uploaded to HockeyApp|
|use\_wildcard\_signing|`false`||If enabled, the Wildcard provisioning profile will be downloaded instead of one which matches the bundle identifier.|
|xcconfig\_name|`nil`||The name of the xcconfig to build. This is needed if xcconfig files are used instead of targets.|
|use\_sparkle|`false`|If enabled, the release will be distributed with Sparkle.|Configuration Will be taken from the `sparkle` Json|

### Phrase App Synchronisation Variables
The Phrase-App synchronisation scripts need certain environment variables. The values for theses variables are stored in the nested dictionary ```phrase_app```. These entries exist for each build variant that needs to sync with phrase app and are therefore nested inside the given build-variant entry.

|Key|Default Value|Datatype| Mandatory |Description|
|---|---|---|---|---|
|```access_token_key```| ```"SMF_PHRASEAPP_ACCESS_TOKEN"```|```String```| ☑️| The variable name in which jenkins stores the access token for the phrase app api. The default value is ```"SMF_PHRASEAPP_ACCESS_TOKEN"``` which should work for almost all projects. An exception are the Strato projects, they should use ```"stratoPhraseappAccessToken"```.|
|```project_id```| ```nil```|```String```|  ☑️| The projects phrase app id which is used in the api call to identify the correct project. This should be an all lowercase hexadecimal string with 32 digits. For example ```"12abc345bf6e980d96e5b0a236fe78b1"```|
|```source```| ```nil```|```String```| ☑️| This value should be an identifier for the language which is used as source for the translation. This is ```"en"``` in the most of the cases.|
|```locales```| ```nil```|```Array of Strings```| ☑️| A list of language identifiers to which the strings of the app will be translated. For example ```["de", "at", "es", "fr"]```|
|```format```| ```nil```|```String```| ☑️| Determines the format in which the phrase app translation files are stored. This is in almost all cases ```"strings"```. But it could also be for example ```"simple_json"```or ```"xml"``` or another format.|
|```base_directory```| ```nil```|```String```| ☑️| This string specifies the base directory in which the different translation files will be stored. |
|```files```| ```nil```|```Array of Strings```| ☑️| A list of files which will be translated.|
|```git_branch```| ```@smf_git_branch```|```String```| | The projects git branch to which new or changed translations will be pushed. The default is the branch which is passed to the fastlane build job.|
|```files_prefix```| ```""```|```String```| |Specifies a prefix for the file tags.|
|```forbi_comments_in_source```| ```true```|```Bool```| | If this is set to true, the phrase app scripts abort if the find an comments in the source file. This is due to some weird behavoir of the PhrasApp if there are comments in the source file.|

If there are extensions which need to be synced with the phrase app, too, this can be done by adding an ```extensions``` array nested in the ```phrase_app``` entry. For each extension the array should contain entry with keys: ```project_id, base_directory and files```.

Here a template for the ```phrase_app``` structure:

```
"alpha": {
		...		
		"phrase_app" : {
			"format"		: "...",
			"access_token_key"	: "...",
			"project_id"		: "...",
			"source"		: "...",
			"locales"		: [
				"...",
				"..."
			],
			"base_directory"	: "...",
			"files"				: [
				"...",
				"..."
			],
			"forbid_comments_in_source"	: false/true,
			"files_prefix"			: "...",
			"git_branch"			: "...",
			"extensions"			: [
				{
					"project_id"		: "...",
					"base_directory"	: "...",
					"files"				: [
						"...",
						"..."
					]
				}
			]
		}

}
```
## Extension Suffixes

The extension suffixes are nested in the root level key `extensions_suffixes`. It's an array which should contain the app extension bundle identifier suffixes.

If you have an app with the bundle identifier `my.app` and an extensions `my.app.findersync`, the extension suffix would be `findersync`. This is needed to let Fastlane download the correct provisioning profiles.

## Sparkle Configuration

|Key|Description|
|---|---|
|`signing_key`|The private Key from sparkle's `generate_key`-Tool. The according public Key should be set in the `info.Plist` of the Target.|
|`upload_url`|The Host Address that is used to upload the `.xml` and the `.dmg` file using `scp`. **Note:** Since this is used in a Script, the Host-URL should be listed in the known-hosts.| 
|`upload_user`|The User that is used to upload Files with `scp`|
|`xml_name`|The filename of the XML, this filename will should be equal to the one that is referenced in the `info.Plist`.|
|`dmg_path`|The Path on the Server where the `.dmg` File will be placed. **Note:** The `.dmg` File will always be named like the target.|
|`sparkle_version`|The Version of the Tool Kit, provided from Sparkle, this will be downloaded from Github to sign the `.xml` File and the `.dmg` File.|
|`sparkle_signing_team`|A Team that can sign the Sparkle Tools to let them access the Keychain without prompting. This is an important Step, otherwise the Update process would be insecure.|

