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

  rescue => e

    title = "Fastlane Precheck found Metadata issues for #{project_name} #{@smf_build_variant.upcase} in iTunes Connect 😢"
    message = "The build will continue to upload to iTunes Connect, but you may need to fix the Metadata issues before releasing the app."

    smf_send_mail(
      title: title,
      message: message,
      success: false,
      exception_message: e,
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


##############
### HELPER ###
##############

def should_skip_waiting_after_itc_upload
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  return (build_variant_config[:itc_skip_waiting].nil? ? false : build_variant_config[:itc_skip_waiting])
end
