def smf_run_danger()
  if File.file?('Dangerfile')
    env_export = "export BUILD_VARIANT=\"#{@smf_build_variant}\";"
    env_export << "export FASTLANE_CONFIG_PATH=\"#{fastlane_config_path}\";"
    env_export << "export FASTLANE_COMMONS_FOLDER=\"#{@fastlane_commons_dir_path}\";"
    env_export << "export DID_RUN_UNIT_TESTS=\"#{ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY]}\";"
    sh "#{env_export} cd ..; /usr/local/bin/danger --dangerfile=fastlane/Dangerfile --danger_id=#{@smf_build_variant}"
  else
    UI.important("There was no Dangerfile in ./fastlane, not running danger at all!")
  end
end
