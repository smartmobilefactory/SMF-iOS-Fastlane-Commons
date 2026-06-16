##############################################
### App Store Connect API Key Auth helper  ###
##############################################
#
# Returns a fastlane `app_store_connect_api_key`-action hash if the Jenkins
# pipeline has injected the three `APP_STORE_CONNECT_API_KEY_*` environment
# variables (see Jenkins-Pipeline-Commons `vars/fastlane.groovy` line 141-143
# and `vars/loadAppStoreConnectCredentials.groovy`). Returns `nil` otherwise,
# in which case fastlane falls back to the legacy Apple-ID + app-specific
# password auth via `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`.
#
# Memoised per fastlane run — the action issues a JWT under the hood and
# we don't need to re-mint it for every lane that uses iTC.
#
# CBENEFIOS-1686 brought the Jenkins-side credentials online but the
# fastlane lanes here were never switched to consume them. This helper
# closes that loop without forcing every caller to handle the nil case.

def smf_app_store_connect_api_key
  return @smf_asc_api_key if defined?(@smf_asc_api_key) && !@smf_asc_api_key.nil?

  key_path   = ENV["APP_STORE_CONNECT_API_KEY_PATH"]
  key_id     = ENV["APP_STORE_CONNECT_API_KEY_ID"]
  issuer_id  = ENV["APP_STORE_CONNECT_API_KEY_ISSUER_ID"]

  return nil if key_path.nil? || key_path.empty?
  return nil if key_id.nil? || key_id.empty?
  return nil if issuer_id.nil? || issuer_id.empty?

  UI.important("Using App Store Connect API Key auth (Key ID: #{key_id})")

  @smf_asc_api_key = app_store_connect_api_key(
    key_id: key_id,
    issuer_id: issuer_id,
    key_filepath: key_path,
    duration: 1200,
    in_house: false
  )
end

####################################
### smf_upload_ipa_to_testflight ###
####################################

desc "upload the app on Testflight"
private_lane :smf_upload_ipa_to_testflight do |options|

  UI.important("Uploading the build to Testflight")

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  pilot_params = {
    apple_id: build_variant_config[:itc_apple_id],
    username: build_variant_config[:apple_id],
    team_id: build_variant_config[:itc_team_id],
    skip_waiting_for_build_processing: should_skip_waiting_after_itc_upload,
    wait_for_uploaded_build: (should_skip_waiting_after_itc_upload == false),
    changelog: ""
  }

  api_key = smf_app_store_connect_api_key
  pilot_params[:api_key] = api_key if api_key

  pilot(pilot_params)

end

#########################################
### smf_download_dsym_from_testflight ###
#########################################

desc "Download the dsym from iTunes Connect"
private_lane :smf_download_dsym_from_testflight do |options|

  UI.important("Download dsym from Testflight")

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  bundle_identifier = build_variant_config[:bundle_identifier]
  username = build_variant_config[:apple_id]

  build_number = get_build_number(
    xcodeproj: "#{project_name}.xcodeproj"
    ).to_s

  download_dsyms_params = {
    username: username,
    app_identifier: bundle_identifier,
    build_number: build_number
  }

  api_key = smf_app_store_connect_api_key
  download_dsyms_params[:api_key] = api_key if api_key

  download_dsyms(download_dsyms_params)

end

################################
###   smf_itunes_precheck    ###
################################

private_lane :smf_itunes_precheck do |options|

  # Variables
  project_config = @smf_fastlane_config[:project]
  project_name = project_config[:project_name]
  slack_channel = project_config[:slack_channel]

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  begin
    app_identifier = build_variant_config[:bundle_identifier]
    username = build_variant_config[:apple_id]

    precheck_params = {
      username: username.nil? ? nil : username,
      app_identifier: app_identifier
    }

    api_key = smf_app_store_connect_api_key
    precheck_params[:api_key] = api_key if api_key

    precheck(precheck_params)

  rescue => exception

    title = "Fastlane Precheck found Metadata issues in iTunes Connect for #{smf_default_notification_release_title} 😢"
    message = "The build will continue to upload to iTunes Connect, but you may need to fix the Metadata issues before releasing the app."

    smf_send_chat_message(
      title: title,
      message: message,
      type: "warning",
      exception: exception,
      slack_channel: slack_channel
      )
  end
end

################################################
###   smf_verify_common_itc_upload_errors    ###
################################################

private_lane :smf_verify_common_itc_upload_errors do |options|
  # TODO: still uses legacy `Spaceship::Tunes.login(user, password)` below —
  # needs migration to `Spaceship::ConnectAPI.token = …` with the ASC API
  # Key (same key as `smf_app_store_connect_api_key` returns). Out of scope
  # for the initial fix that unblocks `smf_upload_ipa_to_testflight`; track
  # in a follow-up. Until then this lane will fail authentication too when
  # the app-specific password expires.
  require 'spaceship'
  require 'credentials_manager'

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  version_number = smf_get_version_number
  build_number = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  bundle_identifier = build_variant_config[:bundle_identifier]
  itc_team_id = build_variant_config[:itc_team_id]
  itc_skip_version_check = build_variant_config[:itc_skip_version_check]

  username = build_variant_config[:apple_id]

  credentials = CredentialsManager::AccountManager.new(user: username)

  # Setup Spaceship
  ENV["FASTLANE_ITC_TEAM_ID"] = itc_team_id
  Spaceship::Tunes.login(credentials.user, credentials.password)
  Spaceship::Tunes.select_team

  # Get the currently editable version
  app = Spaceship::Tunes::Application.find(bundle_identifier)

  # Check if there is already a build with the same build number
  versions = [version_number]
  if app.edit_version
    versions.push(app.edit_version)
  end

  if app.live_version
    versions.push(app.live_version)
  end

  duplicate_build_number_erros = smf_check_if_itc_already_contains_buildnumber(app, versions, build_number)

  errors = duplicate_build_number_erros

  # Check if there is a matching editable app version
  if itc_skip_version_check != true
    no_matching_editable_app_version = smf_check_if_app_version_is_editable_in_itc(app, version_number)

    errors = errors + no_matching_editable_app_version
  end

  Spaceship::Tunes.client = nil

  if errors.length > 0
    raise errors.join("\n")
  end
end

##############
### HELPER ###
##############

def smf_check_if_itc_already_contains_buildnumber(app, version_numbers, build_number)

  errors = []

  for version in version_numbers
    
    UI.message("Checking if App version #{version} contains already the build number #{build_number}")
    
    build_trains = app.build_trains[version]
    if build_trains

      for build_train in build_trains  
        if build_train.build_version == build_number
          UI.error("Found matching build #{build_train.build_version}")
          errors.push("There is already a build uploaded with the build number #{build_number}. You need to increment the build number first before uploading to iTunes Connect.")
          break
        else
          UI.message("Found not matching build #{build_train.build_version}")
        end
      end

    end
  end

  return errors
end

def smf_check_if_app_version_is_editable_in_itc(app, version_number)

  editable_app = app.edit_version

  if editable_app == nil || editable_app.version != version_number
    live_app = app.live_version
    if live_app == version_number
      error = "The current App version #{version_number} is already in sale. You need to inrement the marketing version before you can upload a new Testflight build."
    elsif editable_app != nil
      error = "The current App version #{version_number} is not editable, but #{editable_app.version} is. Please investigate why there is a mismatch."
    else
      error = "There is no editable App version #{version_number}. Please investigate why there is a mismatch."
    end

    UI.error(error)

    return [error]
  else
    UI.success("The App version #{version_number} is editable.")
    return []
  end
end

def should_skip_waiting_after_itc_upload
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  return (build_variant_config[:itc_skip_waiting].nil? ? false : build_variant_config[:itc_skip_waiting])
end
