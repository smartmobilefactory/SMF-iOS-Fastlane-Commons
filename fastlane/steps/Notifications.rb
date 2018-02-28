fastlane_require 'net/https'
fastlane_require 'uri'
fastlane_require 'json'

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
