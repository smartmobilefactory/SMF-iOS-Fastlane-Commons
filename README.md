# SMF-iOS-Fastlane-Commons

This repo contains the shared Fastlane code which is used across the iOS and macOS apps of Smart Mobile Factory GmbH.

# Goal

There is one vision behind Fastlane Commons:

> Provide all Continuous Integration features we use to all apps and implement features and fixes only once

Result of this vision are a few rules / concepts:

### Commons first
Each project should contain as less Fastlane logic as possible. If new features are needed in a project, they should be placed in almost all cases in the shared Commons code instead of a project itself. It's very likely that a feature will also be needed in other projects.

Some exceptions are eg. features which are needed for Strato for their UI tests usage. In this case it's clear that only one project is affected, there is no intersection with our environment and the client shouldn't need our Commons repo to do his things.

### Opt-out

The projects shouldn't be updated to support new features or bugfixes if possible. This is archived by referencing to a branch in Fastlane Commons instead of a specific release or commit. The Fastfile of a project downloads the shared Commons as first step during the execution. This ensures that always the newest codebase is used.
  
### Config.json instead of function parameters

To allow the opt-out idea, the configuration should be done in the Config.json instead of passing parameters to Fastlane functions.
It's unclear which configuration is needed in which place in the future. By storing and accessing it in one central place, we can use it in any place which knows where the Congig.json is stored.

If we would only provide the parameters which are currently needed, we would need to modify the projects once the content is also needed somewhere else deep inside the Fastlane Commons codebase.

## Features

### Pull Requests

- [x] Builds iOS and macOS apps to verify that they can be compiled
- [x] Builds framework targets to verify that they can be compiled
- [x] Performs unit tests
- [x] Runs Danger
- [x] Collects project insights which are added to MetaJSON

### Deploying

- [x] Builds iOS and macOS apps
- [x] Uploads apps to HockeyApp and App Store Connect
- [x] Builds CocoaPod Pods
- [x] Releases CocoaPod Pods in the official and private Spec repos
- [x] Creates special build outputs for UI tests
- [x] Creates release notes based on the commit history
- [x] Syncs Strings with PhraseApp
- [x] Sends notifications via mail and HipChat with status updates
- [x] Collects project insights which are added to MetaJSON

### Dedicated UI-Test projects

- [x] Performs UI tests which are stored in a separated project
- [x] Sends notifications via mail and HipChat with status updates


Most logic is written in Ruby, only some precompiled code is written in Java and Swift.

## Documentation

The documentation will split into the following areas:

- [Flows](documentation/Flows.md)
- [Steps](documentation/Steps.md)
- [Configuration](documentation/Configuration.md)
- [What is needed in a project?](documentation/What_is_needed_in_a_project.md)
