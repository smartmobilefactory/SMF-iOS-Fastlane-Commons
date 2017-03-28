
  desc "Clean, build and release the app on HockeyApp"
  private_lane :upload_ipa_to_hockey do |options|

    hockeyAppId = options[:hockeyAppId]
    buildVariant = options[:buildVariant]


    UI.important("Upload a new build to HockeyApp")
    #Print .ipa path
    puts "IPA: "+lane_context[SharedValues::IPA_OUTPUT_PATH]+"".green

    hockey(
      api_token: ENV["HOCKEYAPP_API_TOKEN"],
      ipa: lane_context[SharedValues::IPA_OUTPUT_PATH],
      notify: "0",
      notes: ENV["CHANGELOG"],
      public_identifier: hockeyAppId
      )

    clean_build_artifacts

  end
