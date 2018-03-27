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
  bundle_identifier = build_variant_config[:bundle_identifier]
  extensions_suffixes = build_variant_config[:extensions_suffixes]

  upload_itc = (build_variant_config[:upload_itc].nil? ? false : build_variant_config[:upload_itc])
  upload_bitcode = (build_variant_config[:upload_bitcode].nil? ? true : build_variant_config[:upload_bitcode])
  
  export_method = (build_variant_config[:export_method].nil? ? nil : build_variant_config[:export_method])
  icloud_environment = (build_variant_config[:icloud_environment].nil? ? "Development" : build_variant_config[:icloud_environment])
  # Check if the project defined if the build should be cleaned. Other wise the default behavior is used based on the whether the archiving is a bulk operation.
  should_clean_project = bulk_deploy_params != nil ? (bulk_deploy_params[:index] == 0 && bulk_deploy_params[:count] > 1) : true
  if build_variant_config[:should_clean_project] != nil
    should_clean_project = build_variant_config[:should_clean_project]
  end

  apple_team_id = build_variant_config[:team_id]
  use_sigh = (build_variant_config[:download_provisioning_profiles].nil? ? true : build_variant_config[:download_provisioning_profiles])
  code_signing_identity = build_variant_config[:code_signing_identity]

  # Set the Apple Team ID
  team_id apple_team_id

  if use_sigh
    if smf_is_jenkins_environment
      unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])
    end

    is_adhoc_build = @smf_build_variant.include? "adhoc"

    sigh(
      adhoc: is_adhoc_build,
      skip_certificate_verification:true,
      app_identifier: bundle_identifier
      )

    if extensions_suffixes
      for extension_suffix in extensions_suffixes do
        
        begin
          sigh(
            adhoc: is_adhoc_build,
            skip_certificate_verification:true,
            app_identifier: "#{bundle_identifier}.#{extension_suffix}"
            )
        rescue
          UI.important("Seems like #{bundle_identifier}.#{extension_suffix} is not yet included in this project! Skipping sigh!")
          next   
        end

      end
    end
  end

  if smf_is_jenkins_environment
    unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
  end

  gym(
    clean: should_clean_project,
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    configuration: 'Release',
    codesigning_identity: code_signing_identity,
    output_directory: "build",
    archive_path:"build/",
    output_name: scheme,
    include_symbols: true,
    include_bitcode: (upload_itc && upload_bitcode),
    export_method: export_method,
    export_options: { iCloudContainerEnvironment: icloud_environment },
    skip_package_ipa: skip_package_ipa,
    xcpretty_formatter: "/Library/Ruby/Gems/2.3.0/gems/xcpretty-json-formatter-0.1.0/lib/json_formatter.rb"
    )

end

##############################
### smf_perform_unit_tests ###
##############################

desc "Performs the unit tests of a project."
private_lane :smf_perform_unit_tests do |options|

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config[:unit_test_scheme].nil? ? build_variant_config[:scheme] : build_variant_config[:unit_test_scheme])

  UI.important("Performing the unit tests with the scheme \"#{scheme}\"")

  destination = (ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] == "mac" ? "platform=macOS,arch=x86_64" : nil)

  UI.message("Use destination \"#{destination}\" for platform \"#{ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY]}\"")

  scan(
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    clean: false,
    destination: destination,
    code_coverage: true,
    output_types: "html,xml,junit,json-compilation-database",
    output_files: "report.html,report.xml,report.junit,report.json"
    )

  ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY] = "true"

end

##################################
### smf_increment_build_number ###
##################################

desc "Increments the build number"
private_lane :smf_increment_build_number do |options|

  UI.important("increment build number")

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]

  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  increment_build_number(
    build_number: smf_get_incremented_build_number(version)
    )

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

  if message.include? smf_increment_build_number_prefix_string and author == "SMFHUDSONCHECKOUT"
    UI.message("Don't increment the build number as the last commit was a build number incrementation from Jenkins")
    ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] = "false"
  else
    UI.message("Increment the build number as the last commit wasn't a build number incrementation from Jenkins")
    ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] = "true"
  end

  return ENV[$SMF_SHOULD_BUILD_NUMBER_BE_INCREMENTED_ENV_KEY] == "true"
end

##############
### HELPER ###
##############

def smf_can_unit_tests_be_performed

  # Variables
  project_name = @smf_fastlane_config[:project][:project_name]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config[:unit_test_scheme].nil? ? build_variant_config[:scheme] : build_variant_config[:unit_test_scheme])

  UI.important("Checking whether the unit tests with the scheme \"#{scheme}\" can be performed.")

  destination = (ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] == "mac" ? "platform=macOS,arch=x86_64" : nil)

  UI.message("Use destination \"#{destination}\" for platform \"#{ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY]}\"")

  begin
    scan(
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    destination: destination,
    clean: false,
    skip_build: true,
    xcargs: "-dry-run"
    )

    UI.important("Unit tests can be performed")
    
    return true
  rescue => exception
    
    UI.important("Unit tests can't be performed: #{exception}")
    
    return false
  end

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
  return (@smf_fastlane_config[:build_variants][@smf_build_variant_sym][:podspec_path] != nil)
end
