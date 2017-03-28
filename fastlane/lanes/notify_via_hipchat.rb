

  desc "Send emails to the collaborators"
  private_lane :notify_via_hipchat do |options|

    room = options[:room]
    api_token = options[:api_token]

    hipchat(
      message: "#{PROJECT_NAME} successfully released version #{get_build_number}!",
      channel: room,
      success: true,
      api_token: api_token,
      notify_room: true,
      version: "2"
    )

  end
