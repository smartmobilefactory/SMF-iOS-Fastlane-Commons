
  desc "Clean, build and release the app on HockeyApp"
  private_lane :disable_former_hockey_entry do |options|

    hockeyAppId = options[:hockeyAppId]
    buildVariant = options[:buildVariant]

    # Disable the download of the former non Alpha app on Hockey App
    if (buildVariant != "Alpha") && (Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] > 1)
      previous_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] - 1

      UI.important("HERE IS THE ID OF THE Current VERSION #{Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']}")
      UI.important("HERE IS THE ID OF THE Previous VERSION #{previous_version_id}")

      disable_hockey_download(
        api_token: ENV["HOCKEYAPP_API_TOKEN"],
        public_identifier: hockeyAppId,
        version_id: "#{previous_version_id}"
        )
    end

    clean_build_artifacts

  end
