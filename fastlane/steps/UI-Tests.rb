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
  path_to_app = options[:path_to_app]

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  scheme = build_variant_config[:scheme]
  buildlog_path = "#{smf_workspace_dir}/Scanlog"
  slack_channel = @smf_fastlane_config[:project][:slack_channel]
  disable_concurrent_testing = (build_variant_config[:disable_concurrent_testing] ? build_variant_config[:disable_concurrent_testing] : false)
  is_report_already_uploaded = false
  app_to_test = build_variant_config["ui_test.target.bundle_identifier".to_sym]

  # Setup APP_TO_TEST argument, if a bundle identifier was given
  if app_to_test != nil
    app_to_test = "APP_TO_TEST=#{app_to_test}"
  end


  if slack_channel
    smf_send_chat_message(
      title: "Starting to perform UI tests for #{report_name} 🔎",
      message: "It may take multiple hours until the report is completed. Enjoy life and check for new notifications later...",
      type: "message",
      slack_channel: slack_channel
      )
  end

  begin

    if smf_is_keychain_enabled
      unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])
      unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
    end

     # The derived data folder has to be deleted to support the testing of diferent apps. Otherwise the formerly tested app will be opened again
    sh "rm -r #{Dir.pwd}/../DerivedData || true"

    scan(
      scheme: scheme,
      destination: destinations,
      derived_data_path: "./DerivedData",
      buildlog_path: buildlog_path,
      disable_concurrent_testing: disable_concurrent_testing,
      xcargs: app_to_test
      )
  rescue => exception
    UI.important("Failed to perform the unit tests, exception: #{exception}")

    # Inspect the logs to see if the exception is due to failing tests or a failing building. A failed test (not complete testing, just single tests) isn't concidered as build job failure
    were_ui_tests_performed = false
    Dir.glob("#{buildlog_path}/*.log") { |file|
      filelines = File.readlines(file)
      if filelines.grep(/Running tests.../).size > 0 && filelines.grep(/Generating coverage data.../).size > 0
        UI.message("Found running tests and generating coverage data logs. We concider the tests as runned...")
        were_ui_tests_performed = true
      end
    }

    if should_create_report
      results_foldername = smf_create_and_sync_report("/../DerivedData", "#{Dir.pwd}/..", report_sync_destination, report_name, path_to_app)
      is_report_already_uploaded = true
    end

    if were_ui_tests_performed == false
      raise "The UI tests couldn't be executed. Check the build log for more information."
    end
  end

  notification_message = "The UI tests were performed"
  if should_create_report
    if is_report_already_uploaded == false
      results_foldername = smf_create_and_sync_report("/../DerivedData", "#{Dir.pwd}/..", report_sync_destination, report_name, path_to_app)
    end
    new_report_image_path = "../Report_#{report_name}.png"
    sh "mv \"../#{results_foldername}/screenshot.png\" \"#{new_report_image_path}\""
    attachment_path = new_report_image_path
    notification_message = "#{notification_message} and the report was uploaded to HiDrive. Check it for more details."
  else
    notification_message = "#{notification_message}. See the build log for more details"
  end

  smf_send_chat_message(
    title: "Done performing UI tests for #{report_name} ✍🏻",
    message: notification_message,
    type: "success",
    slack_channel: slack_channel,
    attachment_path: attachment_path
    )
end

##############
### Helper ###
##############

def smf_create_and_sync_report(derivedDataURL, results_directory, report_sync_destination, report_name, path_to_app)
	temp_results_foldername = "Results"
	results_foldername = "#{report_name} (#{Time.now.strftime("%Y-%m-%d %H:%M")})"

	reporting_tool = "#{@fastlane_commons_dir_path}/tools/ui-test-reporting.jar"

	def get_plist_value(plist_key, path_to_app)
		pwd = Dir.pwd
		path_to_plist = "#{pwd}/#{path_to_app}/Info"
		value = sh("defaults read #{path_to_plist} #{plist_key}")
		return value
	end

	# Create the report based on the derived data
	sh("java", "-jar", reporting_tool, Dir.pwd + derivedDataURL + "/Logs/Test", "#{results_directory}/#{temp_results_foldername}", 400.to_s, get_plist_value("CFBundleShortVersionString", path_to_app), get_plist_value("CFBundleVersion", path_to_app), get_plist_value("CFBundleName", path_to_app))

  # Wait for a short time. This is a try to avoid errors like "rsync error: some files/attrs were not transferred"
  sleep(10)

  # Zip the report
  sh("cd #{results_directory} && mv \"#{temp_results_foldername}\" \"#{results_foldername}\" && zip -r \"#{results_foldername}.zip\" \"#{results_foldername}\"")

  # Wait for a short time. This is a try to avoid errors like "rsync error: some files/attrs were not transferred"
  sleep(10)

  # Sync the report to HiDrive
  local_path = "#{results_directory}/#{results_foldername}.zip"
  remote_path = "#{report_sync_destination}/#{results_foldername}"
  remote_path = remote_path.gsub!(" ", "\\ ")
  sh("rsync -rltDvzre ssh -i \"#{local_path}\" \"#{remote_path}.zip\"")

  return results_foldername
end

def smf_shutdown_simulators()
  UI.message("Shutting down all simulators to save system resources.")
  sh "xcrun simctl shutdown all"
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

    UI.message("Waiting 90 seconds to let the devices time to install the app")
    sleep(90)
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
