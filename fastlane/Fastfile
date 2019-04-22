
@fastlane_commons_dir_path = File.expand_path(File.dirname(__FILE__))
@should_commons_repo_be_downloaded = (File.exist?("#{@fastlane_commons_dir_path}/flow") == false || File.exist?("#{@fastlane_commons_dir_path}/steps") == false)

#################
### Lifecycle ###
#################

before_all do |lane, options|
  puts "Inline options: #{options}"
  smf_setup_fastlane_commons(options)
end

desc "Called on success"
after_all do
  if @should_commons_repo_be_downloaded
    smf_remove_fastlane_commons_repo
  end
end

desc "Called on error"
error do |lane, exception|
  if @smf_set_should_send_deploy_notifications == true || @smf_set_should_send_build_job_failure_notifications == true
    smf_handle_exception(
      exception: exception,
      )
  end

  if @should_commons_repo_be_downloaded
    smf_remove_fastlane_commons_repo
  end
end

def smf_setup_fastlane_commons(options = Hash.new)
  # Load the Fastlane config from the disk into memory
  smf_load_fastlane_config

  # Clone the Commons Repo
  @fastlane_commons_dir_path = "#{smf_workspace_dir}/.fastlane-smf-commons"

  if @should_commons_repo_be_downloaded
    UI.message("Downloading Fastlane Commons Repo as it's not locally available yet")
    smf_remove_fastlane_commons_repo
    smf_clone_fastlane_commons_repo
  else
    UI.message("The Fastlane Commons Repo won't be downloaded as it's already available locally")
  end

  # Import the splitted Fastlane classes
  import_all "#{@fastlane_commons_dir_path}/fastlane/flow"
  import_all "#{@fastlane_commons_dir_path}/fastlane/steps"
  import_all "#{@fastlane_commons_dir_path}/fastlane/utils"

  # Setup build type options
  smf_setup_default_build_type_values

  # Override build type options by inline
  build_type = options[:build_type]
  smf_override_build_type_options_by_type(build_type)

  @smf_original_platform = ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY]
  puts "Original Platform #{@smf_original_platform}"
end

##############
### Helper ###
##############

def import_all(path)
  Dir["#{path}/*.rb"].each { |file|
    import file
  }
end

##############
### Config ###
##############

def smf_value_for_keypath_in_hash_map(hash_map, keypath)
  keys = keypath.split("/")
  value = hash_map
  for key in keys
    if value.key?(key.to_sym)
      value = value[key.to_sym]
    else
      raise "Error: Couldn't find keypath \"#{keypath}\" in \"#{hash_map}\""
    end
  end
  return value
end

def smf_load_fastlane_config
  config_path = fastlane_config_path
  UI.message("Reading the SMF Fastlane config from \"#{config_path}\"")
  config_file = File.read(config_path)
  if config_file
    @smf_fastlane_config ||= JSON.parse(config_file, :symbolize_names => true)
    UI.success("Parsed config file into the hash map")
  else
    raise "Error: The SMF Fastlane config file doesn't exist at path \"#{config_path}\""
  end
end

def smf_set_should_send_deploy_notifications(should_notify)
  @smf_set_should_send_deploy_notifications = should_notify
end

def smf_set_should_send_build_job_failure_notifications(should_notify)
  @smf_set_should_send_build_job_failure_notifications = should_notify
end

def smf_set_build_variant(build_variant, reset_build_variant_array = true)
  @smf_build_variant = build_variant.downcase
  @smf_build_variant_sym = @smf_build_variant.to_sym
  if reset_build_variant_array
    smf_set_build_variants_array(nil)
  end

  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  if build_variant_config == nil
    raise "Error: build variant \"#{@smf_build_variant}\" isn't declared in the configuration file."
  end

  # Override build type options if set in Config.json
  smf_override_build_type_options_by_variant_config(build_variant_config)

  # Modify the platform if needed
  platform = build_variant_config[:platform]
  if platform != nil
    # Change the platform to the declared one
    ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] = platform
  else
    # Reset the platform to one which was active in "befor_all" if no platform is specified
    ENV[$FASTLANE_PLATFORM_NAME_ENV_KEY] = @smf_original_platform
  end
end

def smf_set_build_variants_array(build_variants)
  @smf_build_variants_array = build_variants
end

def smf_set_build_variants_matching_regex(regex)
  all_build_variants = @smf_fastlane_config[:build_variants].keys
  matching_build_variants = all_build_variants.grep(/#{regex}/).map(&:to_s)

  UI.important("Found matching build variants: #{matching_build_variants}")

  smf_set_build_variants_array(matching_build_variants)
end

def smf_set_bump_type(bump_type)
  @smf_bump_type = bump_type
end

def smf_set_git_branch(branch)
  @smf_git_branch = branch
end

####################
### Commons Repo ###
####################

private_lane :smf_clone_fastlane_commons_repo do
  fastlane_commons_branch = @smf_fastlane_config[:project][:fastlane_commons_branch]
  sh "git clone -b \"" + fastlane_commons_branch + "\" git@github.com:smartmobilefactory/SMF-iOS-Fastlane-Commons.git #{@fastlane_commons_dir_path}"
end

private_lane :smf_remove_fastlane_commons_repo do
  sh "if [ -d #{@fastlane_commons_dir_path} ]; then rm -rf #{@fastlane_commons_dir_path}; fi"
end

#####################################################
### Helper (needed without commons repo available)###
#####################################################

def smf_setup_default_build_type_values
  smf_set_slack_enabled(true)
  smf_set_keychain_enabled(true)
end

def smf_override_build_type_options_by_variant_config(build_variant_config)
  is_slack_enabled = (build_variant_config[:slack_enabled].nil? ? smf_is_slack_enabled : build_variant_config[:slack_enabled])
  is_keychain_enabled = (build_variant_config[:keychain_enabled].nil? ? smf_is_keychain_enabled : build_variant_config[:keychain_enabled])

  puts "Overriding build type options:\n slack_enabled: #{is_slack_enabled}\n keychain_enabled: #{is_keychain_enabled}"

  smf_set_slack_enabled(is_slack_enabled)
  smf_set_keychain_enabled(is_keychain_enabled)
end

def smf_override_build_type_options_by_type(build_type)
  if not build_type.nil?
    puts "Overriding build type options with build type: #{build_type}"
    if build_type == "local"
      smf_set_keychain_enabled(false)
    elsif build_type == "quiet"
      smf_set_slack_enabled(false)
    elsif build_type == "develop"
      smf_set_slack_enabled(false)
      smf_set_keychain_enabled(false)
    end
  end
end

def smf_is_jenkins_environment
  return ENV["JENKINS_URL"]
end

def smf_set_slack_enabled(value)
  newValue = value ? "true" : "false"
  return ENV[$SMF_IS_SLACK_ENABLED] = newValue
end

def smf_is_slack_enabled
  return ENV[$SMF_IS_SLACK_ENABLED].nil? ? true : ENV[$SMF_IS_SLACK_ENABLED] == "true"
end

def smf_set_keychain_enabled(value)
  newValue = value ? "true" : "false"
  return ENV[$SMF_IS_KEYCHAIN_ENABLED] = newValue
end

def smf_is_keychain_enabled
  return ENV[$SMF_IS_KEYCHAIN_ENABLED].nil? ? true : ENV[$SMF_IS_KEYCHAIN_ENABLED] == "true"
end

def smf_workspace_dir
  path = "#{Dir.pwd}"
  if path.end_with?("/fastlane")
    path = path.chomp("/fastlane")
  end
  return path
end

def ci_ios_error_log
  return "#{$SMF_CI_IOS_ERROR_LOG}"
end

def slack_url
  return "#{$SMF_SLACK_URL}"
end
