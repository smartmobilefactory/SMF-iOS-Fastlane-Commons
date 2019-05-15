##################################
### smf_upload_dsyms_to_sentry ###
##################################

desc "Upload generated dsyms to Sentry"
private_lane :smf_upload_dsyms_to_sentry do |options|
	# First take the sentry settings from the project level
    project_config = @smf_fastlane_config[:project]

    org_slug = project_config[:sentry_org_slug]
    project_slug = project_config[:sentry_project_slug]

    variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

    org_slug_variant = variant_config[:sentry_org_slug]
    project_slug_variant = variant_config[:sentry_project_slug]

    # If a build variant overrides the sentry settings, use the variant settings
    if org_slug_variant != nil && project_slug_variant != nil
    	org_slug = org_slug_variant
    	project_slug = project_slug_variant
    end

    sentry_upload_dsym(
      auth_token: $SENTRY_AUTH_TOKEN,
      org_slug: org_slug,
      project_slug: project_slug,
      url: $SENTRY_URL
    )
end