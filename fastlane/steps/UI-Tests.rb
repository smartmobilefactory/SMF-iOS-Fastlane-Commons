#############################################
### perform_uitests_on_given_destinations ###
#############################################

desc "Performs the UI tests on all given destinations"
private_lane :smf_perform_uitests_on_given_destinations do |options|

  #Parameters
  destinations = options[:destinations]
  resultsPrefix = options[:resultsPrefix]
  should_create_report = (options[:should_create_report] != nil ? options[:should_create_report] : true)
  report_sync_destination = options[:report_sync_destination]
  report_name = options[:report_name]

  # Variables
  scheme = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]

  begin

    if smf_is_jenkins_environment
      unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
    end

    scan(
      scheme: scheme,
      destination: destinations,
      derived_data_path: "./DerivedData"
      )
  rescue => exception
    UI.important("Failed to perform the unit tests, exception: #{exception}")

    if should_create_report
      smf_create_and_sync_report("/../DerivedData", "#{Dir.pwd}/..", report_sync_destination, report_name)
      next
    else
      raise exception
    end
  end

  if should_create_report
    smf_create_and_sync_report("/../DerivedData", "#{Dir.pwd}/..", report_sync_destination, report_name)
  end
end

##############
### Helper ###
##############

def smf_create_and_sync_report(derivedDataURL, results_directory, report_sync_destination, report_name)
  results_foldername = "#{report_name} (#{Time.now.strftime("%Y-%m-%d %H:%M")})"

  reporting_tool = "#{@fastlane_commons_dir_path}/tools/ui-test-reporting.jar"

  # Create the report based on the derived data
  sh("java", "-jar", reporting_tool, Dir.pwd + derivedDataURL + "/Logs/Test", "\"#{results_directory}/#{results_foldername}\"", 400.to_s)

  # Wait for a short time. This is a try to avoid errors like "rsync error: some files/attrs were not transferred"
  sleep(10)

  # Zip the report
  sh("cd #{results_directory} && zip -r \"#{results_foldername}.zip\" \"#{results_foldername}\"")

  # Wait for a short time. This is a try to avoid errors like "rsync error: some files/attrs were not transferred"
  sleep(10)

  # Sync the report to HiDrive
  remote_path = "#{report_sync_destination}/#{results_foldername}"
  remote_path = remote_path.gsub!(" ", "\ ")
  sh("rsync -rltDvzre \"ssh\" \"#{results_directory}/#{results_foldername}.zip\" \"#{remote_path}.zip\"")
end

def smf_install_app_on_simulators(simulators, path_to_app)
  UI.message("Copying the APP \"#{path_to_app}\" to the simulators: \"#{simulators}\"")

  simulators.each { |simulator|
    sh "xcrun simctl boot '#{simulator}' || true"
    sh "xcrun simctl install '#{simulator}' #{path_to_app} || true"
  }
end

def smf_uninstall_app_on_simulators(simulators, bundle_identifier)
  UI.message("Removing the APP \"#{bundle_identifier}\" from the simulators: \"#{simulators}\"")

  simulators.each { |simulator|
    sh "xcrun simctl boot '#{simulator}' || true"
    sh "xcrun simctl uninstall '#{simulator}' #{bundle_identifier} || true"
  }
end

def smf_install_app_on_devices(path_to_app)
  UI.message("Copying the IPA \"#{path_to_app}\"to all connected devices")

  connected_devices = sh "cfgutil list"

  if connected_devices.length > 0
    sh "cfgutil -f install-app #{path_to_app}"

    UI.message("Waiting 60 seconds to let the devices time to install the app")
    sleep(60)
  end
end

def smf_uninstall_app_on_devices(bundle_identifier)
  UI.message("Removing the IPA \"#{bundle_identifier}\" from all connected devices")

  connected_devices = sh "cfgutil list"

  if connected_devices.length > 0
    sh "cfgutil -f remove-app #{bundle_identifier}"

    sleep(60)
  end

end
