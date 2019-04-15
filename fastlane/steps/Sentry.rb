##################################
### smf_upload_dsyms_to_sentry ###
##################################

desc "Upload generated dsyms to Sentry"
private_lane :smf_upload_dsyms_to_sentry do |options|
    project_config = @smf_fastlane_config[:project]

    sentry_upload_dsym(
      auth_token: $SENTRY_AUTH_TOKEN,
      org_slug: project_config[:sentry_org_slug],
      project_slug: project_config[:sentry_project_slug],
      url: $SENTRY_URL
    )
end