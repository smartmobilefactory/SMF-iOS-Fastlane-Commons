# What is needed in a project?

As most of the logic is implemented in Fastlane Commons, the project doesn't need to contain that much logic.

Besides some mandatory files from Fastlane most importantly the Fastlane Commons configuration is needed:

* `fastlane` folder
* `fastlane/Config.json`
* `fastlane/Fastfile`
* `fastlane/Appfile`
* `fastlane/Dangerfile`
* `fastlane/Gemfile`

## fastlane/Config.json
This file contains the custom configuration of Fastlane Commons. The filename can be changed as it has to be provided in the Fastfile. A detailed documentation of the configuration can be found [here](Configuration.md).

[Example file](project_example/Appfile)

## fastlane/Fastfile
This file is an pfficial Fastlane file. It needs to be used to add the lanes which are accessable from the outside - e.g. from Jenkins.
There is some mandatory logic needed for Fastlane Commons:

* The lane `fastlane_config_path` which returns the path to the configuration JSON
* The import of Fastlane Commons in `before_all`

Additionally only the lanes `check_pr` and `deploy_app` or `publish_pod` are needed in most projects.

As most of the logic is configured in the configuration JSON and implemented in Fastlane Commons, the lanes only need to:

* set the builds variant
* activate notifications (if wanted)
* set the git branch (in some cases)
* call a Fastlane Commons flow

Besides this default setup it's still possible to create whatever lanes and logic you want, as long as Fastlane supports it.

[Example file](project_example/Fastfile)

## fastlane/Appfile
This file is an official Fastlane file. It can be used to set e.g. credentials. In most projects which is only used to set the Apple ID for the Member Center.

[Example file](project_example/Appfile)

## fastlane/Dangerfile
This is an official Danger file. It normally contains the logic to run Danger. As most of our Danger logic in implemented in Fastlane Commons, the projects Dangerfile will normally only contain the import of the Fastlane Commons Dangerfile and maybe some custom rules afterwards.

[Example file](project_example/Dangerfile)

## fastlane/Gemfile
The Gemfile is needed declare the dependencies for Danger. Normally a project shouldn't need to change anything of the default file content. You can take a look in the Example file to see what is needed.

[Example file](project_example/Gemfile)
