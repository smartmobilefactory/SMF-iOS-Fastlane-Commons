#######################
### smf_publish_pod ###
#######################

desc "Publish the pod. Either to the official specs repo or to the SMF specs repo"
private_lane :smf_publish_pod do |options|

  UI.important("Publishing the Pod")

  # Variables
  bump_type = @smf_bump_type
  branch = @smf_git_branch
  project_config = @smf_fastlane_config[:project]
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  podspec_path = build_variant_config[:podspec_path]
  generateMetaJSON = (build_variant_config[:generateMetaJSON].nil? ? true : build_variant_config[:generateMetaJSON])

  generate_temporary_appfile

  # Unlock keycahin to enable pull repo with https
  if smf_is_keychain_enabled
    unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])
  end

  if smf_is_keychain_enabled
    unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])
  end

  # Make sure the repo is up to date and clean
  ensure_git_branch(branch: branch)

  # Bump the pods version if needed
  if ["major", "minor", "patch"].include? bump_type
    version_bump_podspec(
      path: podspec_path,
      bump_type: bump_type
      )
  elsif ["breaking", "internal"].include? bump_type
    # The versionning here is major.minor.breaking.internal
    # major & minor are set manually
    # Only breaking and internal are incremented via Fastlane
    if bump_type == "breaking"
      # Here we need to bump the patch component
      version_bump_podspec(
       path: podspec_path,
       bump_type: "patch"
      )

      # And set back the appendix to 0
      version_bump_podspec(
        path: podspec_path,
        version_appendix: "0"
      )
    elsif bump_type == "internal"
      appendix = 0
      currentVersionNumberComponents = version_get_podspec(path: podspec_path).split(".").map { |s| s.to_i }

      if currentVersionNumberComponents.length >= 4
        appendix = currentVersionNumberComponents[3]
      end

      appendix = appendix.next

      version_bump_podspec(
        path: podspec_path,
        version_appendix: appendix.to_s
      )
    end
  end

  # Check if the New Tag already exists
  smf_verify_git_tag_is_not_already_existing

  # Update the MetaJSONS if wanted
  if generateMetaJSON != false
    begin

      smf_generate_meta_json
      smf_commit_meta_json
    rescue => exception
      UI.important("Warning: MetaJSON couldn't be created")

      project_name = project_config[:project_name]

      smf_send_chat_message(
        title: "Failed to create MetaJSON for #{smf_default_notification_release_title} 😢",
        type: "error",
        exception: exception,
        slack_channel: ci_ios_error_log
      )
      next
    end
  end

  version = read_podspec(path: podspec_path)["version"]

  # Commit the version bump if needed
  if ["major", "minor", "patch", "breaking", "internal"].include? bump_type
    git_commit(
      path: podspec_path,
      message: "Release Pod #{version}"
      )
  end

  smf_collect_changelog

  # Add the git tag
  tag = smf_add_git_tag

  smf_git_pull

  # Push the changes to a temporary branch
  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: "jenkins_build/#{branch}",
    force: true,
    tags: true
  )

  begin
    # Publish the pod. Either to a private specs repo or to the offical one
    smf_pod_push

  rescue => e
    # Remove the git tag
    sh "git push --delete origin #{tag} || true"
    # Remove the temporary git branch
    sh "git push origin --delete jenkins_build/#{branch} || true"

    raise "Pod push failed: #{e.message}"
  end

  # Push the changes to the original branch
  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: branch,
    force: false,
    tags: true
  )

  # Remove the temporary git branch
  sh "git push origin --delete jenkins_build/#{branch} || true"

  # Create the GitHub release
  smf_create_github_release(
    release_name: version,
    tag: tag
  )

  smf_send_deploy_success_notifications(
    app_link: ""
    )
end
