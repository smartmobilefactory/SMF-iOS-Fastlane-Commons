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


##############
### HELPER ###
##############

def should_skip_waiting_after_itc_upload(build_variant_config)
  return (build_variant_config["itc_skip_waiting"].nil? ? false : ["itc_skip_waiting"])
end
