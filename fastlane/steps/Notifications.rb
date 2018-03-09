fastlane_require 'net/https'
fastlane_require 'uri'
fastlane_require 'json'

################################
### smf_send_hipchat_message ###
################################

# options: title (String), message (String), additional_html_entries (Array of Strings), success (String), use_build_job_link_footer (Boolean) [Optional], hipchat_channel (String)

desc "Sending a message to the given HipChat room"
private_lane :smf_send_hipchat_message do |options|

  # Parameter
  title = options[:title]
  message = options[:message]
  if message
    UI.message("Inital message: #{message}")
  end
  exception = options[:exception]
  additional_html_entries = options[:additional_html_entries]
  success = options[:success]
  use_build_job_link_footer = options[:use_build_job_link_footer]
  hipchat_channel = options[:hipchat_channel]

  # Log the exceptions to find out if there is useful information which can be added to the message
  UI.message("exception.inspect: #{exception.inspect}")
  UI.message("exception.cause: #{exception.cause}") if exception.respond_to?(:cause)
  UI.message("exception.exception: #{exception.exception}") if exception.respond_to?(:exception)
  UI.message("exception.backtrace: #{exception.backtrace}") if exception.respond_to?(:backtrace)
  UI.message("exception.backtrace_locations: #{exception.backtrace_locations}") if exception.respond_to?(:backtrace_locations)
  UI.message("exception.preferred_error_info: #{exception.preferred_error_info}") if exception.respond_to?(:preferred_error_info)
  UI.message("exception.error_info: #{exception.error_info}") if exception.respond_to?(:error_info)
  
  if hipchat_channel && (hipchat_channel.include? "/") == false

    project_name = @smf_fastlane_config[:project][:project_name]
    hipchat_channel = URI.unescape(hipchat_channel) == hipchat_channel ? URI.escape(hipchat_channel) : hipchat_channel

    content = "<table><tr><td><strong>#{title}</strong></td></tr><tr></tr></table>"

    if message != nil && message.length > 0
      UI.message("Adding message: #{message}")
      content << "<table><tr><td><pre>#{message[0..4000]}#{' <br/>... (maxmium length reached)' if message.length > 4000}</pre></td></tr></table>"
    end

    # Show the error info if it's provided
    if exception != nil
      error_info = exception.respond_to?(:preferred_error_info) ? exception.preferred_error_info : nil
      error_info = exception.respond_to?(:error_info) ? exception.error_info : nil

      UI.message("Found error_info: #{error_info}")
      if error_info != nil && error_info.to_s.length > 0
        UI.message("Adding error_info: #{error_info.to_s}")
        content << ("<table><tr><td><strong>Error Info:</strong></td></tr><tr>")
        content << ("<tr><td>#{error_info.to_s[0..4000]}#{' <br/>... (maxmium length reached)' if error_info.to_s.length > 4000}</td></tr></table>")
      end
    end

    if additional_html_entries
      for additional_html_entry in additional_html_entries do
        UI.message("Adding additional_html_entry: #{additional_html_entry}")
        content << ("<table><tr><td>#{additional_html_entry}</td></tr></table>")
      end
    end

    if use_build_job_link_footer != false
        UI.message("Adding use_build_job_link_footer")
        content << ("<table><tr><td><strong>Source: </strong><a href=#{ENV["BUILD_URL"]}>Build Job Console</a></td></tr></table>")
    end

    UI.message("Sending message \"#{content}\" to room \"#{hipchat_channel}\"")

    # Send failure messages also to CI to notice them so that we can see if they can be improved
    if success == false && ((hipchat_channel.eql? "CI") == false)
      hipchat(
      message: content,
      channel: "CI",
      success: success,
      api_token: ENV[$SMF_HIPCHAT_API_TOKEN_ENV_KEY],
      notify_room: true,
      version: "2",
      message_format: "html",
      include_html_header: false,
      from: "#{project_name} iOS CI"
      )
    end

    hipchat(
      message: content,
      channel: hipchat_channel,
      success: success,
      api_token: ENV[$SMF_HIPCHAT_API_TOKEN_ENV_KEY],
      notify_room: true,
      version: "2",
      message_format: "html",
      include_html_header: false,
      from: "#{project_name} iOS CI"
      )
  elsif hipchat_channel
        UI.error("Didn't send message as \"hipchat_channel\" contains \"/\"")
  else
    UI.message("Didn't send message as \"hipchat_channel\" is nil")
  end

end

#####################################
### smf_send_mail_to_contributors ###
#####################################

# options: title (String), message (String), success (Boolean), exception_message (String) [Optional], app_link (String), template_path (String) [Optional], send_only_to_internal_adresses (Boolean) [Optional]

desc "Send emails to all collaborators who worked on the project since the last build to inform about successfully or failing build jobs."
private_lane :smf_send_mail_to_contributors do |options|

  # Parameter
  title = options[:title]
  message = options[:message]
  success = options[:success]
  exception_message = options[:exception_message]
  send_only_to_internal_adresses = options[:send_only_to_internal_adresses]
  app_link = options[:app_link]
  template_path = options[:template_path]

  authors_emails = []
  if ENV[$SMF_CHANGELOG_EMAILS_ENV_KEY]
    authors_emails = ENV[$SMF_CHANGELOG_EMAILS_ENV_KEY].split(" ").uniq.delete_if{|e| e == "git-checkout@smartmobilefactory.com"}
  end

  smf_send_mail(
    title: title,
    message:message,
    success: success,
    exception_message: exception_message,
    authors_emails: authors_emails,
    send_only_to_internal_adresses: send_only_to_internal_adresses,
    app_link: app_link,
    template_path: template_path
    )

end

#####################
### smf_send_mail ###
#####################

# options: title (String), message (String), success (Boolean), exception_message (String) [Optional], authors_emails (Array), app_link (String), template_path (String) [Optional], send_only_to_internal_adresses (Boolean) [Optional]

desc "Send emails to all collaborators who worked on the project since the last build to inform about successfully or failing build jobs."
private_lane :smf_send_mail do |options|

  # Parameter
  title = options[:title]
  message = (options[:message].nil? ? "" : options[:message])
  success = options[:success]
  exception_message = (options[:exception_message].nil? || options[:exception_message].length == 0 ? "" : options[:exception_message])
  authors_emails = options[:authors_emails]
  send_only_to_internal_adresses = (options[:send_only_to_internal_adresses].nil? ? true : options[:send_only_to_internal_adresses])
  app_link = (options[:app_link].nil? ? "" : options[:app_link])
  template_path = (options[:template_path] ? options[:template_path] : "/Users/smf/jenkins/template_mail_ios.erb")

  if send_only_to_internal_adresses == true
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
      text-align: center;' >#{exception_message[0..8000]}#{'\\n...' if exception_message.length > 8000}<p>
      <strong>Source: </strong><a href=#{ENV["BUILD_URL"]}>Build Job Console</a>"
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
      template_path: template_path
      )
  end

end

###################################
### smf_send_ios_hockey_app_apn ###
###################################

desc "Send a Push Notification through OneSignal to the SMF HockeyApp"
private_lane :smf_send_ios_hockey_app_apn do |options|

  UI.important("Sending APN to the SMF HockeyApps which inform the users that a new version of favorited apps is built.")

  # Variables
  hockeyapp_id = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:hockeyapp_id]

  # Create valid URI
  uri = URI.parse('https://onesignal.com/api/v1/notifications')

  # Authentification Header
  header = {
    'Content-Type' => 'application/json; charset=utf-8',
    'Authorization' => "Basic #{ENV[$SMF_ONE_SIGNAL_BASIC_AUTH_ENV_KEY]}" # OneSignal User AuthKey REST API
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
        'key' => hockeyapp_id,
        'value' => 'com.usernotifications.app_update'
      }
    ],
    'data' => {
      'HockeyAppId' => hockeyapp_id
    }
  }

  # Create and send a POST request
  https = Net::HTTP.new(uri.host,uri.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(uri.path, header)
  request.body = payload.to_json
  https.request(request)

end

##############
### HELPER ###
##############

def smf_default_notification_release_title
  release_title = nil
  if smf_is_build_variant_a_pod == true
    release_title = smf_default_pod_notification_release_title
  else
    release_title = smf_default_app_notification_release_title
  end
  return release_title
end

def smf_default_app_notification_release_title

  # Variables
  branch = @smf_git_branch
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant = @smf_build_variant

  # Create the branch name string
  branch_suffix = ""
  if branch.nil? == false and branch.length > 0
    branch_suffix = " from branch \"#{branch}\""
    branch_suffix.sub!("origin/", "")
  end

  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  version = get_version_number(xcodeproj: "#{project_name}.xcodeproj")
  return "#{project_name} #{build_variant.upcase} #{version} (#{build_number})#{branch_suffix}"
end

def smf_default_pod_notification_release_title

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  podspec_path = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:podspec_path]
  branch = @smf_git_branch

  version = read_podspec(path: podspec_path)["version"]

  # Create the branch name string
  branch_suffix = ""
  if branch.nil? == false and branch.length > 0
    branch_suffix = " from branch \"#{branch}\""
    branch_suffix.sub!("origin/", "")
  end

  return "#{project_name} #{version}#{branch_suffix}"
end
