fastlane_require 'net/https'
fastlane_require 'uri'
fastlane_require 'json'

################################
### smf_send_chat_message ###
################################

# options: title (String), message (String), additional_html_entries (Array of Strings), success (String), use_build_job_link_footer (Boolean) [Optional], slack_channel (String), fail_build_job_on_error (Boolean) [Optional]

desc "Sending a message to the given HipChat room"
private_lane :smf_send_chat_message do |options|

  # Skip sending if slack is disabled
  return unless smf_is_slack_enabled

  # Parameter
  title = "*#{options[:title]}*"
  message = options[:message]
  if message
    UI.message("Inital message: #{message}")
  else
    message = ""
  end
  exception = options[:exception]
  additional_html_entries = options[:additional_html_entries]
  fail_build_job_on_error = (options[:fail_build_job_on_error] == nil ? false : options[:additional_html_entries])
  attachment_path = options[:attachment_path]

  type = options[:type]
  success = false
  if type == "success" || type == "message"
    success = true
  end

  use_build_job_link_footer = options[:use_build_job_link_footer]
  slack_channel = (options[:slack_channel] != nil ? options[:slack_channel] : ci_ios_error_log)

  # Log the exceptions to find out if there is useful information which can be added to the message
  UI.message("exception.inspect: #{exception.inspect}")
  UI.message("exception.cause: #{exception.cause}") if exception.respond_to?(:cause)
  UI.message("exception.exception: #{exception.exception}") if exception.respond_to?(:exception)
  UI.message("exception.backtrace: #{exception.backtrace}") if exception.respond_to?(:backtrace)
  UI.message("exception.backtrace_locations: #{exception.backtrace_locations}") if exception.respond_to?(:backtrace_locations)
  UI.message("exception.preferred_error_info: #{exception.preferred_error_info}") if exception.respond_to?(:preferred_error_info)
  UI.message("exception.error_info: #{exception.error_info}") if exception.respond_to?(:error_info)

  if slack_channel && (slack_channel.include? "/") == false

    project_name = @smf_fastlane_config[:project][:project_name]
    slack_channel = URI.unescape(slack_channel) == slack_channel ? URI.escape(slack_channel) : slack_channel

    content = ""

    if message != nil && message.length > 0
      UI.message("Adding message: #{message}")
      content << "#{message[0..4000]}#{'... (maxmium length reached)' if message.length > 4000}"
    elsif exception != nil
      error_info = exception.respond_to?(:preferred_error_info) ? exception.preferred_error_info : nil
      error_info = exception.respond_to?(:error_info) ? exception.error_info : nil
      if (error_info == nil)
        error_info = exception.exception
      end

      UI.message("Found error_info: #{error_info}")
      if error_info != nil && error_info.to_s.length > 0
        UI.message("Adding error_info: #{error_info.to_s}")
        content << ("#{error_info.to_s[0..4000]}#{'... (maxmium length reached)' if error_info.to_s.length > 4000}")
      end
    end

    if additional_html_entries
      for additional_html_entry in additional_html_entries do
        UI.message("Adding additional_html_entry: #{additional_html_entry}")
        content << ("#{additional_html_entry}")
      end
    end

    UI.message("Sending message \"#{content}\" to room \"#{slack_channel}\"")
    slack_workspace_url = "https://hooks.slack.com/services/" + ENV[slack_url]

    # Send failure messages also to CI to notice them so that we can see if they can be improved
    begin
      if type == "error" && ((slack_channel.eql? ci_ios_error_log) == false)
        slack(
          slack_url: slack_workspace_url,
          message: content,
          pretext: title,
          success: success,
          channel: "#{ci_ios_error_log}",
          username: "#{project_name} iOS CI",
          payload: {
            "Build Job" => "#{ENV["BUILD_URL"]}",
            "Build Type" => "#{type}",
          },
          default_payloads: [:git_branch]
        )
      end
    rescue => exception
      UI.important("Failed to send error message to #{ci_ios_error_log} Slack room. Exception: #{exception}")
    end

    begin
        if attachment_path != nil
          slack(
            slack_url: slack_workspace_url,
            message: content,
            pretext: title,
	    success: success,
            channel: "#{slack_channel}",
            username: "#{project_name} iOS CI",
            payload: {
              "Build Job" => "#{ENV["BUILD_URL"]}",
              "Build Type" => "#{type}",
            },
            default_payloads: [:git_branch],
            attachment_properties: {
              fields: [
                {
                   title: "Attachment",
                   value: "#{attachment_path}"
                }
              ]
            }
          )
        elsif
          slack(
            slack_url: slack_workspace_url,
            message: content,
            pretext: title,
	    success: success,
            channel: "#{slack_channel}",
            username: "#{project_name} iOS CI",
            payload: {
              "Build Job" => "#{ENV["BUILD_URL"]}",
              "Build Type" => "#{type}",
            },
            default_payloads: [:git_branch]
          )
        end
    rescue => exception
      UI.important("Failed to send error message to #{slack_channel} Slack room. Exception: #{exception}")
      if fail_build_job_on_error
        raise exception
      end
    end
  elsif slack_channel
        UI.error("Didn't send message as \"slack_channel\" contains \"/\"")
  else
    UI.message("Didn't send message as \"slack_channel\" is nil")
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
  elsif smf_is_build_variant_a_decoupled_ui_test == true
    release_title = smf_default_decoupled_ui_test_notification_name_title
  else
    release_title = smf_default_app_notification_release_title
  end
  return release_title
end

def smf_default_app_notification_release_title

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant = @smf_build_variant

  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  version = smf_get_version_number
  return "#{project_name} #{build_variant.upcase} #{version} (#{build_number})"
end

def smf_default_pod_notification_release_title

  # Variables
  podspec_path = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:podspec_path]
  version = read_podspec(path: podspec_path)["version"]
  pod_name = read_podspec(path: podspec_path)["name"]

  # Project name
  project_name = @smf_fastlane_config[:project][:project_name]
  project_name = (project_name.nil? ? pod_name : project_name)

  return "#{project_name} #{version}"
end

def smf_default_decoupled_ui_test_notification_name_title
  return "#{ENV[$SMF_UI_TEST_REPORT_NAME_FOR_NOTIFICATIONS]}"
end
