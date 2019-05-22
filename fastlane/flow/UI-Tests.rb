require 'json'

################################################
### smf_perform_ui_tests_from_github_webhook ###
################################################

desc "Trigger UITests from a given tag_name"
lane :smf_perform_ui_tests_with_tag_name do |options|

  # Parameters
  tag_name = options[:tag_name]
  report_sync_destination = options[:report_sync_destination]
  github_token = options[:github_token]
  simulators = options[:simulators]

  # Variables
  project_path = @smf_fastlane_config[:project][:github_repo_path]
  assets = smf_fetch_assets_for_tag(tag_name, github_token, project_path)

  # Call lane
  smf_perform_ui_tests_with_assets(
    assets: assets,
    tag_name: tag_name,
    report_sync_destination: report_sync_destination,
    github_token: github_token,
    simulators: simulators
  )
end


desc "Github triggered UITests for Simulators"
lane :smf_perform_ui_tests_from_github_webhook do |options|

  # Parameters
  payload = options[:payload]
  report_sync_destination = options[:report_sync_destination]
  github_token = options[:github_token]
  simulators = options[:simulators]

  # Variables
  assets = payload["release"]["assets"]
  tag_name = payload["release"]["tag_name"]
  
  # Call lane
  smf_perform_ui_tests_with_assets(
    assets: assets,
    tag_name: tag_name,
    report_sync_destination: report_sync_destination,
    github_token: github_token,
    simulators: simulators
  )
end

lane :smf_perform_ui_tests_with_assets do |options|

  # Parameters
  assets = options[:assets]
  tag_name = options[:tag_name]
  report_sync_destination = options[:report_sync_destination]
  github_token = options[:github_token]
  simulators = options[:simulators]

  # Variables
  report_name = tag_name
  report_name = report_name.gsub("build/", "")
  report_name = report_name.gsub!("/", "-")
  ENV[$SMF_UI_TEST_REPORT_NAME_FOR_NOTIFICATIONS] = report_name

  ui_test_triggering_github_releases = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:ui_test_triggering_github_releases]

  tag_name_matches_result = tag_name =~ /#{ui_test_triggering_github_releases.gsub("\\/", "\/")}/
  if tag_name_matches_result == nil
    UI.important("Release \"#{tag_name}\" is not eligible to be tested. Only tags matching \"#{ui_test_triggering_github_releases}\" are allowed.")
    # Stop the execution of this lane

    jenkins_build_job_url = ENV["BUILD_URL"]
    jenkins_username = ENV[$SMF_JENKINS_UI_TEST_USER_USERNAME]
    jenkins_password = ENV[$SMF_JENKINS_UI_TEST_USER_PASSWORD]

    jenkins_build_job_url = jenkins_build_job_url.gsub("http://", "http://#{jenkins_username}:#{jenkins_password}@")
    jenkins_build_job_url = jenkins_build_job_url.gsub("https://", "https://#{jenkins_username}:#{jenkins_password}@")

    sh "curl -X POST #{jenkins_build_job_url}stop"

    next
  end 

  # First download the provisioning profiles. We don't nee to continue if they aren't valid
  smf_download_provisioning_profiles_if_needed

  simulator_build_asset_path = smf_download_asset($SMF_SIMULATOR_RELEASE_APP_ZIP_FILENAME, assets, github_token)

  device_build_asset_path = smf_download_asset($SMF_DEVICE_RELEASE_APP_ZIP_FILENAME, assets, github_token)

  smf_perform_all_ui_tests(
    simulators: simulators,
    simulator_build_asset_path: simulator_build_asset_path,
    device_build_asset_path: device_build_asset_path,
    report_name: report_name,
    report_sync_destination: report_sync_destination
  )
end

################################
### smf_perform_all_ui_tests ###
################################

desc "Peforms the UI-Tests on the given simulators and all attached Devices"
lane :smf_perform_all_ui_tests do |options|

  # Parameters
  simulator_build_asset_path = options[:simulator_build_asset_path]
  device_build_asset_path = options[:device_build_asset_path]
  report_name = options[:report_name]
  report_sync_destination = options[:report_sync_destination]
  simulators = options[:simulators].split(',').map{ |x| x.gsub('\n', '') }

  # Variables
  bundle_identifier = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]["ui_test.target.bundle_identifier".to_sym]

  smf_install_pods_if_project_contains_podfile

  # Add the simulators to the destinations and install the app which should be tested

  smf_shutdown_simulators

  destinations = simulators.map{ |x| "platform=iOS Simulator,name=#{x}" }

  smf_install_app_on_simulators(simulators, simulator_build_asset_path)

  UI.message("Created destination: \"#{destinations}\" from simulators: \"#{simulators}\"")

  # Add the real devices to the destinations and install the app which should be tested

  udids = []
  sh("cfgutil list").split("\n").map{ |device_description_line|
    if device_description_line.include? "UDID:"
      device_udid = device_description_line.match("UDID: ([^\s]+) ")[1]
      udids.push(device_udid)
    end
  }.uniq

  UI.message("Attached devices: #{udids}")

  if udids.length == 0
    UI.important("No Devices found")
  else 
    begin

      # Install the app on the devices
      smf_install_app_on_devices(device_build_asset_path)

      destinations = destinations + udids.map{ |x| "platform=ios,id=#{x.gsub('\n', '')}" }

    rescue => exception
      UI.important("Installing on real devices failed, but the build job will continue. Error: #{exception}")
    end
  end

  UI.message("All destinations: #{destinations}")

  begin
    smf_perform_uitests_on_given_destinations(
      destinations: destinations,
      report_sync_destination: report_sync_destination,
      report_name: report_name,
      should_create_report: true,
      path_to_app: simulator_build_asset_path
      )

      smf_uninstall_app_on_simulators(simulators, bundle_identifier)
      smf_uninstall_app_on_devices(bundle_identifier)
  rescue => exception
    smf_uninstall_app_on_simulators(simulators, bundle_identifier)
    smf_uninstall_app_on_devices(bundle_identifier)

    raise exception
  end
end
