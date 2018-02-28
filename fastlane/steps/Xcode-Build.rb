fastlane_require 'net/https'
fastlane_require 'uri'
fastlane_require 'json'

#######################
### smf_archive_ipa ###
#######################

# options: build_variants_config (Hash), project_config (Hash), build_variant (String), use_sigh (string) [Optional], should_clean_project (String) [Optional]

desc "Build the project based on the build type."
private_lane :smf_archive_ipa do |options|

  UI.important("Build a new version")

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  build_variant = options[:build_variant].downcase
  build_variant_config = options[:build_variants_config]["targets"][build_variant]
  use_sigh = (options[:use_sigh].nil? ? true : options[:use_sigh])
  should_clean_project = (options[:should_clean_project].nil? ? true : options[:should_clean_project])
  icloud_environment = (build_variant_config["icloud_environment"].nil? ? "Development" : build_variant_config["icloud_environment"])
  upload_itc = (build_variant_config["upload_itc"].nil? ? false : build_variant_config["upload_itc"])
  upload_bitcode = (build_variant_config["upload_bitcode"].nil? ? true : build_variant_config["upload_bitcode"])
  export_method = (build_variant_config["export_method"].nil? ? nil : build_variant_config["export_method"])

  extensions_suffixes = options[:build_variants_config]["extensions_suffixes"]
  scheme = build_variant_config["scheme"]

  # Set the Apple Team ID
  team_id build_variant_config["team_id"]

  if use_sigh
    unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])

    is_adhoc_build = build_variant.include? "adhoc"

    sigh(
      adhoc: is_adhoc_build,
      skip_certificate_verification:true,
      app_identifier: build_variant_config["bundle_identifier"]
      )

    if extensions_suffixes
      for extension_suffix in extensions_suffixes do
        
        begin
          sigh(
            adhoc: is_adhoc_build,
            skip_certificate_verification:true,
            app_identifier: "#{build_variant_config["bundle_identifier"]}.#{extension_suffix}"
            )
        rescue
          UI.important("Seems like #{build_variant_config["bundle_identifier"]}.#{extension_suffix} is not yet included in this project! Skipping sigh!")
          next   
        end

      end
    end
  end

  unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])

  gym(
    clean: should_clean_project,
    workspace: "#{project_name}.xcworkspace",
    scheme: scheme,
    configuration: 'Release',
    codesigning_identity: build_variant_config["code_signing_identity"],
    output_directory: "build",
    archive_path:"build/",
    output_name: scheme,
    include_symbols: true,
    include_bitcode: (upload_itc && upload_bitcode),
    export_method: export_method,
    export_options: { iCloudContainerEnvironment: icloud_environment },
    xcpretty_formatter: "/Library/Ruby/Gems/2.3.0/gems/xcpretty-json-formatter-0.1.0/lib/json_formatter.rb"
    )

end

##############################
### smf_perform_unit_tests ###
##############################

# options: project_config (Hash), build_variant_config (Hash)

desc "Performs the unit tests of a project."
private_lane :smf_perform_unit_tests do |options|

  UI.important("Perform the unit tests")

  # Read options parameter
  project_config = options[:project_config]
  build_variant_config = options[:build_variant_config]

  # Prefer the unit test scheme over the normal scheme
  scheme = (build_variant_config["unit_test_schme"].nil? ? build_variant_config["scheme"] : build_variant_config["unit_test_schme"])

  scan(
    workspace: "#{project_config["project_name"]}.xcworkspace",
    scheme: scheme,
    clean: false,
    output_types: "html,junit,json-compilation-database",
    output_files: "report.xml,report.junit,report.json"
    )

end

##################################
### smf_increment_build_number ###
##################################

desc "increment build number"
private_lane :smf_increment_build_number do |options|

  UI.important("increment build number")

  project_name = options[:project_config]["project_name"]
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  increment_build_number(build_number: smf_get_incremented_build_number(version))

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

def smf_should_build_number_be_incremented(tag_prefixes = nil)

    if not ENV["SHOULD_INCREMENT_BUILD_NUMBER"].nil?
      UI.message("The SHOULD_INCREMENT_BUILD_NUMBER ENV was already set. Reusing #{ENV["SHOULD_INCREMENT_BUILD_NUMBER"]}")
      return ENV["SHOULD_INCREMENT_BUILD_NUMBER"] == "true"
    end

    # Check if the former commit was a build of the same build variant 
    unless tag_prefixes.nil?
      last_commit_tags_string = sh "git tag -l --points-at HEAD"
      for tag_prefix in tag_prefixes do
        if last_commit_tags_string.include? tag_prefix
          UI.message("Increment the build number as the former commit is a build of the same build variant. We have to increase it to avoid duplicate build numbers")
          ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "true"
          return ENV["SHOULD_INCREMENT_BUILD_NUMBER"]
        end
      end
    end

    last_commit = last_git_commit
    message = last_commit[:message]
    author = last_commit[:author]

    UI.message("The last commit was \"#{message}\" from #{author}")

    if message.include? smf_increment_build_number_prefix_string and author == "SMFHUDSONCHECKOUT"
      UI.message("Don't increment the build number as the last commit was a build number incrementation from Jenkins")
      ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "false"
    else
      UI.message("Increment the build number as the last commit wasn't a build number incrementation from Jenkins")
      ENV["SHOULD_INCREMENT_BUILD_NUMBER"] = "true"
    end

  return ENV["SHOULD_INCREMENT_BUILD_NUMBER"] == "true"

end

##############
### HELPER ###
##############

def smf_increment_build_number_prefix_string
  return "Increment build number to "
end

def is_bitcode_enabled(project_name, scheme)
  if not sh "pgrep Xcode"
    # Xcode isn't running, open it to avoid a hanging xcrun
    
    # Wait 10 seconds to let Xcode start properly
    sleep 10
  end

  enable_bitcode_string = sh "cd .. && xcrun xcodebuild -showBuildSettings -workspace\ \"#{project_name}.xcworkspace\" -scheme \"#{scheme}\" \| grep \"ENABLE_BITCODE = \" \| grep -o \"\\(YES\\|NO\\)\""
  return ((enable_bitcode_string.include? "NO") == false)
end
