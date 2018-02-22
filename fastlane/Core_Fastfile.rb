fastlane_require 'net/https'
fastlane_require 'uri'
fastlane_require 'json'

METAJSON_TEMP_FOLDERNAME = ".MetaJSON-temp"

########################################
########################################
### LANES TO BE USED BY THE PROJECTS ###
########################################
########################################

######################
### smf_deploy_app ###
######################

desc "Builds the project including build number incrementation, MetaJSON etc. and uploads the version to Hockey."
private_lane :smf_deploy_app do |options|

  UI.important("Deploy a new app version")

  # Cleanup

  # Reset the HockeyApp ID to avoid that a successful upload is removed if a following build variant is failing in the same build job
  ENV["SMF_APP_HOCKEY_ID"] = nil

  # Reset the build incrementation flag to support build jobs which build multiple build variants in a row
  ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = nil

  # Read options parameter
  build_variant = options[:build_variant].downcase
  build_variants_config = options[:build_variants_config]
  branch = options[:branch]
  project_config = build_variants_config["project"]
  build_variant_config = build_variants_config["targets"][build_variant]
  project_name = project_config["project_name"]
  # Optional parameters
  should_perform_unit_test = (build_variant_config["perform_unit_tests"].nil? ? false : build_variant_config["perform_unit_tests"])
  should_clean_project = (options[:should_clean_project].nil? ? true : options[:should_clean_project])
  generateMetaJSON = options[:generateMetaJSON]
  use_sigh = (options[:use_sigh].nil? ? true : options[:use_sigh])
  use_hockey = (options[:use_hockey].nil? ? true : options[:use_hockey])
  push_generated_code = (options[:push_generated_code].nil? ? false : options[:push_generated_code])

  # Cleanup the temporary MetaJSON folder in case it exists from a former build
  if generateMetaJSON != false
    workspace = ENV["WORKSPACE"]
    sh "if [ -d #{workspace}/#{METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{METAJSON_TEMP_FOLDERNAME}; fi"
    sh "mkdir #{workspace}/#{METAJSON_TEMP_FOLDERNAME}"
  end

  # check if the next Tag exist
  smf_check_tag(
    project_config: project_config,
    build_variant: build_variant
    )

  # Increment the build number only if it should
  if smf_should_build_number_be_incremented
    smf_increment_build_number(
      project_config: project_config
      )
  end

  # Build and archive the IPA
  smf_archive_ipa(
    should_clean_project: should_clean_project,
    project_config: project_config,
    build_variant: build_variant,
    build_variants_config: build_variants_config,
    use_sigh: use_sigh
    )

  # Copy the Xcode warnings and errors report to keep the files available for MetaJSON
  if generateMetaJSON != false
    workspace = ENV["WORKSPACE"]
    sh "if [ -f #{workspace}/build/reports/errors.json ]; then cp #{workspace}/build/reports/errors.json #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/xcodebuild.json; fi"
  end

  # Run unit tests and then run linter to generate JSONs
  if should_perform_unit_test
    smf_perform_unit_tests(
      project_config: project_config,
      build_variant_config: build_variant_config
    )
  end

  # Commit generated code. There can be changes eg. from PhraseApp + R.swift
  if push_generated_code
    smf_commit_generated_code(
      branch: branch
    )
  end

  # Update the MetaJSONS if wanted
  if generateMetaJSON != false
    begin
      smf_run_linter

      smf_run_slather(build_variant_config["scheme"], project_name)

      smf_generate_meta_json(
        project_config: project_config,
        build_variant: build_variant,
        branch: branch
      )
      smf_commit_meta_json(
      	branch: branch
      )
    rescue
      UI.important("Warning: MetaJSON couldn't be created")

      message = "<table><tr><td><strong>Failed to create MetaJSON for #{project_name} #{build_variant.upcase} 😢</strong></td></tr><tr><td><strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a></td></tr></table>"

      smf_send_message_to_hipchat_ci_room(
        project_name: project_name,
        message: message,
        success: false
      )
    end
  end

  # Commit the build number if it was incremented
  if smf_should_build_number_be_incremented
    smf_commit_build_number(
      project_config: project_config,
      branch: branch
    )
  end

  # Collect the changelog 
  smf_collect_changelog(
    build_variant: build_variant,
    project_config: project_config
    )

  if use_hockey
    ENV["SMF_APP_HOCKEY_ID"] = build_variant_config["hockeyapp_id"]
    # Upload the IPA to HockeyApp
    smf_upload_ipa_to_hockey(
      build_variant_config: build_variant_config,
      project_config: project_config
      )
    
    # Disable the former HockeyApp entry
    smf_disable_former_hockey_entry(
      build_variant: build_variant,
      build_variant_config: build_variant_config,
      build_variants_contains_whitelist: ["beta"]
      )

    # Inform the SMF HockeyApp about the new app version
    begin
      smf_send_ios_hockey_app_apn(
        hockeyapp_id: ENV["SMF_APP_HOCKEY_ID"]
      )
    rescue
      UI.important("Warning: The APN to the SMF HockeyApp couldn't be sent!")

      message = "<table><tr><td><strong>Failed to send APN to SMF HockeyApp for #{project_name} #{build_variant.upcase} 😢</strong></td></tr><tr><td><strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a></td></tr></table>"

      smf_send_message_to_hipchat_ci_room(
        project_name: project_name,
        message: message,
        success: false
      )
    end
  end

  tag = smf_add_git_tag(
    project_config: project_config,
    branch: branch,
    tag_prefix: "build/#{build_variant}/"
  )

  smf_git_pull

  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: branch,
    force: false,
    tags: true
  )

  # Create the GitHub release
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  smf_create_github_release(
    release_name: "#{build_variant.upcase} (#{version})",
    tag: "#{tag}",
    branch: branch
  )

  smf_handle_deploy_app_success(
    build_variant: build_variant,
    project_config: project_config
    )

  # Upload Ipa to Testflight and Download the generated DSYM
  # The testflight upload should happen as last step as the upload often shows an error although the IPA was successfully uploaded. We still want the tag, HockeyApp upload etc in this case.
  if build_variant_config["upload_itc"] == true

    if build_variant_config.key?("itc_team_id")
      ENV["FASTLANE_ITC_TEAM_ID"] = build_variant_config["itc_team_id"]
    end

    smf_itunes_precheck(
      project_config: project_config,
      build_variant_config: build_variant_config
    )

    notification_message = ""
    itc_upload_succeeded = false

    begin
      smf_upload_ipa_to_testflight(
        build_variant_config: build_variant_config
      )

      skip_waiting = should_skip_waiting_after_itc_upload(options[:build_variant_config])

      smf_download_dsym_from_testflight(
        project_config: project_config,
        build_variant_config: build_variant_config
      )

      skipped_waiting_message = ""
      if skip_waiting
        skipped_waiting_message = "The build job didn't wait until iTunes Connect processed the build. Errors might still occur! ⚠️"
      else
        skipped_waiting_message = "The IPA was processed by Apple without any errors 👍"
      end

      notification_message = "<table><tr><td><strong>Uploaded #{project_name} #{build_variant.upcase} to iTunes Connect 🎉</strong></td></tr><tr><td>skipped_waiting_message</td></tr>/table>"
      itc_upload_succeeded = true
    rescue => e 
      UI.important("Warning: The upload to iTunes Connect failed!")

      notification_message = "<table><tr><td><strong>Failed to upload #{project_name} #{build_variant.upcase} to iTunes Connect 😢</strong></td></tr><tr><td>As iTunes Connect often response with an error altough the IPA was successfully uploaded, you may want to check iTunes Connect to know if the upload worked or not.</td></tr><tr><td><strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a></td></tr></table>"
      itc_upload_succeeded = false
    end

    smf_send_message_to_hipchat_project_room(
        build_variant: build_variant,
        project_config: project_config,
        success: itc_upload_succeeded,
        message: notification_message
      )
  end

end


#######################
### smf_publish_pod ###
#######################

# options: branch (String), tag_prefix (String) [optional], bump_type (String), podspec_path (String), repository_path (String), specs_repo (String)

desc "Publish the pod. Either to the official specs repo or to the SMF specs repo"
private_lane :smf_publish_pod do |options|

  UI.important("Publish Pod")

  # Read options parameter
  framework_config = options[:framework_config]
  project_config = options[:project_config]
  branch = options[:branch]
  generateMetaJSON = options[:generateMetaJSON]
  tag_prefix = (options[:tag_prefix].nil? ? "" : options[:tag_prefix])
  bump_type = options[:bump_type]
  podspec_path = framework_config["podsepc_path"]
  repository_path = project_config["github_repo_path"]
  specs_repo = framework_config["pods_specs_repo"]


  # Unlock keycahin to enable pull repo with https
  unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])

  unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])

  # Make sure the repo is up to date and clean
  ensure_git_branch(branch: branch)
  ensure_git_status_clean

  # Bump the pods version if needed
  if ["major", "minor", "patch"].include? bump_type
    version_bump_podspec(
      path: podspec_path,
      bump_type: bump_type
      )
  end
  
  # Update the MetaJSONS if wanted
  if generateMetaJSON != false
    begin
      smf_generate_meta_json(
        project_config: project_config,
        build_variant: bump_type,
        branch: branch
        )
      smf_commit_meta_json(
      	branch: branch
      )
    rescue
      UI.important("Warning: MetaJSON couldn't be created")

      project_name = options[:project_config]["project_name"]

      message = "<table><tr><td><strong>Failed to create MetaJSON for #{project_name} #{bump_type.upcase} 😢</strong></td></tr><tr><td><strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a></td></tr></table>"

      smf_send_message_to_hipchat_ci_room(
        project_name: project_name,
        message: message,
        success: false
      )
      next
    end
  end

  version = read_podspec(path: podspec_path)["version"]

  # Commit the version bump if needed
  if ["major", "minor", "patch"].include? bump_type
    git_commit(
      path: podspec_path,
      message: "Release Pod #{version}"
      )
  end

  smf_collect_changelog(
    build_variant: bump_type,
    project_config: project_config,
    tag_prefix: tag_prefix
    )

  # Add the git tag
  begin
    add_git_tag(
      tag: "#{tag_prefix}#{version}"
    )
  rescue
    raise "Git tag already existed".red
  end

  smf_git_pull

  # Push the changes to a temporary branch
  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: "jenkins_build/#{branch}",
    force: false,
    tags: true
  )
  
  begin
    # Publish the pod. Either to a private specs repo or to the offical one
    if specs_repo
      pod_push(
        repo: specs_repo,
        path: podspec_path,
        allow_warnings: true
        )
    else
      pod_push(path: podspec_path)
    end

  rescue => e 
    # Remove the git tag
    sh "git push --delete origin #{tag_prefix}#{version} || true"
    # Remove the temporary git branch
    sh "git push origin --delete jenkins_build/#{branch} || true"

    raise "Pod push failed: #{e.message}"
  end

  # Push the changes to the original branch
  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: branch,
    force: false,
    tags: true
  )

  # Remove the temporary git branch
  sh "git push origin --delete jenkins_build/#{branch} || true"

  # Create the GitHub release
  smf_create_github_release(
    release_name: version,
    tag: "#{tag_prefix}#{version}",
    branch: branch,
    ignore_existing_release: true
  )

  # Update the CocoaPods repo to avoid unknown Pod version issues if this Pod is integrated into another project
  sh "pod repo update"

  smf_handle_pod_publish_success(
    build_variant: bump_type,
    project_config: project_config,
    framework_config: framework_config
    )

end

############################
### smf_test_pod_project ###
############################

# options: project_config (Hash), framework_config (Hash). "perform_unit_tests" is handeld as opt-out

desc "Performs the unit tests of the pod."
private_lane :smf_test_pod_project do |options|

  UI.important("Test the pod")

  # Read options parameter
  project_config = options[:project_config]
  framework_config = options[:framework_config]
  should_perform_unit_test = (framework_config["perform_unit_tests"].nil? ? true : framework_config["perform_unit_tests"])

  if should_perform_unit_test
    smf_perform_unit_tests(
      project_config: project_config,
      build_variant_config: framework_config
    )
  end

  fastlane_commons_branch = project_config["fastlane_commons_branch"]

  smf_run_danger(options[:build_variant_config], "frameworks", fastlane_commons_branch)

end

############################
### smf_test_app_project ###
############################

# options: project_config (Hash), build_variant (String), build_variants_config (Hash). "perform_unit_tests" is handeld as opt-in

desc "Performs the unit tests of the pod."
private_lane :smf_test_app_project do |options|

  UI.important("Test the app project: Build an IPA and unit tests (opt-in).")

  # Read options parameter
  project_config = options[:project_config]
  build_variant = options[:build_variant]
  build_variants_config = options[:build_variants_config]
  build_variant_config = build_variants_config["targets"][build_variant]
  should_perform_unit_test = (build_variant_config["perform_unit_tests"].nil? ? false : build_variant_config["perform_unit_tests"])
  should_clean_project = (options[:should_clean_project].nil? ? true : options[:should_clean_project])
  use_sigh = (options[:use_sigh].nil? ? true : options[:use_sigh])

  # Build only the IPA to test if the project is compiling
  smf_archive_ipa(
    should_clean_project: should_clean_project,
    project_config: project_config,
    build_variant: build_variant,
    build_variants_config: build_variants_config,
    use_sigh: use_sigh
  )

  if should_perform_unit_test
    smf_perform_unit_tests(
      project_config: project_config,
      build_variant_config: build_variant_config
    )
  end

  fastlane_commons_branch = project_config["fastlane_commons_branch"]

  smf_run_danger(options[:build_variant], "targets", fastlane_commons_branch)
end

######################
######################
### INTERNAL LANES ###
######################
######################

#####################################
### smf_handle_deploy_app_success ###
#####################################

# options: build_variant (String), project_config (Hash), release_title (String) [optional], app_link (String) [optional] [default: HockeyApp Link]

desc "Handle the success by sending email to the authors and post to the hipchat channel"
private_lane :smf_handle_deploy_app_success do |options|

  UI.important("Handle the build job success")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  release_title = (options[:release_title].nil? ? smf_default_app_notification_release_title(project_config["project_name"], build_variant) : options[:release_title])
  hipchat_channel = project_config["hipchat_channel"]
  app_link = (options[:app_link].nil? ? Actions.lane_context[Actions::SharedValues::HOCKEY_DOWNLOAD_LINK] : options[:app_link])

  if ENV["SMF_CHANGELOG"].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog(
      build_variant: build_variant,
      project_config: project_config
      )
  end

  message_title = "Built #{release_title} 🎉"

  smf_notify_via_mail(
    title: message_title,
    message: "#{release_title} is now available!",
    release_title: release_title,
    success: true,
    app_link: app_link
    )

  if hipchat_channel
    hipchat_channel = URI.escape(hipchat_channel)
    smf_notify_via_hipchat(
      title: message_title,
      message: ENV["SMF_CHANGELOG"],
      project_name: project_config["name"],
      project_config: project_config,
      hipchat_channel: hipchat_channel,
      success: true
      )
  end
end

################################################
### smf_send_message_to_hipchat_project_room ###
################################################

# options: build_variant (String), project_config (Hash), success (String), message: String [optional]

desc "Send a message to the hipchat channel of the current project"
private_lane :smf_send_message_to_hipchat_project_room do |options|

  UI.important("Send HipChat message to project room")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  success = options[:success]
  message = options[:message]
  hipchat_channel = project_config["hipchat_channel"]

  if hipchat_channel
    hipchat_channel = URI.escape(hipchat_channel)
    hipchat(
      message: message,
      channel: hipchat_channel,
      success: success,
      api_token: ENV["HIPCHAT_API_TOKEN"],
      notify_room: true,
      version: "2",
      message_format: "html",
      include_html_header: false,
      from: "#{project_config["project_name"]} iOS CI"
    )
  end
end

######################################
### smf_handle_pod_publish_success ###
######################################

# options: build_variant (String), project_config (Hash), framework_config (Hash), release_title (String) [optional]

desc "Handle the success by sending email to the authors and post to the hipchat channel"
private_lane :smf_handle_pod_publish_success do |options|

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  framework_config = options[:framework_config]

  release_title = (options[:release_title].nil? ? smf_default_pod_notification_release_title(project_config["project_name"], framework_config) : options[:release_title])

  smf_handle_deploy_app_success(
    build_variant: build_variant,
    release_title: release_title,
    project_config: project_config,
    app_link: ""
    )
end


############################
### smf_handle_exception ###
############################

# options: exception (exception), build_variant (String), project_config (Hash), release_title (String) [optional]

desc "Handle the exception by sending email to the authors"
private_lane :smf_handle_exception do |options|

  UI.important("Handle the build job exception")

  # Read options parameter
  exception = options[:exception]
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  hipchat_channel = project_config["hipchat_channel"]
  release_title = (options[:release_title].nil? ? smf_default_app_notification_release_title(project_config["project_name"], build_variant) : options[:release_title])

  apps_hockey_id = ENV["SMF_APP_HOCKEY_ID"]
  if not apps_hockey_id.nil?
    begin
      smf_delete_uploaded_hockey_entry(
        apps_hockey_id: apps_hockey_id
      )
    rescue
      UI.message("The HockeyApp entry wasn't removed. This is fine if it wasn't yet uploaded")
    end
  end

  if ENV["SMF_CHANGELOG"].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog(
      build_variant: build_variant,
      project_config: project_config
      )
  end

  message_title = "Failed to build #{release_title} 😢"

  smf_notify_via_mail(
    title: message_title,
    message: message_title,
    success: false,
    exception_message: exception,
    app_link: ""
    )

    if hipchat_channel
      hipchat_channel = URI.escape(hipchat_channel)

      smf_notify_via_hipchat(
        title: message_title,
        message: "#{exception.message}",
        project_name: project_config["name"],
        additional_html_entries: ["strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a>"],
        hipchat_channel: hipchat_channel,
        success: false
        )
    end
end

#######################
### smf_archive_ipa ###
#######################

# options: build_variants_config (Hash), project_config (Hash), build_variant (String), use_sigh (string) [Optional], should_clean_project (String) [Optional]

desc "Build the project based on the build type."
private_lane :smf_archive_ipa do |options|

  UI.important("Build a new version")

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  build_variant = options[:build_variant].downcase
  build_variant_config = options[:build_variants_config]["targets"][build_variant]
  use_sigh = (options[:use_sigh].nil? ? true : options[:use_sigh])
  should_clean_project = (options[:should_clean_project].nil? ? true : options[:should_clean_project])
  icloud_environment = (build_variant_config["icloud_environment"].nil? ? "Development" : build_variant_config["icloud_environment"])
  upload_itc = (build_variant_config["upload_itc"].nil? ? false : build_variant_config["upload_itc"])
  upload_bitcode = (build_variant_config["upload_bitcode"].nil? ? true : build_variant_config["upload_bitcode"])
  export_method = (build_variant_config["export_method"].nil? ? nil : build_variant_config["export_method"])

  extensions_suffixes = options[:build_variants_config]["extensions_suffixes"]
  scheme = build_variant_config["scheme"]

  # Set the Apple Team ID
  team_id build_variant_config["team_id"]

  if use_sigh
    unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])

    is_adhoc_build = build_variant.include? "adhoc"

    sigh(
      adhoc: is_adhoc_build,
      skip_certificate_verification:true,
      app_identifier: build_variant_config["bundle_identifier"]
      )

    if extensions_suffixes
      for extension_suffix in extensions_suffixes do
        
        begin
          sigh(
            adhoc: is_adhoc_build,
            skip_certificate_verification:true,
            app_identifier: "#{build_variant_config["bundle_identifier"]}.#{extension_suffix}"
            )
        rescue
          UI.important("Seems like #{build_variant_config["bundle_identifier"]}.#{extension_suffix} is not yet included in this project! Skipping sigh!")
          next   
        end

      end
    end
  end

  unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])

  gym(
    clean: should_clean_project,
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    configuration: 'Release',
    codesigning_identity: build_variant_config["code_signing_identity"],
    output_directory: "build",
    archive_path:"build/",
    output_name: scheme,
    include_symbols: true,
    include_bitcode: (upload_itc && upload_bitcode),
    export_method: export_method,
    export_options: { iCloudContainerEnvironment: icloud_environment },
    xcpretty_formatter: "/Library/Ruby/Gems/2.3.0/gems/xcpretty-json-formatter-0.1.0/lib/json_formatter.rb"
    )

end

#############################
### smf_collect_changelog ###
#############################

# options: build_variant (String)

desc "Collect git commit messages and author mail adresses into a changelog and store them as environmental varibles."
private_lane :smf_collect_changelog do |options|

  UI.important("collect commits back to the last tag")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_platform = options[:project_config]["platform"]

  matching_pattern = (options[:tag_prefix].nil? ? "#{build_variant}" : options[:tag_prefix])

  NO_GIT_TAG_FAILURE = "NO_GIT_TAG_FAILURE"

  # Get last tag for the current branch
  last_tag = sh("git describe --tags --match \"*#{matching_pattern}*\" --abbrev=0 HEAD --first-parent || echo #{NO_GIT_TAG_FAILURE}").to_s

  # Use the initial commit if there is no matching tag yet
  if last_tag.include? NO_GIT_TAG_FAILURE
    last_tag = sh("git rev-list --max-parents=0 HEAD").to_s
  end

  last_tag = last_tag.strip

  if ["patch", "minor", "major", "current"].any? { |item| build_variant.downcase.include?(item) }
    ENV["SMF_CHANGELOG"] =  changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '- (%an) %s')
    ENV["SMF_CHANGELOG_EMAILS"] = changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '%ae')
  else
    ENV["SMF_CHANGELOG"] =  changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '- (%an) %s')
    ENV["SMF_CHANGELOG_EMAILS"] = changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '%ae')
  end

  if (!project_platform.nil?) && (project_platform.eql? "mac")

   File.open("changelog.properties", 'w') { |file| file.write("SMF_CHANGELOG='#{ENV["SMF_CHANGELOG"]}'") }
   File.open("emails.properties", 'w') { |file| file.write("SMF_CHANGELOG_EMAILS='#{ENV["SMF_CHANGELOG_EMAILS"]}'") }

  end

end

#############################
#####   smf_check_tag   #####
#############################

# options: build_variant (String)

desc "Check if the tag exist after incrementation of the build number"
private_lane :smf_check_tag do |options|

  UI.important("check if the Incremented Tag exist")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_name = options[:project_config]["project_name"]

  tag_prefix = (options[:tag_prefix].nil? ? "build/#{build_variant}/" : options[:tag_prefix])
  tag_suffix = (options[:tag_suffix].nil? ? "" : options[:tag_suffix])

  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  # Use the incremented build number only if it should be incremented. Also pass the former default prefix.
  tag_prefixes = [tag_prefix, "build/#{build_variant}_b"]
  if smf_should_build_number_be_incremented(tag_prefixes)
    version = smf_get_incremented_build_number(version)
  end

  # Check if the tag already exists. Check also for the former default tag prefix
  if git_tag_exists(tag: tag_prefix+version.to_s+tag_suffix) or git_tag_exists(tag: "build/#{build_variant}_b"+version.to_s+tag_suffix)
    raise "Git tag already existed".red
  end

end


#######################
### smf_add_git_tag ###
#######################

# options: project_config (Hash), tag_prefix (String), tag_suffix (String) [optional], branch (String) [optional]

desc "Tag the current git commit."
private_lane :smf_add_git_tag do |options|

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  tag_prefix = (options[:tag_prefix].nil? ? "" : options[:tag_prefix])
  tag_suffix = (options[:tag_suffix].nil? ? "" : options[:tag_suffix])
  branch = options[:branch]

  UI.important("Tag the current commit")
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  version = version.to_s

  # Tag the current commit
  tag = tag_prefix+version+tag_suffix
  if git_tag_exists(tag: tag_prefix+version+tag_suffix)
    UI.message("Git tag already existed")
  else
    add_git_tag(
      tag: tag
      )
  end

  # Return the tag
  tag
end

##############################
### smf_perform_unit_tests ###
##############################

# options: project_config (Hash), build_variant_config (Hash)

desc "Performs the unit tests of a project."
private_lane :smf_perform_unit_tests do |options|

  UI.important("Perform the unit tests")

  # Read options parameter
  project_config = options[:project_config]
  build_variant_config = options[:build_variant_config]

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config["unit_test_schme"].nil? ? build_variant_config["scheme"] : build_variant_config["unit_test_schme"])

  scan(
    workspace: "#{project_config["project_name"]}.xcworkspace",
    scheme: scheme,
    clean: false,
    output_types: "html,junit,json-compilation-database",
    output_files: "report.xml,report.junit,report.json"
    )

end

#######################################
### smf_disable_former_hockey_entry ###
#######################################

# options: build_variant_config (Hash), build_variant (String)

desc "Disable the downlaod of the former app version on HockeyApp - does not apply for Alpha builds."
private_lane :smf_disable_former_hockey_entry do |options|

  # Read options parameter
  build_variant = options[:build_variant].downcase
  build_variant_config = options[:build_variant_config]
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  # Disable the download of the former non Alpha app on Hockey App
  if (!build_variants_contains_whitelist) || (build_variants_contains_whitelist.any? { |whitelist_item| build_variant.include?(whitelist_item) })
    if (Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] > 1)
      previous_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] - 1

      UI.important("HERE IS THE ID OF THE Current VERSION #{Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']}")
      UI.important("HERE IS THE ID OF THE Previous VERSION #{previous_version_id}")

      disable_hockey_download(
        api_token: ENV["HOCKEYAPP_API_TOKEN"],
        public_identifier: build_variant_config["hockeyapp_id"],
        version_id: "#{previous_version_id}"
        )
    end
  end
end

########################################
### smf_delete_uploaded_hockey_entry ###
########################################

# options: apps_hockey_id (String)

desc "Deletes the uploaded app version on Hockey. It should be used to clean up after a error response from hockey app."
private_lane :smf_delete_uploaded_hockey_entry do |options|

  # Read options parameter
  apps_hockey_id = options[:apps_hockey_id]

  # Disable the download of the former non Alpha app on Hockey App
  app_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']
  if (app_version_id > 1)
    UI.important("Will remove the app version with id: #{app_version_id}")

    delete_app_version_on_hockey(
      api_token: ENV["HOCKEYAPP_API_TOKEN"],
      public_identifier: apps_hockey_id,
      version_id: "#{app_version_id}"
     )
  else
    UI.message("No HOCKEY_BUILD_INFORMATION was found, so there is nothing to delete.")
    end
end

##############################
### smf_generate_meta_json ###
##############################

# options: branch (String), build_variant (String) and build_variants_contains_whitelist (String) [optional]

desc "Create the metaJSON files - applys only for Alpha builds."
private_lane :smf_generate_meta_json do |options|

  # Read options parameter
  branch = options[:branch]
  build_variant = options[:build_variant].downcase
  project_name = options[:project_config]["project_name"]
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  if (build_variants_contains_whitelist.nil?) || (build_variants_contains_whitelist.any? { |whitelist_item| build_variant.include?(whitelist_item) })
    desc "Create the meta JSON files"
    # Fetch the MetaJSON scripts repo
    sh "git clone git@github.com:smartmobilefactory/SMF-iOS-MetaJSON.git"
    # Create and commit the MetaJSON files
    sh "cd .. && fastlane/SMF-iOS-MetaJSON/scripts/create-meta-jsons.sh \"#{project_name}\" \"#{branch}\" || true"
    # Remove the MetaJSON scripts repo
    sh "rm -rf SMF-iOS-MetaJSON"
  end

end

############################
### smf_commit_meta_json ###
############################

# options: branch (String)

desc "Commit the metaJSON files - applys only for Alpha builds."
private_lane :smf_commit_meta_json do |options|
  branch = options[:branch]

  workspace = ENV["WORKSPACE"]

  desc "Commit the meta JSON files"

  # Copy additional meta files to MetaJSON directory
  sh "if [ -d #{workspace}/#{METAJSON_TEMP_FOLDERNAME} ]; then cp -R #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/. #{workspace}/.MetaJSON/; fi"

  # Delete the temporary MetaJSON folder
  sh "if [ -d #{workspace}/#{METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{METAJSON_TEMP_FOLDERNAME}; fi"

  # Reset git, add MetaJSON directory and commit
  sh "cd \"#{workspace}\"; git reset && git add \".MetaJSON\" && git commit -m \"Update MetaJSONs\""
end

###############################
### smf_commit_generated_code ###
###############################

# options: branch (String)

desc "Commit generated code"
private_lane :smf_commit_generated_code do |options|

  UI.important("Commit and push generated code")
    # Read options parameter
    branch = options[:branch]

    # Reset the currently staged files first to make sure only the generated code will be commited
    sh "git reset"
    sh "git add ../Generated/ || true"
    sh "git commit -m \"Update generated code\" || true"

end


###############################
### smf_commit_build_number ###
###############################

# options: project_config (Hash), branch (String)

desc "Commit the build number."
private_lane :smf_commit_build_number do |options|

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  branch = options[:branch]

  UI.important("Increment Build Version Code")
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  puts version

  commit_version_bump(
    xcodeproj: "#{project_name}.xcodeproj",
    message: "#{smf_increment_build_number_prefix_string}#{version}",
    force: true
    )

end

##############################
### smf_notify_via_hipchat ###
##############################

# options: title (String), message (String), additional_html_entries (Array of Strings), hipchat_channel (String), success (String)

desc "Post to a HipChat room if the build was successful"
private_lane :smf_notify_via_hipchat do |options|

  # Read options parameter
  title = options[:title]
  message = options[:message]
  project_name = options[:project_name]
  additional_html_entries = options[:additional_html_entries]
  hipchat_channel = options[:hipchat_channel]
  success = options[:success]

  hipchat_channel = URI.unescape(hipchat_channel) == hipchat_channel ? URI.escape(hipchat_channel) : hipchat_channel

  message = "<table><tr><td><strong>#{title}</strong></td></tr><tr></tr><tr><td><pre>#{message[0..8000]}#{' ...' if message.length > 8000}</pre></td></tr></table>"

  if additional_html_entries
    for additional_html_entry in additional_html_entries do
      message.sub('</table>', "<tr><td>#{additional_html_entry}</td></tr></table>")
    end
  end

  hipchat(
    message: message,
    channel: hipchat_channel,
    success: success,
    api_token: ENV["HIPCHAT_API_TOKEN"],
    notify_room: true,
    version: "2",
    message_format: "html",
    include_html_header: false,
    from: "#{project_name} iOS CI"
    )

end


###########################
### smf_notify_via_mail ###
###########################

# options: release_title (String), authors_emails (String), success (Boolean), exception_message (String) [Optional], app_link (String)

desc "Send emails to all collaborators who worked on the project since the last build to inform about successfully or failing build jobs."
private_lane :smf_notify_via_mail do |options|

  # Read options parameter
  title = options[:title]
  message = options[:message]
  success = options[:success]
  exception_message = options[:exception_message]
  app_link = (options[:app_link].nil? ? "" : options[:app_link])

  authors_emails = []
  if ENV["SMF_CHANGELOG_EMAILS"]
    authors_emails = ENV["SMF_CHANGELOG_EMAILS"].split(" ").uniq.delete_if{|e| e == "git-checkout@smartmobilefactory.com"}
    # Only allow internal mail adresses
    authors_emails.delete_if do |e_mail|
      if e_mail.end_with? "@smfhq.com" or e_mail.end_with? "@smartmobilefactory.com"
        false
      else
        UI.message("Exclude #{e_mail} as it's not an SMF mail adress")
        true
      end
    end
  end

  case success
  when false
    message << "<p style='
    border: 1px solid #D8D8D8;
    padding: 5px;
    border-radius: 5px;
    font-family: Arial;
    font-size: 11px;
    text-transform: uppercase;
    background-color: rgb(255, 249, 242);
    color: rgb(211, 0, 0);
    text-align: center;' >#{exception_message} <p>"
  end

  authors_emails.each do |receiver|
    mailgun(
      subject: title,
      postmaster:"postmaster@mailgun.smfhq.com",
      apikey: ENV["MAILGUN_KEY"],
      to: receiver,
      success: success,
      message: message,
      app_link: app_link,
      ci_build_link: ENV["BUILD_URL"],
      template_path: "/Users/smf/jenkins/template_mail_ios.erb"
      )
  end

end


################################
### smf_upload_ipa_to_hockey ###
################################

# options: project_config (Hash)

desc "Clean, build and release the app on HockeyApp"
private_lane :smf_upload_ipa_to_hockey do |options|

  UI.important("Upload a new build to HockeyApp")

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  hockey_app_id = options[:build_variant_config]["hockeyapp_id"]
  bundle_identifier = options[:build_variant_config]["bundle_identifier"]
  version_number = get_version_number(xcodeproj: "#{project_name}.xcodeproj")
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  scheme = options[:build_variant_config]["scheme"]

  release_notes = message = "#{ENV["SMF_CHANGELOG"][0..4995]}#{'\\n...' if ENV["SMF_CHANGELOG"].length > 4995}"

  #DSYM Path
  path = Pathname.getwd.dirname.to_s + "/#{bundle_identifier}-#{version_number}-#{build_number}.dSYM.zip"
  
  NO_APP_FAILURE = "NO_APP_FAILURE"
  escaped_filename = scheme.gsub(" ", "\ ")
  sh "cd ../build; zip -r9 \"#{escaped_filename}.app.zip\" \"#{escaped_filename}.app\" || echo #{NO_APP_FAILURE}"
  app_path = Pathname.getwd.dirname.to_s + "/build/#{escaped_filename}.app.zip"
  puts app_path


  hockey(
    api_token: ENV["HOCKEYAPP_API_TOKEN"],
    ipa: File.exist?(app_path) ? app_path : lane_context[SharedValues::IPA_OUTPUT_PATH], 
    notify: "0",
    notes: release_notes,
    public_identifier: hockey_app_id,
    dsym: File.exist?(path) ? path : nil  
  )

end

####################################
### smf_upload_ipa_to_testflight ###
####################################

# options: build_variant_config (Hash)

desc "upload the app on Testflight"
private_lane :smf_upload_ipa_to_testflight do |options|

  UI.important("Upload a new build to Testflight")

  skip_waiting = should_skip_waiting_after_itc_upload(options[:build_variant_config])

  if options[:build_variant_config].key? "itc_apple_id"
    username = options[:build_variant_config]["itc_apple_id"]
  else
    username = nil
  end

  pilot(
    username: username,
    skip_waiting_for_build_processing: skip_waiting,
    changelog: ""
    )

end

desc "Clean, build and release the app on HockeyApp"
private_lane :smf_download_dsym_from_testflight do |options|

  UI.important("Download dsym from Testflight")

  project_name = options[:project_config]["project_name"]
  bundle_identifier = options[:build_variant_config]["bundle_identifier"]
  username = options[:build_variant_config]["itc_apple_id"]

  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  build_number = build_number.to_s

  download_dsyms(username: username, app_identifier: bundle_identifier,  build_number: build_number)

end


##################################
### smf_increment_build_number ###
##################################

desc "increment build number"
private_lane :smf_increment_build_number do |options|

  UI.important("increment build number")

  project_name = options[:project_config]["project_name"]
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  increment_build_number(build_number: smf_get_incremented_build_number(version))

end

################################
###   smf_itunes_precheck    ###
################################

private_lane :smf_itunes_precheck do |options|

  project_config = options[:project_config]
  project_name = project_config["project_name"]
  hipchat_channel = project_config["hipchat_channel"]
  build_variant_config = options[:build_variant_config]
  app_identifier = build_variant_config["bundle_identifier"]
  username = build_variant_config["itc_apple_id"]

  begin
   precheck(username: username.nil? ? nil : username , app_identifier: app_identifier)

 rescue => e 
  UI.error "Error while checking Metadata ...:
  #{e.message}"
  subject = "Found Metadata issues for #{project_name}"
  message = "<strong> Info: iTunes Connect Precheck found issues for #{build_variant_config["scheme"]}</strong> 😢"
  message << "<p style='
  border: 1px solid #D8D8D8;
  padding: 5px;
  border-radius: 5px;
  font-family: Arial;
  font-size: 11px;
  text-transform: uppercase;
  background-color: rgb(255, 249, 242);
  color: rgb(211, 0, 0);
  text-align: center;' >#{e.message[0..8000]}#{'\\n...' if e.message.length > 8000}<p>
  <strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a>"

  mailgun(
    subject: subject,
    postmaster:"postmaster@mailgun.smfhq.com",
    apikey: ENV["MAILGUN_KEY"],
    to: "development@smfhq.com",
    success: false,
    message: message,
    app_link: "",
    ci_build_link: ENV["BUILD_URL"],
    template_path: "/Users/smf/jenkins/template_mail_ios_precheck.erb"
    )

  if hipchat_channel
    hipchat_channel = URI.escape(hipchat_channel)

    hipchat(
      message: message,
      channel: hipchat_channel,
      success: false,
      api_token: ENV["HIPCHAT_API_TOKEN"],
      notify_room: true,
      version: "2",
      message_format: "html",
      include_html_header: false,
      from: "#{project_name} iOS CI"
      )
  end
 end
end

##########################################################
###   check build number whether it's a int or float   ###
##########################################################

def smf_get_incremented_build_number(version)

  if version.to_s.include? "."
    
   parts = version.to_s.split(".")
   count = parts.count

   incremented_version = parts[count - 1].to_i + 1

   version_string = ""

    for i in 0..count-2
     version_string += parts[i].to_s + "."
    end

   version_string += incremented_version.to_s

  else 
   version_string = version.to_i + 1

  end    

 return version_string.to_s

end

#################################################
###   smf_should_build_number_be_incremented  ###
#################################################

def smf_should_build_number_be_incremented(tag_prefixes = nil)

    if not ENV["SHOULD_INCREMENT_BUILD_NUMBER"].nil?
      UI.message("The SHOULD_INCREMENT_BUILD_NUMBER ENV was already set. Reusing #{ENV["SHOULD_INCREMENT_BUILD_NUMBER"]}")
      return ENV["SHOULD_INCREMENT_BUILD_NUMBER"] == "true"
    end

    # Check if the former commit was a build of the same build variant 
    unless tag_prefixes.nil?
      last_commit_tags_string = sh "git tag -l --points-at HEAD"
      for tag_prefix in tag_prefixes do
        if last_commit_tags_string.include? tag_prefix
          UI.message("Increment the build number as the former commit is a build of the same build variant. We have to increase it to avoid duplicate build numbers")
          ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "true"
          return ENV["SHOULD_INCREMENT_BUILD_NUMBER"]
        end
      end
    end

    last_commit = last_git_commit
    message = last_commit[:message]
    author = last_commit[:author]

    UI.message("The last commit was \"#{message}\" from #{author}")

    if message.include? smf_increment_build_number_prefix_string and author == "SMFHUDSONCHECKOUT"
      UI.message("Don't increment the build number as the last commit was a build number incrementation from Jenkins")
      ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "false"
    else
      UI.message("Increment the build number as the last commit wasn't a build number incrementation from Jenkins")
      ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "true"
    end

  return ENV["SHOULD_INCREMENT_BUILD_NUMBER"] == "true"

end

###################################
### smf_send_ios_hockey_app_apn ###
###################################

# options: hockeyapp_id (String)

desc "Send a Push Notification through OneSignal to the SMF HockeyApp"
private_lane :smf_send_ios_hockey_app_apn do |options|

  UI.important("Send Push Notification")

  # Read options parameter
  hockey_app_id = options[:hockeyapp_id]

  # Create valid URI
  uri = URI.parse('https://onesignal.com/api/v1/notifications')

  # Authentification Header
  header = {
    'Content-Type' => 'application/json; charset=utf-8',
    'Authorization' => 'Basic OGMyMjA2ZGUtNTFjOS00NGQzLWE5YmEtOWM1YjMxZTE1YWZh' # OneSignal User AuthKey REST API
  }

  # Notification Payload
  payload = {
    'app_ids' => ['f809f1b9-e7ae-4d64-946b-66db65daf360', '5cd4e388-10ad-4bd7-b0a0-acd8a25420a7'], # OneSignal App IDs (ALPHA & BETA)
    'content_available' => 'true',
    'mutable_content' => 'true',
    'isIos' => 'true',
    'ios_category' => 'com.usernotifications.app_update', # Remote Notification Category.
    'filters' => [
      {
        'field' => 'tag',
        'relation' => '=',
        'key' => hockey_app_id,
        'value' => 'com.usernotifications.app_update'
      }
    ],
    'data' => {
      'HockeyAppId' => hockey_app_id
    }
  }

  # Create and send a POST request
  https = Net::HTTP.new(uri.host,uri.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(uri.path, header)
  request.body = payload.to_json
  https.request(request)

end

###########################################
### smf_send_message_to_hipchat_ci_room ###
###########################################

# options: project_name (Hash), message (String)

desc "Send a message to the CI room in HipChat"
private_lane :smf_send_message_to_hipchat_ci_room do |options|

  UI.important("Send a message to the CI room in HipChat")

  # Read options parameter
  project_name = options[:project_name]
  message = options[:message]
  success = options[:success]

  hipchat(
    message: message,
    channel: "CI",
    success: success,
    api_token: ENV["HIPCHAT_API_TOKEN"],
    notify_room: true,
    version: "2",
    message_format: "html",
    include_html_header: false,
    from: "#{project_name} iOS CI"
  )

end

##################
### error lane ###
##################

error do |lane, exception|
  if ENV["SMF_SHOULD_SEND_DEPLOY_FAILURE_NOTIFICATIONS"] == "true"
    project_config = build_variants_config["project"]

    # Create the release title with the framework config if it's a framework
    framework_identifier = ENV["SMF_FRAMEWORK_IDENTIFIER"]
    release_title = nil
    if framework_identifier
      release_title = smf_default_pod_notification_release_title(project_config["project_name"], build_variants_config["framework"][framework_identifier])
    end

    smf_handle_exception(
      build_variant: ENV["SMF_BUILD_VARIANT"],
      project_config: project_config,
      release_title: release_title,
      exception: exception,
      )
  end
end

#################################
### smf_create_github_release ###
#################################

# options: release_name (String), tag (String), branch (String)

private_lane :smf_create_github_release do |options|

  release_name = options[:release_name]
  tag = options[:tag]
  branch = options[:branch]
  ignore_existing_release = (options[:ignore_existing_release].nil? ? false : options[:ignore_existing_release])

  git_remote_origin_url = sh "git config --get remote.origin.url"
  github_url_match = git_remote_origin_url.match(/.*github.com:(.*)\.git/)
  # Search fot the https url if the ssh url couldn't be found
  if github_url_match.nil?
    github_url_match = git_remote_origin_url.match(/.*github.com\/(.*)\.git/)
  end

  if github_url_match.nil? or github_url_match.length < 2
    UI.message("The remote orgin doesn't seem to be GitHub. The GitHub Release won't be created.")
    return
  end

  repository_path = github_url_match[1]

  UI.message("Found #{repository_path} as GitHub repo name")

  if get_github_release(url: repository_path, version: tag) and ignore_existing_release == false
    raise "Git release already existed".red
  end

  UI.message("Found #{repository_path} as GitHub repo name")

  # Create the GitHub release
  set_github_release(
    repository_name: repository_path,
    api_token: ENV['GITHUB_TOKEN'],
    name: release_name.to_s,
    tag_name: tag,
    description: ENV["SMF_CHANGELOG"],
    commitish: branch
  )
end

##############
### HELPER ###
##############

def smf_default_app_notification_release_title(project_name, build_variant)

  # Create the branch name string
  branch = git_branch
  branch_suffix = ""
  if branch.nil? == false and branch.length > 0
    branch_suffix = ", branch: #{branch}"
    branch_suffix.sub!("origin/", "")
  end

  return "#{project_name} #{build_variant.upcase} (build: #{get_build_number}#{branch_suffix})"
end

def smf_default_pod_notification_release_title(project_name, framework_config)

  current_version = read_podspec(path: framework_config["podsepc_path"])["version"]

  # Create the branch name string
  branch = git_branch
  branch_suffix = ""
  if branch.nil? == false and branch.length > 0
    branch_suffix = " (branch: #{branch})"
    branch_suffix.sub!("origin/", "")
  end

  return "#{project_name} #{current_version}#{branch_suffix}"
end

def smf_increment_build_number_prefix_string
  return "Increment build number to "
end

def smf_git_pull
  branch = git_branch
  branch_name = "#{branch}"
  branch_name.sub!("origin/", "")
  sh "git pull origin #{branch_name}"
end

def is_bitcode_enabled(project_name, scheme)
  if not sh "pgrep Xcode"
    # Xcode isn't running, open it to avoid a hanging xcrun
    
    # Wait 10 seconds to let Xcode start properly
    sleep 10
  end

  enable_bitcode_string = sh "cd .. && xcrun xcodebuild -showBuildSettings -workspace\ \"#{project_name}.xcworkspace\" -scheme \"#{scheme}\" \| grep \"ENABLE_BITCODE = \" \| grep -o \"\\(YES\\|NO\\)\""
  return ((enable_bitcode_string.include? "NO") == false)
end

def should_skip_waiting_after_itc_upload(build_variant_config)
  return (build_variant_config["itc_skip_waiting"].nil? ? false : ["itc_skip_waiting"])
end

def smf_run_danger(build_variant, build_type, fastlane_commons_branch)
  fastlane_commons_branch = (fastlane_commons_branch.nil? ? "danger" : fastlane_commons_branch)

  if File.file?('Dangerfile')
    sh "git clone -b \"" + fastlane_commons_branch + "\" git@github.com:smartmobilefactory/SMF-iOS-Fastlane-Commons.git commons"
    sh "export DANGER_GITHUB_API_TOKEN=$GITHUB_TOKEN; export BUILD_VARIANT=\"#{build_variant}\"; export BUILD_TYPE=\"#{build_type}\"; export FASTLANE_COMMONS_BRANCH=\"#{fastlane_commons_branch}\"; cd ..; /usr/local/bin/danger --dangerfile=fastlane/Dangerfile"
  else
    UI.important("There was no Dangerfile in ./fastlane, not running danger at all!")
  end
end

def smf_run_linter
  workspace = ENV["WORKSPACE"]

  system "cd " + workspace + "; Pods/SwiftLint/swiftlint lint --reporter json > build/reports/swiftlint.json"

  # Removes the workspace part
  workspace_regexp = (workspace + '/').gsub(/\//, '\\\\\\\\\/')
  system "sed -i -e 's/#{workspace_regexp}//g' " + workspace + "/build/reports/swiftlint.json"

  # Turns \/ int /
  a = '\\\\\/'
  b = '\/'
  system "sed -i -e 's/#{a}/#{b}/g' " + workspace + "/#{METAJSON_TEMP_FOLDERNAME}/swiftlint.json"

end

def smf_run_slather(scheme, projectName)
  workspace = ENV["WORKSPACE"]

  system "cd " + workspace + "; slather coverage -v --html --scheme " + scheme + " --workspace " + projectName + ".xcworkspace " + projectName + ".xcodeproj"
  system "cd " + workspace + "; slather coverage -v --json --scheme " + scheme + " --workspace " + projectName + ".xcworkspace " + projectName + ".xcodeproj"

  if File.file?(workspace + '/report.json')
    smf_create_json_slather_summary(workspace + '/report.json')
  end

  sh "if [ -f #{workspace}/build/reports/test_coverage.json ]; then cp #{workspace}/build/reports/test_coverage.json #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/test_coverage.json; fi"
  sh "if [ -d #{workspace}/html ]; then cp -r #{workspace}/html #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
  # Compress the Slather HTML folder and delete it afterwards
  sh "if [ -d #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report ]; then zip #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report.zip #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
  sh "if [ -f #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report.zip ]; then rm -rf #{workspace}/#{METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
end

def smf_create_json_slather_summary(report_file)
  if File.file?(report_file)
    files = JSON.parse(File.read(report_file))

    workspace = ENV["WORKSPACE"]

    summary = { }
    summary["files"] = [ ]

    total_covered_loc = 0
    total_relevant_loc = 0
    filenum = 0

    for file in files
        filenum += 1

        covered_loc = 0
        relevant_loc = 0

        for line in file["coverage"]
          if line.to_i > 0
            covered_loc += 1
            relevant_loc += 1
          elsif !line.nil? && line.to_i == 0
            relevant_loc += 1
          end
        end

        percent = (covered_loc.to_f / relevant_loc.to_f) * 100
        #puts "Covered lines in " + file["file"] + ": " + covered_loc.to_s + " of " + relevant_loc.to_s  + " relevant lines of code (" + percent.round(3).to_s + "%)"

        entity = { }
        entity["file"] = file["file"]
        entity["coverage"] = percent
        summary["files"] << entity

        total_covered_loc += covered_loc
        total_relevant_loc += relevant_loc
    end

    percent = (total_covered_loc.to_f / total_relevant_loc.to_f) * 100
    #puts "Tested " + files.length.to_s + " files. Total coverage: " + percent.to_s  + "%"

    summary["total_coverage"] = percent

    File.open(workspace + "/build/reports/test_coverage.json", "w") do |f|
      f.write(summary.to_json)
    end
  else
    puts "Sorry, could not find file: " + report_file
  end
end