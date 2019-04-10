#######################################
### smf_disable_former_hockey_entry ###
#######################################

# options: build_variants_contains_whitelist (Hash)

desc "Disable the downlaod of the former app version on HockeyApp - does not apply for Alpha builds."
private_lane :smf_disable_former_hockey_entry do |options|

  # Parameter
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  # Variables
  build_variant = @smf_build_variant
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  # Disable the download of the former non Alpha app on Hockey App
  if (!build_variants_contains_whitelist) || (build_variants_contains_whitelist.any? { |whitelist_item| build_variant.include?(whitelist_item) })
    if (Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] > 1)
      previous_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] - 1

      UI.important("HERE IS THE ID OF THE Current VERSION #{Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']}")
      UI.important("HERE IS THE ID OF THE Previous VERSION #{previous_version_id}")

      disable_hockey_download(
        api_token: ENV[$SMF_HOCKEYAPP_API_TOKEN_ENV_KEY],
        public_identifier: build_variant_config[:hockeyapp_id],
        version_id: "#{previous_version_id}"
        )
    end
  end
end

########################################
### smf_delete_uploaded_hockey_entry ###
########################################

# options: apps_hockey_id (String)

desc "Deletes the uploaded app version on Hockey. It should be used to clean up after a error response from hockey app."
private_lane :smf_delete_uploaded_hockey_entry do |options|

  # Parameter
  apps_hockey_id = options[:apps_hockey_id]

  # Disable the download of the former non Alpha app on Hockey App
  app_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']
  if (app_version_id > 1)
    UI.important("Will remove the app version with id: #{app_version_id}")

    delete_app_version_on_hockey(
      api_token: ENV[$SMF_HOCKEYAPP_API_TOKEN_ENV_KEY],
      public_identifier: apps_hockey_id,
      version_id: "#{app_version_id}"
     )
  else
    UI.message("No HOCKEY_BUILD_INFORMATION was found, so there is nothing to delete.")
    end
end

################################
### smf_upload_ipa_to_hockey ###
################################

desc "Clean, build and release the app on HockeyApp"
private_lane :smf_upload_ipa_to_hockey do |options|

  UI.important("Upload a new build to HockeyApp")

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  project_name = @smf_fastlane_config[:project][:project_name]
  escaped_filename = build_variant_config[:scheme].gsub(" ", "\ ")

  # Construct path to DSYMs
  version_number = smf_get_version_number
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  dsym_path = Pathname.getwd.dirname.to_s + "/build/#{escaped_filename}.app.dSYM.zip"
  UI.message("Constructed the dsym path \"#{dsym_path}\"")
  unless File.exist?(dsym_path)
    dsym_path = nil

    UI.message("Using nil as dsym_path as no file exists at the constructed path.")
  end

  NO_APP_FAILURE = "NO_APP_FAILURE"

  if ( ! build_variant_config[:use_sparkle])
     sh "cd ../build; zip -r9 \"#{escaped_filename}.app.zip\" \"#{escaped_filename}.app\" || echo #{NO_APP_FAILURE}"
  end

  # Upload the dmg instead of the app if sparkle is enabled
  app_path = smf_path_to_ipa_or_app
  if (build_variant_config[:use_sparkle])
    app_path = app_path.sub(".app", ".dmg")
       if ( ! File.exists?(app_path))
          raise("DMG file #{app_path} does not exit. Nothing to upload.")
       end
  end

  # Get the release notes
  release_notes = "#{ENV[$SMF_CHANGELOG_ENV_KEY][0..4995]}#{'\\n...' if ENV[$SMF_CHANGELOG_ENV_KEY].length > 4995}"

  if (build_variant_config[:use_sparkle])
    hockey(
      api_token: ENV[$SMF_HOCKEYAPP_API_TOKEN_ENV_KEY],
      ipa: app_path,
      bundle_short_version: version_number,
      bundle_version: build_number,
      create_update: "1",
      notify: "0",
      notes: release_notes,
      public_identifier: build_variant_config[:hockeyapp_id],
      dsym: dsym_path  
    )
  elsif
    hockey(
      api_token: ENV[$SMF_HOCKEYAPP_API_TOKEN_ENV_KEY],
      ipa: app_path,
      notify: "0",
      notes: release_notes,
      public_identifier: build_variant_config[:hockeyapp_id],
      dsym: dsym_path  
    )
  end

end
