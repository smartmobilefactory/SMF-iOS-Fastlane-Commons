#######################################
### smf_disable_former_hockey_entry ###
#######################################

# options: build_variant_config (Hash), build_variant (String)

desc "Disable the downlaod of the former app version on HockeyApp - does not apply for Alpha builds."
private_lane :smf_disable_former_hockey_entry do |options|

  # Read options parameter
  build_variant = options[:build_variant].downcase
  build_variant_config = options[:build_variant_config]
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  # Disable the download of the former non Alpha app on Hockey App
  if (!build_variants_contains_whitelist) || (build_variants_contains_whitelist.any? { |whitelist_item| build_variant.include?(whitelist_item) })
    if (Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] > 1)
      previous_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id'] - 1

      UI.important("HERE IS THE ID OF THE Current VERSION #{Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']}")
      UI.important("HERE IS THE ID OF THE Previous VERSION #{previous_version_id}")

      disable_hockey_download(
        api_token: ENV["HOCKEYAPP_API_TOKEN"],
        public_identifier: build_variant_config["hockeyapp_id"],
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

  # Read options parameter
  apps_hockey_id = options[:apps_hockey_id]

  # Disable the download of the former non Alpha app on Hockey App
  app_version_id  = Actions.lane_context[Actions::SharedValues::HOCKEY_BUILD_INFORMATION]['id']
  if (app_version_id > 1)
    UI.important("Will remove the app version with id: #{app_version_id}")

    delete_app_version_on_hockey(
      api_token: ENV["HOCKEYAPP_API_TOKEN"],
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

# options: project_config (Hash)

desc "Clean, build and release the app on HockeyApp"
private_lane :smf_upload_ipa_to_hockey do |options|

  UI.important("Upload a new build to HockeyApp")

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  hockey_app_id = options[:build_variant_config]["hockeyapp_id"]
  bundle_identifier = options[:build_variant_config]["bundle_identifier"]
  version_number = get_version_number(xcodeproj: "#{project_name}.xcodeproj")
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  scheme = options[:build_variant_config]["scheme"]

  release_notes = message = "#{ENV["SMF_CHANGELOG"][0..4995]}#{'\\n...' if ENV["SMF_CHANGELOG"].length > 4995}"

  #DSYM Path
  path = Pathname.getwd.dirname.to_s + "/#{bundle_identifier}-#{version_number}-#{build_number}.dSYM.zip"
  
  NO_APP_FAILURE = "NO_APP_FAILURE"
  escaped_filename = scheme.gsub(" ", "\ ")
  sh "cd ../build; zip -r9 \"#{escaped_filename}.app.zip\" \"#{escaped_filename}.app\" || echo #{NO_APP_FAILURE}"
  app_path = Pathname.getwd.dirname.to_s + "/build/#{escaped_filename}.app.zip"
  puts app_path


  hockey(
    api_token: ENV["HOCKEYAPP_API_TOKEN"],
    ipa: File.exist?(app_path) ? app_path : lane_context[SharedValues::IPA_OUTPUT_PATH], 
    notify: "0",
    notes: release_notes,
    public_identifier: hockey_app_id,
    dsym: File.exist?(path) ? path : nil  
  )

end
