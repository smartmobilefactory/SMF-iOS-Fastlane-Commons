# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SMF-iOS-Fastlane-Commons is a shared Fastlane automation framework for iOS and macOS apps at Smart Mobile Factory GmbH. The core principle is "Commons first" - implement CI/CD features once and share across all projects via configuration-driven flows.

## Core Architecture Principles

### 1. Configuration-Driven Design
All project-specific behavior is controlled via `Config.json` (not function parameters). This enables the "opt-out" pattern where projects automatically get updates by referencing a branch rather than a fixed version.

### 2. Three-Tier Structure

**Flows** (`fastlane/flow/`)
- High-level workflows called from project Fastfiles
- Main flows: `smf_deploy_app`, `smf_publish_pod`, `smf_check_pr`, `smf_perform_ui_tests_*`
- Handle multiple build variants, exception handling, and orchestrate steps

**Steps** (`fastlane/steps/`)
- Granular, single-purpose tasks grouped by topic
- Groups: CocoaPods, Danger, Git, GitHub, HockeyApp, iTunesConnect, MetaJSON, Notifications, PhraseApp, UI-Tests, Xcode-Build
- Called by flows, not directly from projects

**Constants** (`fastlane/utils/Constants.rb`)
- Environment variable keys and shared constants
- Reference this file for all ENV key names

### 3. Project Integration Pattern

Projects need minimal Fastlane setup:
- `Config.json` - All project configuration (see documentation/Configuration.md)
- `Fastfile` - Defines `fastlane_config_path` lane and imports Commons in `before_all`
- Project lanes only: set build variant, enable notifications, call Commons flow
- `Appfile`, `Dangerfile`, `Gemfile` - Usually just import Commons defaults

## Key Configuration Concepts

### Build Variants
Nested under `build_variants` in Config.json. Each variant can specify:
- Build settings (scheme, bundle_id, team_id, code_signing_identity)
- Feature flags (upload_itc, use_hockey, generateMetaJSON)
- Platform-specific settings (platform: "mac" for macOS)
- PR behavior (pr.archive_ipa, pr.perform_unit_tests, pr.run_danger)

### Project Settings
Nested under `project` in Config.json:
- `project_name` - Xcode project/workspace name
- `fastlane_commons_branch` - Which Commons branch to use
- `slack_channel` - For notifications
- `tag_prefix`/`tag_suffix` - Git tag customization

### Extension Suffixes
Array at root level for app extensions (e.g., ["findersync", "widget"])

### Danger Configuration
Nested under `danger_config`, merged with `danger/danger_defaults.json`

### PhraseApp Integration
Nested under build variant's `phrase_app` key with project_id, locales, format, files, base_directory

### Sparkle (macOS Updates)
Nested under build variant's `sparkle` key for DMG distribution

## Common Workflows

### App Deployment Flow (fastlane/flow/App.rb)
1. Generate MetaJSON (optional)
2. Install CocoaPods
3. Increment build number (optional)
4. Verify Git tag doesn't exist
5. Sync PhraseApp strings
6. Archive IPA
7. Commit generated code
8. Run unit tests (stores coverage in MetaJSON)
9. Commit build number
10. Build simulator app (for UI tests)
11. Collect changelog from Git commits
12. Upload to HockeyApp and/or App Store Connect
13. Create Git tag and GitHub release
14. Send notifications

### Pod Publishing Flow (fastlane/flow/Pod.rb)
1. Verify on correct branch
2. Bump version (major/minor/patch or breaking/internal for 4-part versions)
3. Verify Git tag doesn't exist
4. Generate MetaJSON
5. Commit version bump
6. Collect changelog
7. Create Git tag
8. Push to temporary branch
9. Pod push to specs repo (public or private)
10. Push to real branch
11. Create GitHub release
12. Send notifications

### PR Check Flow (fastlane/flow/Shared.rb)
For each build variant:
1. Update generated setup file (pipeline jobs)
2. Install CocoaPods
3. Archive IPA (optional, configurable per variant)
4. Run unit tests (optional, configurable per variant)
5. Run Danger (optional, configurable per variant)

### UI Tests Flow (fastlane/flow/UI-Tests.rb)
1. Fetch GitHub release assets (.app and .ipa)
2. Download provisioning profiles
3. Install app on simulators and devices
4. Run tests on all destinations
5. Generate reports
6. Uninstall from all devices
7. Send notifications

## Development Commands

### Testing Changes
When modifying Commons, test against a project by:
1. Set `fastlane_commons_branch` to your feature branch in project's Config.json
2. Run the project's Fastfile lanes (they auto-download Commons)

### Common Environment Variables
See `fastlane/utils/Constants.rb` for all keys. Key ones:
- `$SMF_CHANGELOG_ENV_KEY` - Generated changelog
- `$SMF_GITHUB_TOKEN_ENV_KEY` - GitHub access
- `$SMF_HOCKEYAPP_API_TOKEN_ENV_KEY` - HockeyApp uploads
- `$SMF_SLACK_URL` - Slack notifications
- `$WORKSPACE_ENV_KEY` - Jenkins workspace path

### Gemfile Templates
- `pipeline/App_Gemfile.template` - For app projects
- `pipeline/Pod_Gemfile.template` - For Pod projects
- Both specify: fastlane 2.228.0, cocoapods 1.16.0, danger, slather, fastlane-plugin-sentry

## Important Notes

### Multi-Variant Builds
Flows support building multiple variants in one job via `@smf_build_variants_array`. Flags are reset between variants to avoid state leakage.

### Build Number Management
Build number incrementation is tracked via ENV flags. If build fails, `smf_decrement_build_number` reverts changes.

### Xcode Version Management
Uses `$XCODE_EXECUTABLE_PATH_PREFIX` and `$XCODE_EXECUTABLE_PATH_POSTFIX` to locate specific Xcode versions at `/Applications/Xcode-<version>.app`

### Git Tag Format
Tags follow pattern: `{tag_prefix}{version}({build_number}){tag_suffix}`
- Apps: default prefix is `build/{build_variant}/`
- Pods: default prefix is `releases/`

### HockeyApp Cleanup
On build failure, uploaded HockeyApp versions are automatically deleted. Former beta entries are disabled on successful deployment.

### App Store Connect Handling
ITC upload is last step because it often shows errors despite success. Job continues even if it fails.

### MetaJSON
Project insights tool (separate system). Generated in `.MetaJSON-temp/` folder, includes:
- Xcode build warnings/errors (from `build/reports/errors.json`)
- Unit test results and code coverage (via slather)
- Linter results

### Sentry Integration
Self-hosted at `https://sentry.solutions.smfhq.com/`. Upload dSYMs after HockeyApp upload using fastlane-plugin-sentry.

### Match for Code Signing
Uses `$FASTLANE_MATCH_REPO_URL` pointing to `git@github.com:smartmobilefactory/SMF-iOS-Fastlane-Match.git`

## File Structure

```
fastlane/
├── flow/              # High-level workflows
│   ├── App.rb        # App deployment flows
│   ├── Pod.rb        # Pod publishing flows
│   ├── Shared.rb     # PR checks, notifications, exception handling
│   └── UI-Tests.rb   # Separated UI test flows
├── steps/             # Granular tasks by topic
│   ├── Xcode-Build.rb
│   ├── CocoaPods.rb
│   ├── Git.rb
│   ├── GitHub.rb
│   ├── HockeyApp.rb
│   ├── iTunesConnect.rb
│   ├── Danger.rb
│   ├── MetaJSON.rb
│   ├── Notifications.rb
│   ├── PhraseApp.rb
│   ├── Sentry.rb
│   ├── Pipeline.rb
│   └── UI-Tests.rb
├── actions/           # Custom Fastlane actions
│   ├── delete_app_version_on_hockey.rb
│   └── disable_hockey_download.rb
└── utils/
    └── Constants.rb   # ENV keys and shared constants

danger/
├── Dangerfile         # Shared Danger rules
└── danger_defaults.json

pipeline/
├── App_Gemfile.template
└── Pod_Gemfile.template

documentation/
├── Configuration.md   # Complete Config.json reference
├── Flows.md          # Detailed flow documentation
├── Steps.md          # Steps overview
└── What_is_needed_in_a_project.md
```

## Versioning Schemes

### Standard (Apps & Most Pods)
- `major.minor.patch` (e.g., 1.2.3)
- Bump types: "major", "minor", "patch"

### Four-Part (Some Pods)
- `major.minor.breaking.internal` (e.g., 1.2.5.3)
- major/minor: Set manually
- breaking: Bumps patch component, resets internal to 0
- internal: Increments last component
- Bump types: "breaking", "internal"

## When Modifying Commons

1. Never break existing Config.json keys without migration plan
2. Add new features as opt-in (default: false/nil) to avoid breaking projects
3. Document new config keys in documentation/Configuration.md
4. Test with multiple projects before merging to master
5. Consider that projects auto-update from branch references

## Available Tools for Task Management

### Jira Ticket Creation
You have two primary tools available for creating and managing Jira tickets:

#### 1. ACLI (Atlassian CLI)
```bash
# Basic ticket creation
~/ACLI/acli sosimple --action createIssue --project [PROJECT] --type Task --summary "Summary" --description "Description"

# Full example with all common parameters
~/ACLI/acli sosimple --action createIssue \
  --project [PROJECT] \
  --type Task \
  --summary "Task summary" \
  --description "h2. Description in Jira Wiki format" \
  --components "Component Name" \
  --priority "Major" \
  --fixVersions "3.3.4" \
  --originalEstimate "3h"

# Get available components for a project
~/ACLI/acli sosimple --action getComponentList --project [PROJECT]

# Get available priorities
~/ACLI/acli sosimple --action getPriorityList
```

#### 2. MCP Atlassian Integration
```bash
# Available MCP Atlassian functions for Jira:
mcp__atlassian__createJiraIssue
mcp__atlassian__getJiraIssue
mcp__atlassian__editJiraIssue
mcp__atlassian__getJiraIssueRemoteIssueLinks
mcp__atlassian__searchJiraIssuesUsingJql
mcp__atlassian__addCommentToJiraIssue
mcp__atlassian__transitionJiraIssue
mcp__atlassian__getTransitionsForJiraIssue
```

### Confluence Content Management

#### MCP Atlassian Integration for Confluence
```bash
# Available MCP Atlassian functions for Confluence:
mcp__atlassian__getConfluenceSpaces
mcp__atlassian__getConfluencePage
mcp__atlassian__getPagesInConfluenceSpace
mcp__atlassian__createConfluencePage
mcp__atlassian__updateConfluencePage
mcp__atlassian__searchConfluenceUsingCql
mcp__atlassian__getConfluencePageFooterComments
mcp__atlassian__getConfluencePageInlineComments
mcp__atlassian__createConfluenceFooterComment
mcp__atlassian__createConfluenceInlineComment
```

### Common Jira Priorities
- `Blocker` (ID: 1) - Blocks development/testing, production cannot run
- `Critical` (ID: 2) - Crashes, data loss, severe memory leak
- `Major` (ID: 3) - Major loss of function - **Default**
- `Minor` (ID: 4) - Minor loss of function, easy workaround available
- `Trivial` (ID: 5) - Cosmetic problems

### Default Values for Ticket Creation
- **Priority**: `Major` (equivalent to "medium")
- **originalEstimate**: `3h` (Original estimate for time to complete work)

### Working with Remote Links
Use `mcp__atlassian__getJiraIssueRemoteIssueLinks` to fetch related tickets across different Jira instances and link them in documentation or release notes.