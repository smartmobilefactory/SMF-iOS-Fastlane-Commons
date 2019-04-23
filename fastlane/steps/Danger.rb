def smf_run_danger()
  if File.file?('Dangerfile')

    ENV["BUILD_VARIANT"] = @smf_build_variant
    ENV["FASTLANE_CONFIG_PATH"] = fastlane_config_path
    ENV["FASTLANE_COMMONS_FOLDER"] = @fastlane_commons_dir_path
    ENV["DID_RUN_UNIT_TESTS"] = ENV[$SMF_DID_RUN_UNIT_TESTS_ENV_KEY]

    sh "cd .."

    danger(
        danger_id: @smf_build_variant,
        dangerfile: "fastlane/Dangerfile",
        github_api_token: ENV[$SMF_GITHUB_TOKEN_ENV_KEY]
    )
  else
    UI.important("There was no Dangerfile in ./fastlane, not running danger at all!")
  end
end
