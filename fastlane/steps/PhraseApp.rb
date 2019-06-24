########################################
### smf_sync_strings_with_phrase_app ###
########################################

desc "Snycs the Strings with PhraseApp if the build variant declared a PhraseApp script"
private_lane :smf_sync_strings_with_phrase_app do |options|

  should_sync_with_phrase_app_using_config = (@smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app] != nil)
  errors_occured = false

  if (should_sync_with_phrase_app_using_config == true)
    initialize_env_variable_name_mappings
    UI.message("Strings are synced with PhraseApp using the values from the fastlane/Config.json")
    valid_entries = validate_and_set_phrase_app_env_variables

    if (valid_entries == false)
      UI.error("Failed to sync Strings with PhraseApp (using the Config.json): check fastlane/Config.json \"phrase_app\" entries!")
      errors_occured = true
    end

    phrase_app_scripts_path = nil

    if (errors_occured == false)
      UI.message("Starting to clone Phraseapp-CI scripts...")
      phrase_app_scripts_path = clone_phraseapp_ci
      errors_occured = (phrase_app_scripts_path == nil)
    end

    if (errors_occured == false)
      UI.message("Successfully downloaded phrase app scripts, running scripts...")
      sh "if #{phrase_app_scripts_path}/push.sh; then #{phrase_app_scripts_path}/pull.sh || true; fi"

      UI.message("Ran scripts.. checking for extensions...")
      extensions = check_for_extensions_and_validate
        
      if (extensions == [])
          UI.message("There are no extension entries..")
      else 
        UI.message("Found extensions...")
        extensions.each do |extension|
          if (extension != nil)
            setup_environtment_variables_for_extension(extension)
            sh "if #{phrase_app_scripts_path}/push.sh; then #{phrase_app_scripts_path}/pull.sh || true; fi"
          elsif
            UI.message("Skipping invalid extension.. look in the Config.json if all extension have the mandatory entries.")
          end
        end
      end

      UI.message("Finished executing phrase app scripts for extensions...")
      UI.message("Deleting phrase app ci scripts...")
      clean_up_phraseapp_ci(phrase_app_scripts_path)
    end
  end

  if (should_sync_with_phrase_app_using_config == false || errors_occured)

    phrase_app_script = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app_script]
    if phrase_app_script
      UI.message("String are synced with PhraseApp using the script \"phrase_app_script\"")
  
      begin
        sh "#{smf_workspace_dir}/#{phrase_app_script} #{@smf_git_branch}"
      rescue => e
        UI.error("Failed to sync Strings with PhraseApp: #{e.message}")
  
        smf_send_chat_message(
          title: "Failed to sync Strings with PhraseApp for #{smf_default_notification_release_title} 😢",
          message: "The build job will continue but won't contain updated translations!",
          exception: e,
          type: "warning",
          slack_channel: @smf_fastlane_config[:project][:slack_channel]
        )
      end
    else
      UI.important("String are not synced with PhraseApp as the build variant didn't declare a \"phrase_app_script\"")
    end
  end

end

##########################################################################
############## PHRASEAPP SETUP USING FASTLANE/CONFIG.JSON. ###############
##########################################################################

###################### GENERAL SETUP ##########################

# Mapps the keys of the fastlane/Config.json to the env. variable names of the phrase app script
# the boolean value indicates whether the value is optional or not
# for default values a third entry in the array can be provided

def initialize_env_variable_name_mappings
  @phrase_app_config_keys_env_variable_mapping = {
    :access_token_key           => ["phraseappAccessToken", true, "SMF_PHRASEAPP_ACCESS_TOKEN"], # optional
    :project_id                 => ["phraseappProjectId", false],
    :source                     => ["phraseappSource", false],
    :locales                    => ["phraseappLocales", false],
    :format                     => ["phraseappFormat", false],
    :base_directory             => ["phraseappBasedir", false],
    :files                      => ["phraseappFiles", false],
    :git_branch                 => ["phraseappGitBranch", true, @smf_git_branch],  # optional, defaults to @smf_git_branch
    :files_prefix               => ["phraseappFilesPrefix", true, ""], # optional
    :forbid_comments_in_source  => ["phraseappForbidCommentsInSource", true, "1"]  # optional
  }
end

# Validates that all necessary values are present in the fastlane/Config.json
# if a none optional value is missing, no env are set and false is returned
# otherwise the environment variables are set and true is returned
def validate_and_set_phrase_app_env_variables
  export_env_key_value_pairs = {}

  UI.message("Checking if all necessary values for the phrase app script are present in the Config.json...")

  @phrase_app_config_keys_env_variable_mapping.each do |key, value|
    result = validate_phrase_app_variable(key, value[1])
    if (result == nil)
      return false
    end

    export_env_key_value_pairs[value[0]] = result
  end

  UI.message("Successfully checked values necessary for phrase app script 🎉")
  UI.message("Setting environment variables...")

  export_dict_as_env_variables(export_env_key_value_pairs)

  return true
end

# Checks if the value for a given key exists in the fastlane config.json file,
# if the value doesn't exist and the value is mandatory it returns nil
# if the value doesnt' exist and the value is optional it returns the default value
# otherwise it returns the value found for the given key.
def validate_phrase_app_variable(key, optional)
  value = get_phrase_app_value_for(key)
  if (value == nil) && (optional == false)
    UI.error("Failed to get phraseapp value for key #{key} in config.json")
    return nil
  elsif (value == nil) && (optional == true)
    UI.message("Couldn't find value for key #{key}, for the phrase-app script. Default is: \"#{@phrase_app_config_keys_env_variable_mapping[key][2]}\"")
    return @phrase_app_config_keys_env_variable_mapping[key][2]
  elsif (value != nil)
    value = transform_value_if_necessary(key, value)
    UI.message("Phrase script value for key #{key} is #{value}")
    return value
  end

  return nil
end

######################### HANDLE EXTENSIONS ##########################

# Checks if there are any extensions to run the phrase app scripts with
# and validates that all necessary entries are present
# returns an array with extensions if valid ones are found
# invalid ones are put as nil into the array
# otherwise returns an emtpy array if no extensions are present
def check_for_extensions_and_validate
  extensions = get_phrase_app_value_for(:extensions)
  validated_extensions = []
  if (extensions != nil) && (extensions.length != 0)
    extensions.each do |extension|
      validated_extension = validate_extension(extension)
      validated_extensions.push(validated_extension)
      
      if (validated_extension == nil)
        UI.error("Error validating an extension entry in the fastlane/Config.json for the phrase app script")
      end
    end
  end

  return validated_extensions
end

# Goes through all the values in an extension
# and checks if they are present, if one is missing it returns nil
# otherwise it returns a dict with transformed key/values to be exported as env variables
def validate_extension(extension)
  exportable_extension = {}
  important_keys = [:project_id, :base_directory, :files]

  important_keys.each do |key|
    value = extension[key]
    env_key = @phrase_app_config_keys_env_variable_mapping[key][0]
    if (value == nil || env_key == nil)
      UI.error("Error validating a value in an extension...")
      return nil
    else
      value = transform_value_if_necessary(key, value)
      exportable_extension[env_key] = value
    end
  end

  return exportable_extension
end

def setup_environtment_variables_for_extension(extension)
  export_dict_as_env_variables(extension)
end

############################# GIT AND GETTING THE PRHASE APP SCRIPTS ###########

# clones the phrasapp ci repository into the current directory
# so the push and pull scripts can be used
# returns parent directory of the push/pull scripts on success
# returns nil on error
def clone_phraseapp_ci
  url = "git@github.com:smartmobilefactory/Phraseapp-CI.git"
  branch = "master"
  src_root = File.join(smf_workspace_dir, File.basename(url, File.extname(url)))
  if File.exists?(src_root)
    UI.error("Can't clone into #{src_root}, directory already exists. Can't download Phraseapp-CI scripts..")
    return nil
  end
  UI.message("Cloning #{url} branch: #{branch} into #{src_root}")
  `git clone #{url} #{src_root} -b #{branch} -q > /dev/null`
  if File.exists?(src_root) == false
    UI.error("Error while cloning into #{src_root}. Couldn't download Phraseapp-CI scripts..")
    return nil
  end
  return src_root
end

def clean_up_phraseapp_ci(path)
  sh "rm -rf #{path}"
end

############################# HELPERS #################################

# Transform value to correct format to export as env variable
def transform_value_if_necessary(key, value)
  case key
  when :access_token_key
    if value != "SMF_PHRASEAPP_ACCESS_TOKEN"
      return ENV["CUSTOM_PHRASE_APP_TOKEN"]
    else
      return ENV["SMF_PHRASEAPP_ACCESS_TOKEN"]
    end
  when :locales, :files
    return value.join(" ")
  when :forbid_comments_in_source
    if (value == true)
      return "1"
    else
      return "0"
    end
  else
    return value
  end
end

# Tries to get the value for the given key in the fastlane/Config.json
# if it doesn't exist it returns nil
def get_phrase_app_value_for(key)
  return @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app][key]
end

# export dict as environment variables
def export_dict_as_env_variables(dict)
  dict.each do |key, value|
    if (value != nil)
      ENV[key] = value
    end
  end
end