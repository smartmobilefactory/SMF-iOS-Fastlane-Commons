

######################
### smf_deploy_app ###
######################

desc "Builds all current build variants including build number incrementation, MetaJSON etc. and uploads the version to Hockey."
private_lane :smf_deploy_app do |options|

# Use the current build variant if no array of build variants to build is provided
  if @smf_build_variants_array.nil? || @smf_build_variants_array.length == 0
    smf_set_build_variants_array([@smf_build_variant])
  else
    UI.important("Multiple build variants are declared. Deploying apps for #{@smf_build_variants_array}")
  end

  bulk_deploy_params = @smf_build_variants_array.length > 1 ? {index: 0, count: @smf_build_variants_array.length} : nil
  for build_variant in @smf_build_variants_array

    smf_set_build_variant(build_variant, false)

    begin
      smf_deploy_build_variant(
        bulk_deploy_params: bulk_deploy_params
      )
    rescue => exception
      
      # Revert build number if needed
      smf_decrement_build_number

      UI.important("Warning: Building variant #{build_variant} failed! Exception #{exception}")
    end

    if bulk_deploy_params != nil
      bulk_deploy_params[:index] += 1
    end
  end
end

######################
### smf_deploy_app ###
######################

desc "Builds the current build variant including build number incrementation, MetaJSON etc. and uploads the version to Hockey."
private_lane :smf_deploy_build_variant do |options|

  UI.important("Deploying a new app version of \"#{@smf_build_variant}\"")

  # Parameters
  bulk_deploy_params = options[:bulk_deploy_params]

  # Cleanup

  # Reset the HockeyApp ID to avoid that a successful upload is removed if a following build variant is failing in the same build job
  ENV[$SMF_APP_HOCKEY_ID_ENV_KEY] = nil

  # Reset the build incrementation flag to support build jobs which build multiple build variants in a row
  ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] = nil

  # Reset that the unit tests were run to avoid wrong information in Danger
  ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY] = "false"

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  project_name = @smf_fastlane_config[:project][:project_name]

  generateMetaJSON = build_variant_config[:generateMetaJSON]
  use_hockey = (build_variant_config[:use_hockey].nil? ? true : build_variant_config[:use_hockey])
  # The default value of push_generated_code depends on whether Strings are synced with PhraseApp. If PhraseApp should be synced, the default is true 
  push_generated_code = (build_variant_config[:push_generated_code].nil? ? (build_variant_config[:phrase_app_script] != nil) : build_variant_config[:push_generated_code])

  # Cleanup the temporary MetaJSON folder in case it exists from a former build
  if generateMetaJSON != false
    workspace = smf_workspace_dir
    sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}; fi"
    sh "mkdir #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}"
  end

  smf_install_pods_if_project_contains_podfile
  
  # Increment the build number only if it should
  if smf_should_build_number_be_incremented
    smf_store_current_build_number
    smf_increment_build_number
    smf_set_should_revert_build_number(true)
  end

  # Check if the New Tag already exists
  smf_verify_git_tag_is_not_already_existing

  # Check for commons ITC Upload errors if needed
  if build_variant_config[:upload_itc] == true
    smf_verify_common_itc_upload_errors
  end

  # Sync Phrase App
  smf_sync_strings_with_phrase_app

  # Build and archive the IPA
  smf_archive_ipa(
    bulk_deploy_params: bulk_deploy_params
    )

  # Commit generated code. There can be changes eg. from PhraseApp + R.swift
  if push_generated_code
    smf_commit_generated_code
  end

  # Copy the Xcode warnings and errors report to keep the files available for MetaJSON
  if generateMetaJSON != false
    workspace = smf_workspace_dir
    sh "if [ -f #{workspace}/build/reports/errors.json ]; then cp #{workspace}/build/reports/errors.json #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/xcodebuild.json; fi"
  end

  # Update the MetaJSONS if wanted
  if generateMetaJSON != false
    begin
      # Run unit tests and then run linter to generate JSONs
      if smf_can_unit_tests_be_performed
        begin
          smf_perform_unit_tests
        rescue
          UI.important("Failed to perform the unit tests")
        end

        smf_run_slather
      end

      smf_run_linter

      #smf_generate_meta_json
      
      #smf_commit_meta_json
    rescue => exception
      UI.important("Warning: MetaJSON couldn't be created")

      smf_send_hipchat_message(
        title: "Failed to create MetaJSON for #{smf_default_notification_release_title} 😢",
        type: "warning",
        exception: exception,
        hipchat_channel: "CI"
      )
    end
  end

  # Commit the build number if it was incremented
  if smf_should_build_number_be_incremented
    smf_commit_build_number
    smf_set_should_revert_build_number(false)
  end

  # Build a Simulator build if wanted
  if build_variant_config[:attach_build_outputs_to_github] == true
    smf_build_simulator_app
  end

  # Collect the changelog 
  smf_collect_changelog

  if use_hockey
    # Store the HockeyApp ID to let the handle exception lane know what hockeyapp entry should be deleted. This value is reset during bulk builds to avoid the deletion of a former succesful build.
    ENV[$SMF_APP_HOCKEY_ID_ENV_KEY] = build_variant_config[:hockeyapp_id]
    
    # Upload the IPA to HockeyApp
    smf_upload_ipa_to_hockey
    
    # Disable the former HockeyApp entry
    smf_disable_former_hockey_entry(
      build_variants_contains_whitelist: ["beta"]
      )

    # Inform the SMF HockeyApp about the new app version
    begin
      smf_send_ios_hockey_app_apn
    rescue => exception
      UI.important("Warning: The APN to the SMF HockeyApp couldn't be sent!")

      smf_send_hipchat_message(
        title: "Failed to send APN to SMF HockeyApp for #{smf_default_notification_release_title} 😢",
        type: "warning",
        exception: exception,
        hipchat_channel: "CI"
      )
    end
  end

  # TODO_DMG_CREATION
  # Create appcast
  sparkle_code_signing_identity = build_variant_config["sparkle.signing_identity".to_sym]
  sparkle_private_key = ENV["CUSTOM_CERTIFICATES"] + "/" + sparkle_code_signing_identity
  update_dir = "#{workspace}/build/"
  sh "#{@fastlane_commons_dir_path}/tools/generate_appcast -f #{sparkle_private_key} #{update_dir}"

  # Upload appcast

  tag = smf_add_git_tag

  smf_git_pull

  push_to_git_remote(
    remote: 'origin',
    local_branch: @smf_git_branch,
    remote_branch: @smf_git_branch,
    force: false,
    tags: true
  )

  # Create the GitHub release
  version = smf_get_version_number
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  smf_create_github_release(
    release_name: "#{@smf_build_variant.upcase} #{version} (#{build_number})",
    tag: tag
  )

  smf_send_deploy_success_notifications

  # Upload Ipa to Testflight and Download the generated DSYM
  # The testflight upload should happen as last step as the upload often shows an error although the IPA was successfully uploaded. We still want the tag, HockeyApp upload etc in this case.
  if build_variant_config[:upload_itc] == true

    if build_variant_config.key?(:itc_team_id)
      ENV["FASTLANE_ITC_TEAM_ID"] = build_variant_config[:itc_team_id]
    end

    smf_itunes_precheck

    notification_title = nil
    notification_message = nil
    notification_type = "error"
    exception = nil

    begin
      smf_upload_ipa_to_testflight

      skip_waiting = should_skip_waiting_after_itc_upload

      # Construct the HipChat notification content
      notification_title = "Uploaded #{smf_default_notification_release_title} to iTunes Connect 🎉"
      if skip_waiting
        notification_message = "The build job didn't wait until iTunes Connect processed the build. Errors might still occur! ⚠️"
        notification_type = "message"
      else
        notification_message = "The IPA was processed by Apple without any errors 👍"
        notification_type = "success"
      end

      # Download the dsym if the waiting of the processing wasn't skipped
      if skip_waiting == false
        begin
          smf_download_dsym_from_testflight
        rescue => e
          UI.important("Warning: The dsym couldn't be downloaded. The build job will continue anyway.")

          notification << " but the dsym download failed."
        end
      end

      UI.success("The upload to iTunes Connect succeeded!")

    rescue => e
      # Construct the HipChat notification content
      notification_title = "Failed to upload #{smf_default_notification_release_title} to iTunes Connect 😢"
      notification_message = "As iTunes Connect often response with an error altough the IPA was successfully uploaded, you may want to check iTunes Connect to know if the upload worked or not."
      notification_type = "error"

      UI.important("Warning: The upload to iTunes Connect failed!")

      exception = e
    end

    smf_send_hipchat_message(
        title: notification_title,
        message: notification_message,
        type: notification_type,
        exception: exception,
        hipchat_channel: @smf_fastlane_config[:project][:hipchat_channel]
      )
  end

end
