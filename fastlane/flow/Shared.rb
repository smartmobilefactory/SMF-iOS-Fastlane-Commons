####################
### smf_check_pr ###
####################

private_lane :smf_check_pr do |options|

  # If we're on a non-pipeline job we should skip this step. Remove this after all jobs are migrated to pipeline.
  if ENV["CHANGE_BRANCH"] != nil
    smf_update_generated_setup_file
  end

  smf_install_pods_if_project_contains_podfile

  # Use the current build variant if no array of build variants to check is provided
  if @smf_build_variants_array.nil? || @smf_build_variants_array.length == 0
    smf_set_build_variants_array([@smf_build_variant])
  else
    UI.important("Multiple build variants are declared. Checking the PR for #{@smf_build_variants_array}")
  end

  bulk_deploy_params = @smf_build_variants_array.length > 1 ? {index: 0, count: @smf_build_variants_array.length} : nil
  for build_variant in @smf_build_variants_array

    UI.important("Starting PR check for build variant \"#{build_variant}\"")

    # Cleanup
    ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY] = "false"

    smf_set_build_variant(build_variant, false)

    # Archive the IPA if the build variant didn't opt-out
    build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
    should_archive_ipa = (build_variant_config["pr.archive_ipa".to_sym].nil? ? (smf_is_build_variant_a_pod == false) : build_variant_config["pr.archive_ipa".to_sym])

    generate_temporary_appfile

    if should_archive_ipa
      smf_archive_ipa_if_scheme_is_provided(
        skip_export: true,
        bulk_deploy_params: bulk_deploy_params
        )
    end
    
    should_run_danger = (build_variant_config["pr.run_danger".to_sym].nil? ? true : build_variant_config["pr.run_danger".to_sym])

    # Run the unit tests if the build variant didn't opt-out
    should_perform_unit_test = (build_variant_config["pr.perform_unit_tests".to_sym].nil? ? true : build_variant_config["pr.perform_unit_tests".to_sym])

    begin
      if should_perform_unit_test && smf_can_unit_tests_be_performed
        smf_perform_unit_tests
      end
    rescue => exception

      # Run Danger if the build variant didn't opt-out even if the unit tests failed
      if should_run_danger
        smf_run_danger
      end

      # Raise the exception as the build job should fail if the unit tests fail
      raise exception
    end

    # Run Danger if the build variant didn't opt-out
    if should_run_danger
      smf_run_danger
    end

    if bulk_deploy_params != nil
      bulk_deploy_params[:index] += 1
    end
  end

end

#############################################
### smf_send_deploy_success_notifications ###
#############################################

# options: app_link (String) [optional]

desc "Handle the success of a deploy by sending email to the authors and post to the slack channel"
private_lane :smf_send_deploy_success_notifications do |options|

  # Parameter
  app_link = (options[:app_link].nil? ? Actions.lane_context[Actions::SharedValues::HOCKEY_DOWNLOAD_LINK] : options[:app_link])

  # Variables
  slack_channel = @smf_fastlane_config[:project][:slack_channel]

  if ENV[$SMF_CHANGELOG_ENV_KEY].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog
  end

  title = "Built #{smf_default_notification_release_title} 🎉"

  if slack_channel
    smf_send_chat_message(
      title: title,
      message: ENV[$SMF_CHANGELOG_ENV_KEY],
      type: "success",
      slack_channel: slack_channel
      )
  end
end

############################
### smf_handle_exception ###
############################

# options: message (String) [optional], exception (exception)

desc "Handle the exception by sending email to the authors"
private_lane :smf_handle_exception do |options|

  UI.important("Handling the build job exception")

  # Parameter
  message = options[:message]
  exception = options[:exception]

  # Variables
  slack_channel = @smf_fastlane_config[:project][:slack_channel]

  apps_hockey_id = ENV[$SMF_APP_HOCKEY_ID_ENV_KEY]
  if not apps_hockey_id.nil?
    begin
      smf_delete_uploaded_hockey_entry(
        apps_hockey_id: apps_hockey_id
      )
      UI.important("The app version which was uploaded to HockeyApp was removed as something else in the build job failed!")
    rescue
      UI.message("The app version which was uploaded to HockeyApp wasn't removed. This is fine if it wasn't yet uploaded")
    end
  end

  if ENV[$SMF_CHANGELOG_ENV_KEY].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog
  end

  if smf_is_build_variant_a_decoupled_ui_test == true
    title = "Failed to perform UI-Tests for #{smf_default_notification_release_title} 😢"
  else
    title = "Failed to build #{smf_default_notification_release_title} 😢"
  end

  if slack_channel
    smf_send_chat_message(
      title: title,
      message: message,
      exception: exception,
      type: "error",
      slack_channel: slack_channel
      )
  end
end


##################################
### generate_temporary_appfile ###
##################################

# Generate the Appfile based on the apple_id and team_id setting in Config.json for the current build variant
private_lane :generate_temporary_appfile do |options|
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  apple_id = build_variant_config[:apple_id]
  team_id = build_variant_config[:team_id]

  if apple_id == nil
    UI.important("Could not find the apple_id for this build variant, will use development@smfhq.com. Please update your Config.json.")
  else
    UI.message("Found apple_id: #{apple_id} in Config.json.")
  end

  # If there's no apple_id setting, use the default development@smfhq.com
  apple_id = apple_id != nil ? apple_id : "development@smfhq.com"

  appfile_content = "apple_id \"#{apple_id}\""

  #team_id is mandatory in Config.json, so no need checking for existence
  appfile_content = appfile_content + "\nteam_id \"#{team_id}\""

  File.write("#{smf_workspace_dir}/fastlane/Appfile", appfile_content)
end
