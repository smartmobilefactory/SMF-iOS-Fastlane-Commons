
  desc "Send emails to the collaborators"
  private_lane :notify_via_mail do |options|

    authors_email = options[:authors_email]
    success = options[:success]

    case success
    when true
      subject = "#{PROJECT_NAME} realeased successfully #{get_build_number}"
      message = "#{PROJECT_NAME} have a new version #{get_build_number} 🎉🎉🎉"
    else
      subject = "#{PROJECT_NAME} failed"
      message = "#{PROJECT_NAME} failed to upload a new version 😢😢😢"
    end

    authors_email.each do |c|
      mailgun(
              subject: subject,
              postmaster:"postmaster@mailgun.smfhq.com",
              apikey: "key-74595c7e3dbbab1e25af00bea08571b8",
              to: c,
              success: success,
              message: message,
              app_link: Actions.lane_context[Actions::SharedValues::HOCKEY_DOWNLOAD_LINK],
              ci_build_link: ENV["BUILD_URL"]
              )
    end

  end