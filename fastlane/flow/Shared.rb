####################
### smf_check_pr ###
####################

private_lane :smf_check_pr do |options|

  smf_install_pods_if_project_contains_podfile

  # Use the current build variant if no array of build variants to check is provided
  if @smf_build_variants_array.nil? || @smf_build_variants_array.length == 0
    smf_set_build_variants_array([@smf_build_variant])
  else
    UI.important("Multiple build variants are declared. Checking the PR for #{@smf_build_variants_array}")
  end

  for build_variant in @smf_build_variants_array

    UI.important("Starting PR check for build variant \"#{build_variant}\"")

    smf_set_build_variant(build_variant, false)

    # Archive the IPA if the build variant didn't opt-out
    build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
    should_archive_ipa = (build_variant_config["pr.archive_ipa".to_sym].nil? ? true : build_variant_config["pr.archive_ipa".to_sym])

    if should_archive_ipa
      smf_archive_ipa_if_scheme_is_provided
    end
    
    # Run the unit tests if the build variant didn't opt-out
    should_perform_unit_test = (build_variant_config["pr.perform_unit_tests".to_sym].nil? ? true : build_variant_config["pr.perform_unit_tests".to_sym])

    if should_perform_unit_test
      smf_perform_unit_tests
    end

    # Run Danger if the build variant didn't opt-out
    should_run_danger = (build_variant_config["pr.run_danger".to_sym].nil? ? true : build_variant_config["pr.run_danger".to_sym])

    if should_run_danger
      smf_run_danger
    end
  end

end

#############################################
### smf_send_deploy_success_notifications ###
#############################################

# options: app_link (String) [optional]

desc "Handle the success of a deploy by sending email to the authors and post to the hipchat channel"
private_lane :smf_send_deploy_success_notifications do |options|

  # Parameter
  app_link = (options[:app_link].nil? ? Actions.lane_context[Actions::SharedValues::HOCKEY_DOWNLOAD_LINK] : options[:app_link])

  # Variables
  hipchat_channel = @smf_fastlane_config[:project][:hipchat_channel]

  if ENV[$SMF_CHANGELOG_ENV_KEY].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog
  end

  title = "Built #{smf_default_notification_release_title} 🎉"

  smf_send_mail_to_contributors(
    title: title,
    message: ENV[$SMF_CHANGELOG_ENV_KEY],
    success: true,
    app_link: app_link
    )

  if hipchat_channel
    smf_send_hipchat_message(
      title: title,
      message: ENV[$SMF_CHANGELOG_ENV_KEY],
      success: true,
      hipchat_channel: hipchat_channel
      )
  end
end

############################
### smf_handle_exception ###
############################

# options: exception (exception)

desc "Handle the exception by sending email to the authors"
private_lane :smf_handle_exception do |options|

  UI.important("Handling the build job exception")

  # Parameter
  exception = options[:exception]

  apps_hockey_id = ENV[$SMF_APP_HOCKEY_ID_ENV_KEY]
  if not apps_hockey_id.nil?
    begin
      smf_delete_uploaded_hockey_entry(
        apps_hockey_id: apps_hockey_id
      )
      UI.important("The app version which was uploaded to HockeyApp was removed as something else in the build job failed!")
    rescue
      UI.message("he app version which was uploaded to HockeyApp wasn't removed. This is fine if it wasn't yet uploaded")
    end
  end

  if ENV[$SMF_CHANGELOG_ENV_KEY].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog
  end

  title = "Failed to build #{smf_default_notification_release_title} 😢"

  smf_send_mail_to_contributors(
    title: title,
    success: false,
    exception_message: exception
    )

  if hipchat_channel
    smf_send_hipchat_message(
      title: title,
      message: "#{exception.message}",
      success: false,
      hipchat_channel: @smf_fastlane_config[:project][:hipchat_channel]
      )
  end
end
