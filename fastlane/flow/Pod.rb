#######################
### smf_publish_pod ###
#######################

# options: branch (String), tag_prefix (String) [optional], bump_type (String), podspec_path (String), repository_path (String), specs_repo (String)

desc "Publish the pod. Either to the official specs repo or to the SMF specs repo"
private_lane :smf_publish_pod do |options|

  UI.important("Publish Pod")

  # Read options parameter
  framework_config = options[:framework_config]
  project_config = options[:project_config]
  branch = options[:branch]
  generateMetaJSON = options[:generateMetaJSON]
  tag_prefix = (options[:tag_prefix].nil? ? "" : options[:tag_prefix])
  bump_type = options[:bump_type]
  podspec_path = framework_config["podsepc_path"]
  repository_path = project_config["github_repo_path"]
  specs_repo = framework_config["pods_specs_repo"]


  # Unlock keycahin to enable pull repo with https
  unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])

  unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])

  # Make sure the repo is up to date and clean
  ensure_git_branch(branch: branch)
  ensure_git_status_clean

  # Bump the pods version if needed
  if ["major", "minor", "patch"].include? bump_type
    version_bump_podspec(
      path: podspec_path,
      bump_type: bump_type
      )
  end
  
  # Update the MetaJSONS if wanted
  if generateMetaJSON != false
    begin
      smf_generate_meta_json(
        project_config: project_config,
        build_variant: bump_type,
        branch: branch
        )
      smf_commit_meta_json(
        branch: branch
      )
    rescue
      UI.important("Warning: MetaJSON couldn't be created")

      project_name = options[:project_config]["project_name"]

      message = "<table><tr><td><strong>Failed to create MetaJSON for #{project_name} #{bump_type.upcase} 😢</strong></td></tr><tr><td><strong> CI build: </strong><a href=#{ENV["BUILD_URL"]}> Build </a></td></tr></table>"

      smf_send_message_to_hipchat_ci_room(
        project_name: project_name,
        message: message,
        success: false
      )
      next
    end
  end

  version = read_podspec(path: podspec_path)["version"]

  # Commit the version bump if needed
  if ["major", "minor", "patch"].include? bump_type
    git_commit(
      path: podspec_path,
      message: "Release Pod #{version}"
      )
  end

  smf_collect_changelog(
    build_variant: bump_type,
    project_config: project_config,
    tag_prefix: tag_prefix
    )

  # Add the git tag
  begin
    add_git_tag(
      tag: "#{tag_prefix}#{version}"
    )
  rescue
    raise "Git tag already existed".red
  end

  smf_git_pull

  # Push the changes to a temporary branch
  push_to_git_remote(
    remote: 'origin',
    local_branch: branch,
    remote_branch: "jenkins_build/#{branch}",
    force: false,
    tags: true
  )
  
  begin
    # Publish the pod. Either to a private specs repo or to the offical one
    if specs_repo
      pod_push(
        repo: specs_repo,
        path: podspec_path,
        allow_warnings: true
        )
    else
      pod_push(path: podspec_path)
    end

  rescue => e 
    # Remove the git tag
    sh "git push --delete origin #{tag_prefix}#{version} || true"
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
    tag: "#{tag_prefix}#{version}",
    branch: branch,
    ignore_existing_release: true
  )

  # Update the CocoaPods repo to avoid unknown Pod version issues if this Pod is integrated into another project
  sh "pod repo update"

  smf_handle_pod_publish_success(
    build_variant: bump_type,
    project_config: project_config,
    framework_config: framework_config
    )

end

############################
### smf_test_pod_project ###
############################

# options: project_config (Hash), framework_config (Hash). "perform_unit_tests" is handeld as opt-out

desc "Performs the unit tests of the pod."
private_lane :smf_test_pod_project do |options|

  UI.important("Test the pod")

  # Read options parameter
  project_config = options[:project_config]
  framework_config = options[:framework_config]
  should_perform_unit_test = (framework_config["perform_unit_tests"].nil? ? true : framework_config["perform_unit_tests"])

  if should_perform_unit_test
    smf_perform_unit_tests(
      project_config: project_config,
      build_variant_config: framework_config
    )
  end

  smf_run_danger(options[:build_variant_config], "frameworks")

end

######################################
### smf_handle_pod_publish_success ###
######################################

# options: build_variant (String), project_config (Hash), framework_config (Hash), release_title (String) [optional]

desc "Handle the success by sending email to the authors and post to the hipchat channel"
private_lane :smf_handle_pod_publish_success do |options|

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_config = options[:project_config]
  framework_config = options[:framework_config]

  release_title = (options[:release_title].nil? ? smf_default_pod_notification_release_title(project_config["project_name"], framework_config) : options[:release_title])

  smf_handle_deploy_app_success(
    build_variant: build_variant,
    release_title: release_title,
    project_config: project_config,
    app_link: ""
    )
end
