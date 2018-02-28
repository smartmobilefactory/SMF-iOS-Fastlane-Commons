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
  build_variant_config = build_variants_config["build_variants"][build_variant]
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
    sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}; fi"
    sh "mkdir #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}"
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
    sh "if [ -f #{workspace}/build/reports/errors.json ]; then cp #{workspace}/build/reports/errors.json #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/xcodebuild.json; fi"
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
  build_variant_config = build_variants_config["build_variants"][build_variant]
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

  smf_run_danger(options[:build_variant])
end

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
