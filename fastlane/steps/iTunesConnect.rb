####################################
### smf_upload_ipa_to_testflight ###
####################################

desc "upload the app on Testflight"
private_lane :smf_upload_ipa_to_testflight do |options|

  UI.important("Uploading the build to Testflight")

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  if build_variant_config.key? "itc_apple_id"
    username = build_variant_config[:itc_apple_id]
  else
    username = nil
  end

  pilot(
    username: username,
    skip_waiting_for_build_processing: should_skip_waiting_after_itc_upload,
    changelog: ""
    )

end

#########################################
### smf_download_dsym_from_testflight ###
#########################################

desc "Download the dsym from iTunes Connect"
private_lane :smf_download_dsym_from_testflight do |options|

  UI.important("Download dsym from Testflight")

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  bundle_identifier = build_variant_config[:bundle_identifier]
  username = build_variant_config[:itc_apple_id]

  build_number = get_build_number(
    xcodeproj: "#{project_name}.xcodeproj"
    ).to_s

  download_dsyms(
    username: username,
    app_identifier: bundle_identifier,
    build_number: build_number
    )

end

################################
###   smf_itunes_precheck    ###
################################

private_lane :smf_itunes_precheck do |options|

  # Variables
  project_config = @smf_fastlane_config[:project]
  project_name = project_config[:project_name]
  hipchat_channel = project_config[:hipchat_channel]

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  begin
    app_identifier = build_variant_config[:bundle_identifier]
    username = build_variant_config[:itc_apple_id]

    precheck(
      username: username.nil? ? nil : username,
      app_identifier: app_identifier
      )

  rescue => exception

    title = "Fastlane Precheck found Metadata issues in iTunes Connect for #{smf_default_notification_release_title} 😢"
    message = "The build will continue to upload to iTunes Connect, but you may need to fix the Metadata issues before releasing the app."

    smf_send_mail(
      title: title,
      message: message,
      success: false,
      exception_message: "#{exception}",
      authors_emails: ["development@smfhq.com"],
      template_path: "/Users/smf/jenkins/template_mail_ios_precheck.erb"
    )

    smf_send_hipchat_message(
      title: title,
      message: message,
      success: false,
      exception: exception,
      hipchat_channel: hipchat_channel
      )
  end
end

################################################
###   smf_verify_common_itc_upload_errors    ###
################################################

private_lane :smf_verify_common_itc_upload_errors do |options|
  require 'spaceship'

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  version_number = get_version_number(xcodeproj: "#{project_name}.xcodeproj")
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  bundle_identifier = build_variant_config[:bundle_identifier]
  itc_team_id = build_variant_config[:itc_team_id]

  # Setup Spaceship
  ENV["FASTLANE_ITC_TEAM_ID"] = itc_team_id
  Spaceship::Tunes.login
  Spaceship::Tunes.select_team

  # Get the currently editable version
  app = Spaceship::Tunes::Application.find(bundle_identifier)

  # Check if there is already a build with the same build number
  versions = [version_number]
  if app.edit_version
    versions.push(app.edit_version)
  end

  if app.live_version
    versions.push(app.live_version)
  end

  duplicate_build_number_erros = smf_check_if_itc_already_contains_buildnumber(app, versions, build_number)

  # Check if there is a matching editable app version
  no_matching_editable_app_version = smf_check_if_app_version_is_editable_in_itc(app, version_number)

  errors = duplicate_build_number_erros + no_matching_editable_app_version

  if errors.length > 0
    raise "#{errors}"
  end
end

##############
### HELPER ###
##############

def smf_check_if_itc_already_contains_buildnumber(app, version_numbers, build_number)

  errors = []

  for version in version_numbers
    
    UI.message("Checking if App version #{version} contains already the build number #{build_number}")
    
    build_trains = app.build_trains[version]
    if build_trains

      for build_train in build_trains  
        if build_train.build_version == build_number
          UI.error("Found matching build #{build_train.build_version}")
          errors.push("There is already a build uploaded with the build number #{build_number}. You need to increment the build number first before uploading to iTunes Connect.")
          break
        else
          UI.message("Found not matching build #{build_train.build_version}")
        end
      end

    end
  end

  return errors
end

def smf_check_if_app_version_is_editable_in_itc(app, version_number)

  editable_app = app.edit_version

  if editable_app == nil || editable_app.version != version_number
    live_app = app.live_version
    if live_app == version_number
      error = "The App version #{version_number} is already in sale. You need to inrement the marketing version before you can upload a new Testflight build."
    elsif editable_app != nil
      error = "The App version #{version_number} is no editable, but #{editable_app.version} is. Please investigate why there is a mismatch."
    else
      error = "There is no editable version #{version_number}. Please investigate why there is a mismatch."
    end

    UI.error(error)

    return [error]
  else
    UI.success("The App version #{version_number} is editable.")
    return []
  end
end

def should_skip_waiting_after_itc_upload
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  return (build_variant_config[:itc_skip_waiting].nil? ? false : build_variant_config[:itc_skip_waiting])
end
