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

## Danger

The project configuration is nested in the root level key `danger_config`.

Each feature from Danger can be en- and disabled. You can see [default Danger config](../danger/danger_defaults.json) to learn about the existing keys and features. The Danger configuration of the project will be merged with the default configuration. If you only need to modify e.g. one feature, you can only declare this one and still all the other default values will be used.

If you need to have a special configuration for one build variant, you can create a custom root level key and declare its name in the build variant key `danger_config_name`. Otherwise `danger_config` is used.

## Build Variants

The build variants configuration is nested in the root level key `build_variants`. You need to add the build variants as map.

|Key|Default Value|Mandatory|Description|
|---|---|---|---|
|attach\_build\_outputs\_to\_github|`false`|||
|bundle\_identifier|`nil`|☑️ (for Apps)||
|code\_signing\_identity| `nil` |☑️ (for Apps)||
|disable\_concurrent\_testing|`false`|||
|download\_provisioning\_profiles|`true`|||
|export\_method|`nil`|||
|generateMetaJSON|`true`|||
|hockeyapp\_id|`nil`|||
|icloud\_environment|`"Development"`|||
|itc\_apple\_id|`nil`|||
|itc\_skip\_version\_check|`true`|||
|itc\_skip\_waiting|`false`|||
|itc\_team\_id|`nil`|||
|keychain\_enabled|`true`|||
|mailgun\_enabled|`true`|||
|phrase\_app\_script|`nil`|||
|platform|original platform|||
|pods\_specs\_repo|`nil`|☑️ (for Pods)||
|podspec\_path|`nil`|☑️ (for Pods)||
|pr.archive\_ipa|`true` (App), `false` (Pod)|||
|pr.perform\_unit\_test|`true`|||
|pr.run\_danger|`true`|||
|push\_generated\_code|`false` (no PhraseApp), `true` (with PhraseApp snyc)|||
|scheme|`nil`|☑️ (for Apps)||
|should\_clean\_project|`true` (single or first build variant), `false` (second or later build variant in a row)|||
|slack\_enabled|`true`|||
|sparkle.signing\_identity||||
|sparkle\_s3aws\_bucket|`nil`|||
|target|`nil`|||
|team\_id|`nil`|☑️ (for Apps)||
|tests.device\_to\_test\_against|`nil`|||
|ui\_test.target.bundle\_identifier|`nil`|||
|ui\_test\_triggering\_github\_releases|`nil`|||
|unit\_test\_scheme|scheme of the build variant|||
|upload\_bitcode|`true`|||
|upload\_itc|`false`|||
|use\_hockey|`true`|||
|use\_sparkle|`false`|||
|use\_wildcard\_signing|`false`|||
|xcconfig\_name|`nil`|||

## Extension Suffixes

The extension suffixes are nested in the root level key `extensions_suffixes`. It's an array which should contain the app extension bundle identifier suffixes.

If you have an app with the bundle identifier `my.app` and an extensions `my.app.findersync`, the extension suffix would be `findersync`. This is needed to let Fastlane download the correct provisioning profiles.



