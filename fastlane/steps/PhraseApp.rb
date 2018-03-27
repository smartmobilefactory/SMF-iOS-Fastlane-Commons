########################################
### smf_sync_strings_with_phrase_app ###
########################################

desc "Snycs the Strings with PhraseApp if the build variant declared a PhraseApp script"
private_lane :smf_sync_strings_with_phrase_app do |options|

  phrase_app_script = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:phrase_app_script]
  if phrase_app_script
    UI.message("String are synced with PhraseApp using the script \"phrase_app_script\"")

    begin
      sh "#{smf_workspace_dir}/#{phrase_app_script} #{@smf_git_branch}"
    rescue => e
      UI.error("Failed to sync Strings with PhraseApp: #{e.message}")

      smf_send_hipchat_message(
        title: "Failed to sync Strings with PhraseApp for #{smf_default_notification_release_title} 😢",
        message: "The build job will continue but won't contain updated translations!",
        exception: e,
        success: false,
        hipchat_channel: @smf_fastlane_config[:project][:hipchat_channel]
      )
    end
  else
    UI.important("String are not synced with PhraseApp as the build variant didn't declare a \"phrase_app_script\"")
  end

end
