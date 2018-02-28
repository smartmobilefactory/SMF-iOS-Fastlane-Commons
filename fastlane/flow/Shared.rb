############################
### smf_handle_exception ###
############################

# options: exception (exception), build_variant (String), project_config (Hash), release_title (String) [optional]

desc "Handle the exception by sending email to the authors"
private_lane :smf_handle_exception do |options|

  UI.important("Handle the build job exception")

  # Read options parameter
  exception = options[:exception]
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  hipchat_channel = project_config["hipchat_channel"]
  release_title = (options[:release_title].nil? ? smf_default_app_notification_release_title(project_config["project_name"], build_variant) : options[:release_title])

  apps_hockey_id = ENV["SMF_APP_HOCKEY_ID"]
  if not apps_hockey_id.nil?
    begin
      smf_delete_uploaded_hockey_entry(
        apps_hockey_id: apps_hockey_id
      )
    rescue
      UI.message("The HockeyApp entry wasn't removed. This is fine if it wasn't yet uploaded")
    end
  end

  if ENV["SMF_CHANGELOG"].nil?
    # Collect the changelog (again) in case the build job failed before the former changelog collecting
    smf_collect_changelog(
      build_variant: build_variant,
      project_config: project_config
      )
  end

  message_title = "Failed to build #{release_title} 😢"

  smf_notify_via_mail(
    title: message_title,
    message: message_title,
    success: false,
    exception_message: exception,
    app_link: ""
    )

    if hipchat_channel
      hipchat_channel = URI.escape(hipchat_channel)

      smf_notify_via_hipchat(
        title: message_title,
        message: "#{exception.message}",
        project_name: project_config["name"],
        additional_html_entries: ["strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a>"],
        hipchat_channel: hipchat_channel,
        success: false
        )
    end
end
