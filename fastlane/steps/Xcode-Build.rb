#############################################
### smf_archive_ipa_if_scheme_is_provided ###
#############################################

desc "Archives the IPA if the build variant declared a scheme"
private_lane :smf_archive_ipa_if_scheme_is_provided do |options|

  # Parameter
  skip_export = (options[:skip_export].nil? ? false : options[:skip_export])
  bulk_deploy_params = options[:bulk_deploy_params]

  if @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]
    smf_archive_ipa(
      skip_export: skip_export,
      bulk_deploy_params: bulk_deploy_params
      )
  else
    UI.important("The IPA won't be archived as the build variant doesn't contain a scheme")
  end
end

#######################
### smf_archive_ipa ###
#######################

desc "Creates an archive of the current build variant."
private_lane :smf_archive_ipa do |options|

  UI.important("Creating the Xcode archive")

  # Parameter
  skip_package_ipa = (options[:skip_export].nil? ? false : options[:skip_export])
  bulk_deploy_params = options[:bulk_deploy_params]

  # Variables

  project_name = @smf_fastlane_config[:project][:project_name]
  
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  scheme = build_variant_config[:scheme]

  upload_itc = (build_variant_config[:upload_itc].nil? ? false : build_variant_config[:upload_itc])
  upload_bitcode = (build_variant_config[:upload_bitcode].nil? ? true : build_variant_config[:upload_bitcode])

  use_xcconfig = build_variant_config[:xcconfig_name].nil? ? false : true
  xcconfig_name = use_xcconfig ? build_variant_config[:xcconfig_name][:archive] : "Release"
  output_name = scheme
  
  export_method = (build_variant_config[:export_method].nil? ? nil : build_variant_config[:export_method])
  icloud_environment = (build_variant_config[:icloud_environment].nil? ? "Development" : build_variant_config[:icloud_environment])
  # Check if the project defined if the build should be cleaned. Other wise the default behavior is used based on the whether the archiving is a bulk operation.
  should_clean_project = bulk_deploy_params != nil ? (bulk_deploy_params[:index] == 0 && bulk_deploy_params[:count] > 1) : true
  if build_variant_config[:should_clean_project] != nil
    should_clean_project = build_variant_config[:should_clean_project]
  end

  code_signing_identity = build_variant_config[:code_signing_identity]

  use_sparkle = (build_variant_config[:use_sparkle].nil? ? false : build_variant_config[:use_sparkle])

  smf_download_provisioning_profiles_if_needed

  if smf_is_keychain_enabled
    unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
  end

  smf_setup_correct_xcode_executable_for_build

  gym(
    clean: should_clean_project,
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    configuration: xcconfig_name,
    codesigning_identity: code_signing_identity,
    output_directory: "build",
    xcargs: smf_xcargs_for_build_system,
    archive_path:"build/",
    output_name: output_name,
    include_symbols: true,
    include_bitcode: (upload_itc && upload_bitcode),
    export_method: export_method,
    export_options: { iCloudContainerEnvironment: icloud_environment },
    skip_package_ipa: skip_package_ipa,
    xcpretty_formatter: "/Library/Ruby/Gems/2.3.0/gems/xcpretty-json-formatter-0.1.0/lib/json_formatter.rb"
    )

  if use_sparkle
    smf_create_dmg_from_app
  end
end

###############################
### smf_build_simulator_app ###
###############################

desc "Creates a Release build for simulators"
private_lane :smf_build_simulator_app do |options|

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  build_type = "Release"
  workspace = smf_workspace_dir

  derived_data_path = "#{workspace}/simulator-build/derivedData"
  output_directory_path = "#{derived_data_path}/Build/Products/#{build_type}-iphonesimulator"
  output_filename = "#{build_variant_config[:scheme]}.app"

  sh "cd #{workspace}; xcodebuild -workspace #{project_name}.xcworkspace -scheme #{build_variant_config[:scheme]} -configuration #{build_type} -arch x86_64 ONLY_ACTIVE_ARCH=NO -sdk iphonesimulator -derivedDataPath #{derived_data_path}"

  # Compress the .app and copy it to the general build folder
  sh "cd \"#{output_directory_path}\"; zip -r \"#{output_filename}.zip\" \"#{output_filename}\"/*"
  sh "cp \"#{output_directory_path}/#{output_filename}.zip\" #{workspace}/build/SimulatorBuild#{build_type}.zip"

end



##############################
### smf_perform_unit_tests ###
##############################

desc "Performs the unit tests of a project."
private_lane :smf_perform_unit_tests do |options|

  should_perform_tests = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]["pr.perform_unit_tests".to_sym]

  if (should_perform_tests == false)
    UI.message("Build Variant \"#{@smf_build_variant}\" is not allowed to perform Unit Tests")
    return
  end

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  device = build_variant_config["tests.device_to_test_against".to_sym]
  use_xcconfig = build_variant_config[:xcconfig_name].nil? ? false : true
  xcconfig_name = use_xcconfig ? build_variant_config[:xcconfig_name][:unittests] : nil

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config[:unit_test_scheme].nil? ? build_variant_config[:scheme] : build_variant_config[:unit_test_scheme])

  UI.important("Performing the unit tests with the scheme \"#{scheme}\"")

  destination = (ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] == "mac" ? "platform=macOS,arch=x86_64" : nil)

  UI.message("Use destination \"#{destination}\" for platform \"#{ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY]}\"")

  scan(
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    xcargs: smf_xcargs_for_build_system,
    clean: false,
    device: device,
    destination: destination,
    configuration: xcconfig_name,
    code_coverage: true,
    output_types: "html,junit,json-compilation-database",
    output_files: "report.html,report.junit,report.json"
    )

  ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY] = "true"

end

##################################
### smf_increment_build_number ###
##################################

desc "Increments the build number"
private_lane :smf_increment_build_number do |options|

  UI.important("increment build number")

  version = smf_current_build_number

  increment_build_number(
    build_number: smf_get_incremented_build_number(version)
    )

end

##################################
### smf_decrement_build_number ###
##################################

desc "Decrement the build number"
private_lane :smf_decrement_build_number do |options|

  if smf_should_build_number_be_reverted
    UI.important("decrement build number")
    version = smf_previous_build_number

    increment_build_number(
      build_number: version
      )
  end

end

##########################################################
###   check build number whether it's a int or float   ###
##########################################################

def smf_get_incremented_build_number(version)

  if version.to_s.include? "."
    
   parts = version.to_s.split(".")
   count = parts.count

   incremented_version = parts[count - 1].to_i + 1

   version_string = ""

    for i in 0..count-2
     version_string += parts[i].to_s + "."
    end

   version_string += incremented_version.to_s

  else 
   version_string = version.to_i + 1

  end    

 return version_string.to_s

end

#################################################
###   smf_should_build_number_be_incremented  ###
#################################################

def smf_should_build_number_be_incremented

  if not ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY].nil?
    UI.message("The ENV #{$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY} was already set. Reusing #{ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY]}")
    return ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] == "true"
  end

  # Check if the former commit was a build of the same build variant 
  tag_matching_pattern = smf_construct_default_tag_for_current_project(".*")
  last_commit_tags_string = sh "git tag -l --points-at HEAD"
  if last_commit_tags_string.match(tag_matching_pattern)
    UI.message("Increment the build number as the former commit is a build of the same build variant. We have to increase it to avoid duplicate build numbers")
    ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] = "true"
    return ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY]
  end

  last_commit = last_git_commit
  message = last_commit[:message]
  author = last_commit[:author]

  UI.message("The last commit was \"#{message}\" from #{author}")
  ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] = "true"
  UI.message("Will increment the build number ...")

  return ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] == "true"
end

##############
### HELPER ###
##############

def smf_xcargs_for_build_system
  return smf_is_using_old_build_system ? "" : "-UseNewBuildSystem=YES"
end

def smf_is_using_old_build_system
  project_root = smf_workspace_dir

  if (project_root== nil)
    return false
  end

  workspace_file = `cd #{project_root} && ls | grep -E "(.|\s)+\.xcworkspace"`.gsub("\n", "")

  if (workspace_file == "" || workspace_file == nil)
    return false
  end

  file_to_search = File.join(project_root, "#{workspace_file}/xcshareddata/WorkspaceSettings.xcsettings")

  if (File.exist?(file_to_search) == false)
    return false
  end

  file_to_search_opened = File.open(file_to_search, "r")
  contents = file_to_search_opened.read

  regex = /<dict>\n\t<key>BuildSystemType<\/key>\n\t<string>Original<\/string>\n<\/dict>/

  if (contents.match(regex) != nil)
    return true
  end
end

def smf_setup_correct_xcode_executable_for_build
  # Make sure that the correct xcode version is selected when building the app
  required_xcode_version = @smf_fastlane_config[:project][:xcode_version]
  xcode_executable_path = smf_xcode_executable_path_for_version(required_xcode_version)
  
  puts "SELECTED XCODE EXECUTABLE: #{xcode_executable_path}"
  ENV[$DEVELOPMENT_DIRECTORY_KEY] = xcode_executable_path

  xcode_select(xcode_executable_path)
  ensure_xcode_version(version: required_xcode_version)
end

def smf_xcode_executable_path_for_version(xcode_version)
  return "#{$XCODE_EXECUTABLE_PATH_PREFIX}" + xcode_version + "#{$XCODE_EXECUTABLE_PATH_POSTFIX}"
end

def smf_set_should_revert_build_number(value)
  newValue = value ? "true" : "false"
  ENV[$SMF_SHOULD_REVERT_BUILD_NUMBER] = newValue
end

def smf_should_build_number_be_reverted
  return ENV[$SMF_SHOULD_REVERT_BUILD_NUMBER] == "true"
end

def smf_current_build_number
  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  return version
end

def smf_store_current_build_number
  version = smf_current_build_number
  smf_set_previous_build_number(version)
end

def smf_set_previous_build_number(version)
  ENV[$SMF_PREVIOUS_BUILD_NUMBER] = version
end

def smf_previous_build_number
  return ENV[$SMF_PREVIOUS_BUILD_NUMBER]
end

def smf_can_unit_tests_be_performed

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config[:unit_test_scheme].nil? ? build_variant_config[:scheme] : build_variant_config[:unit_test_scheme])

  use_xcconfig = build_variant_config[:xcconfig_name].nil? ? false : true
  xcconfig_name = use_xcconfig ? build_variant_config[:xcconfig_name][:unittests] : nil

  UI.important("Checking whether the unit tests with the scheme \"#{scheme}\" can be performed.")

  destination = (ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] == "mac" ? "platform=macOS,arch=x86_64" : nil)

  UI.message("Use destination \"#{destination}\" for platform \"#{ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY]}\"")

  begin
    scan(
      workspace: "#{project_name}.xcworkspace",
      scheme: scheme,
      destination: destination,
      configuration: xcconfig_name,
      clean: false,
      skip_build: true,
      xcargs: "-dry-run #{smf_xcargs_for_build_system}"
    )

    UI.important("Unit tests can be performed")
    
    return true
  rescue => exception
    
    UI.important("Unit tests can't be performed: #{exception}")
    
    return false
  end

end

def smf_is_build_variant_internal
  return (@smf_build_variant.include? "alpha") || smf_is_build_variant_a_pod
end

def smf_increment_build_number_prefix_string
  return "Increment build number to "
end

def smf_is_bitcode_enabled
  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  scheme = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]

  enable_bitcode_string = sh "cd .. && xcrun xcodebuild -showBuildSettings -workspace\ \"#{project_name}.xcworkspace\" -scheme \"#{scheme}\" \| grep \"ENABLE_BITCODE = \" \| grep -o \"\\(YES\\|NO\\)\""
  return ((enable_bitcode_string.include? "NO") == false)
end

def smf_is_build_variant_a_pod
  is_pod = (@smf_fastlane_config[:build_variants][@smf_build_variant_sym][:podspec_path] != nil)

  UI.message("Build variant is a pod: #{is_pod}, as the config is #{@smf_fastlane_config[:build_variants][@smf_build_variant_sym]}")

  return is_pod
end

def smf_is_build_variant_a_decoupled_ui_test
  is_ui_test = (@smf_fastlane_config[:build_variants][@smf_build_variant_sym][:"ui_test.target.bundle_identifier".to_sym] != nil)

  UI.message("Build variant is a is_ui_test: #{is_ui_test}, as the config is #{@smf_fastlane_config[:build_variants][@smf_build_variant_sym]}")

  return is_ui_test
end

def smf_create_dmg_from_app

  if ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] != "mac"
    raise "Wrong platform configuration: dmg's are only created for macOS apps."
  end

  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  code_signing_identity = build_variant_config["team_id".to_sym]
  app_path = smf_path_to_ipa_or_app

  # Create the dmg with the script and store it in the same directory as the app
  sh "#{@fastlane_commons_dir_path}/tools/create_dmg.sh -p #{app_path} -ci #{code_signing_identity}"

end

def smf_path_to_ipa_or_app
  
  # Variables
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  project_name = @smf_fastlane_config[:project][:project_name]
  escaped_filename = build_variant_config[:scheme].gsub(" ", "\ ")

  app_path = Pathname.getwd.dirname.to_s + "/build/#{escaped_filename}.app.zip"
  if ( ! File.exists?(app_path))
     app_path =  Pathname.getwd.dirname.to_s + "/build/#{escaped_filename}.app"
  end

  UI.message("Constructed path \"#{app_path}\" from filename \"#{escaped_filename}\"")

  unless File.exist?(app_path)
      app_path = lane_context[SharedValues::IPA_OUTPUT_PATH]

      UI.message("Using \"#{app_path}\" as app_path as no file exists at the constructed path.")
  end

  return app_path
end

def smf_get_version_number
  project_name = @smf_fastlane_config[:project][:project_name]
  scheme = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]
  target = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:target]

  version_number = get_version_number(
    xcodeproj: "#{project_name}.xcodeproj",
    target: (target != nil ? target : scheme)
    )

  return version_number
end

def smf_download_provisioning_profiles_if_needed

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  use_sigh = (build_variant_config[:download_provisioning_profiles].nil? ? true : build_variant_config[:download_provisioning_profiles])

  if use_sigh

    bundle_identifier = build_variant_config[:bundle_identifier]
    use_wildcard_signing = build_variant_config[:use_wildcard_signing]
    extensions_suffixes = @smf_fastlane_config[:extensions_suffixes]
    apple_team_id = build_variant_config[:team_id]

    # Set the Apple Team ID
    team_id apple_team_id

    if smf_is_keychain_enabled
      unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])
      unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
    end

    is_adhoc_build = @smf_build_variant.include? "adhoc"
    app_identifier = (use_wildcard_signing == true ? "*" : bundle_identifier)

    begin
      sigh(
        adhoc: is_adhoc_build,
        app_identifier: app_identifier,
        readonly: true
        )
    rescue => exception
      raise "Couldn't download the provisioning profiles. The profile did either expire or there is no matching certificate available locally."
    end

    if extensions_suffixes
      for extension_suffix in extensions_suffixes do
        
        begin
          sigh(
            adhoc: is_adhoc_build,
            app_identifier: "#{bundle_identifier}.#{extension_suffix}",
            readonly: true
            )
        rescue
          UI.important("Seems like #{bundle_identifier}.#{extension_suffix} is not yet included in this project! Skipping sigh!")
          next   
        end

      end
    end
  end
end
