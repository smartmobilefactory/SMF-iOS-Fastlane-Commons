def smf_run_danger(build_variant)
  if File.file?('Dangerfile')
  	env_export = "export DANGER_GITHUB_API_TOKEN=$GITHUB_TOKEN; export BUILD_VARIANT=\"#{build_variant}\"; export FASTLANE_CONFIG_PATH=\"#{fastlane_config_path}\"; export FASTLANE_COMMONS_FOLDER=\"#{$FASTLANE_COMMONS_FOLDER_NAME}\""
    sh "#{env_export}; cd ..; /usr/local/bin/danger --dangerfile=fastlane/Dangerfile"
  else
    UI.important("There was no Dangerfile in ./fastlane, not running danger at all!")
  end
end
