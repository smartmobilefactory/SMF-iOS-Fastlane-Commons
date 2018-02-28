def smf_value_for_keypath_in_hash_map(hash_map, keypath)
  keys = keypath.split("/")
  value = hash_map
  for key in keys
    if value.key?(key)
      value = value[key]
    else
      raise "Error: Couldn't find keypath \"#{keypath}\" in \"#{hash_map}\"".red
    end
  end
  return value
end

def smf_load_fastlane_config
  config_path = fastlane_config_path
  UI.message("Reading the SMF Fastlane config from \"#{config_path}\"")
  config_file = File.read(config_path)
  if config_file
    @smf_fastlane_config ||= JSON.parse(config_file)
    UI.success("Parsed config file into the hash map")
  else
    raise "Error: The SMF Fastlane config file doesn't exist at path \"#{config_path}\"".red
  end
end
