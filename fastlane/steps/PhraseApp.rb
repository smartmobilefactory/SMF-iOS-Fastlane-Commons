########################################
### smf_sync_strings_with_phrase_app ###
########################################

desc "Snycs the Strings with PhraseApp if the build variant declared a PhraseApp script"
private_lane :smf_sync_strings_with_phrase_app do |options|

  should_sync_with_phrase_app_using_config = (@smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app] != nil)
  errors_occured = false

  if (should_sync_with_phrase_app_using_config == true)

    UI.message("Strings are synced with PhraseApp using the values from the fastlane/Config.json")
    valid_entries = validate_and_set_phrase_app_env_variables

    if (valid_entries == false)
      UI.error("Failed to sync Strings with PhraseApp: check fastlane/Config.json \"phrase_app\" entries!")
      errors_occured = true
    else
      UI.message("Starting to clone Phraseapp-CI scripts..."
      phrase_app_scripts_path = clone_phraseapp_ci

      if (phrase_app_scripts_path != nil)
        UI.message("Successfully downloaded phrase app scripts, running scripts...")
        sh "if #{phrase_app_scripts_path}/push.sh; then #{phrase_app_scripts_path}/pull.sh || true; fi"

        UI.message("Ran scripts.. checking for extensions...")
        extensions = check_for_extensions_and_validate
        
        if (extensions == [])
          UI.message("There are no valid extension entries..")
        else 
          UI.message("Found valid extensions... running phrase app script for them")
          extensions.each do |extension|
            setup_environtment_variables_for_extension(extension)
            sh "if #{phrase_app_scripts_path}/push.sh; then #{phrase_app_scripts_path}/pull.sh || true; fi"
          end
          UI.message("Finished executing phrase app scripts for extensions...")
        end
        clean_up_phraseapp_ci(phrase_app_scripts_path)
      else
        errors_occured = true
      end
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

# Mapps the keys of the fastlane/Config.json to the env. variable names of for the phrase app script
# the boolean value indicates whether the value is optional or not
# for default values a third entry in the array can be provided
phrase_app_config_keys_env_variable_mapping = {
  :access_token_key           => ["phraseappAccessToken", false],
  :project_id                 => ["phraseappProjectId", false],
  :source                     => ["phraseappSource", false],
  :locales                    => ["phraseappLocales", false],
  :format                     => ["phraseappFormat", false],
  :base_directory             => ["phraseappBasedir", false],
  :files                      => ["phraseappFiles", false],
  :git_branch                 => ["phraseappGitBranch", true, "master"],  # optional, defaults to @smf_git_branch
  :force_update               => ["phraseappForceupdate", true],  # optional
  :files_prefix               => ["phraseappFilesPrefix", false],
  :forbid_comments_in_source  => ["phraseappForbidCommentsInSource", true, "1"]  # optional
}

# Validates that all necessary values are present in the fastlane/Config.json
# if a none optional value is missing, no env are set and false is returned
# otherwise the environment variables are set and true is returned
def validate_and_set_phrase_app_env_variables
  export_env_key_value_pairs = {}

  UI.message("Checking if all necessary values for the phrase app script are present in the Config.json...")

  phrase_app_config_keys_env_variable_mapping.each do |key, value|
    result = validate_phrase_app_variable(key, value[1])
    if (result == nil)
      return false
    elsif (result == "")
      result = value[2]
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
# if the value doesnt' exist and the value is optional it returns an empty string
# otherwise it returns the value found for the given key.
def validate_phrase_app_variable(key, optional)
  value = get_phrase_app_value_for(key)
  if (value == nil) && (optional == false)
    UI.error("Failed to get phraseapp value for key #{key}, running old phrase_app shell script")
    return nil
  elsif (value == nil) && (optional == true)
    UI.warning("Couldn't find value for key #{key}, for the phrase-app script. Keep going because the value is optional")
    return ""
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
# returns an array with extensions it valid ones are found
# otherwise returns an emtpy array
def check_for_extensions_and_validate
  extensions = get_phrase_app_value_for(:extensions)
  validated_extensions = []
  if (extensions != nil) && (extensions.length != 0)
    extensions.each do |extension|
      validated_extension = validate_extension(extension)
      if (validate_extension != nil)
        validated_extensions.push(validate_extension)
      else
        UI.error("Error validating an extension entry in the fastlane/Config.json for the phrase app script")
      end
    end
  end

  return validated_extensions
end

# Goes through all the values in an extension
# and checks if they are presend, if one is missing it returns nil
# otherwise it returns a dict with transformed key/values to be exported as env variables
def validate_extension(extension)
  exportable_extension = {}
  extension.each do |key, value|
    value = validate_phrase_app_variable(key, false)
    if (value == nil)
      return nil
    end

    key = phrase_app_config_keys_env_variable_mapping[key][0]
    if (key == nil)
      return nil
    end
    exportable_extension[key] = value
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
# return nil on error
def clone_phraseapp_ci
  url = "git@github.com:smartmobilefactory/Phraseapp-CI.git"
  branch = "master"
  src_root = File.join(smf_workspace_dir, File.basename(url, File.extname(url)))
  if File.exists?(src_root)
    UI.error("Can't clone into #{src_root}, directory already exists. Can't download Phraseapp-CI scripts.."
    return nil
  end
  UI.message("Cloning #{url} branch: #{branch} into #{src_root}")
  `git clone #{url} #{src_root} -b #{branch} -q > /dev/null`
  if File.exists?(src_root) == false
    UI.error("Error while cloning into #{src_root}. Couldn't download Phraseapp-CI scripts.."
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
  when :locales, :files
    return value.join(" ")
  when :force_update, :forbid_comments_in_source
    if (value == true)
      return "1"
    else
      return "0"
  else
    return value
  end
end

# Tries to get the value for the fiven key in the fastlane/Config.json
# if it doesn't exist it returns nil
def get_phrase_app_value_for(key)
  return @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app][0][key]
end

# export dict as environment variables
def export_dict_as_env_variables(dict)
  dict.each do |key, value|
    if (value != nil)
      env[key] = value
    end
  end
end
