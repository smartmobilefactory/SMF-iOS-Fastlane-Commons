################################################
### smf_perform_ui_tests_from_github_webhook ###
################################################

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
  ui_test_triggering_github_releases = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:ui_test_triggering_github_releases]

  unless tag_name =~ /#{Regexp.quote(ui_test_triggering_github_releases)}/
    UI.important("Release \"#{tag_name}\" is not eligible to be tested. Only tags matching \"#{ui_test_triggering_github_releases}\" are allowed.")
    # Stop the execution of this lane
    next
  end 

  simulator_build_asset_url = assetForSimulatorReleaseBuild(assets)
  simulator_build_asset_path = downloadApp(simulator_build_asset_url, github_token)

  device_build_asset_url = assetForDeviceReleaseBuild(assets)
  device_build_asset_path = downloadAppForDevices(device_build_asset_url, github_token)

  smf_perform_all_ui_tests(
    simulators: simulators,
    simulator_build_asset_path: simulator_build_asset_path,
    device_build_asset_path: device_build_asset_path,
    report_name: tag_name,
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
  simulators = options[:simulators]

  smf_install_pods_if_project_contains_podfile

  # Add the simulators to the destinations and install the app which should be tested

  destinations = simulators.split(',').map{ |x| "platform=iOS Simulator,name=#{x.gsub('\n', '')}" }

  smf_install_app_on_simulators(destinations, simulator_build_asset_path)

  UI.message("Chosen simulators: #{destinations}")

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
      smf_install_app_on_devices(udids, device_build_asset_path)

      destinations = destinations + udids.map{ |x| "platform=ios,id=#{x.gsub('\n', '')}" }

    rescue => exception
      UI.important("Installing on real devices failed, but the build job will continue. Error: #{exception}")
    end
  end

  UI.message("All destinations: #{destinations}")

  smf_perform_uitests_on_given_destinations(
    destinations: destinations,
    report_sync_destination: report_sync_destination,
    report_name: report_name,
    should_create_report: true
    )

end
