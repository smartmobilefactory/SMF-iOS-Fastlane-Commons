#############################
### smf_collect_changelog ###
#############################

desc "Collect git commit messages and author mail adresses into a changelog and store them as environmental varibles."
private_lane :smf_collect_changelog do |options|

  UI.important("Collecting commits back to the last tag")

  # Constants
  NO_GIT_TAG_FAILURE = "NO_GIT_TAG_FAILURE"

  # Create the tag with a regex as version. The result is eg. "releases/*" which will match any tag starting with "releases/"
  matching_pattern = smf_construct_default_tag_for_current_project("*")

  last_tag = sh("git describe --tags --match \"#{matching_pattern}\" --abbrev=0 HEAD --first-parent || echo #{NO_GIT_TAG_FAILURE}").to_s

  # Use the initial commit if there is no matching tag yet
  if last_tag.include? NO_GIT_TAG_FAILURE
    last_tag = sh("git rev-list --max-parents=0 HEAD").to_s
  end

  last_tag = last_tag.strip

  ENV[$SMF_CHANGELOG_ENV_KEY] =  changelog_from_git_commits(
    between:[last_tag,"HEAD"],
    merge_commit_filtering: "exclude_merges",
    pretty: '- (%an) %s'
    )
  ENV[$SMF_CHANGELOG_EMAILS_ENV_KEY] = changelog_from_git_commits(
    between:[last_tag,"HEAD"],
    merge_commit_filtering: "exclude_merges",
    pretty: '%ae'
    )

  # Store the change log in a file if a macOS app is build as the upload to HockeyApp is done in a separate Fastlane call
  if lane_context[SharedValues::PLATFORM_NAME] == "mac"
    File.open("changelog.properties", 'w') { |file| file.write("#{$SMF_CHANGELOG_ENV_KEY}='#{ENV[$SMF_CHANGELOG_ENV_KEY]}'") }
    File.open("emails.properties", 'w') { |file| file.write("#{$SMF_CHANGELOG_EMAILS_ENV_KEY}='#{ENV[$SMF_CHANGELOG_EMAILS_ENV_KEY]}'") }
  end

end

##########################################################
#####   smf_verify_git_tag_is_not_already_existing   #####
##########################################################

desc "Check if the tag exist after incrementation of the build number"
private_lane :smf_verify_git_tag_is_not_already_existing do |options|

  UI.important("Checking if the incremented tag already exists")

  # Check if the tag already exists.
  git_tag = smf_construct_default_tag_for_current_project
  # Check also for the former default tag prefix
  project_config = @smf_fastlane_config[:project]
  tag_prefix = (project_config[:tag_prefix].nil? ? smf_default_tag_prefix : project_config[:tag_prefix])
  deprecated_git_tag = smf_construct_tag_for_current_project("#{tag_prefix}_b", "")
  if git_tag_exists(tag: git_tag) or git_tag_exists(tag: deprecated_git_tag)
    raise "The Git tag already exists! The build job will be aborted to avoid builds with the same build nubmer. If this surprises you: It may be a good time to get some help."
  end

end


#######################
### smf_add_git_tag ###
#######################

desc "Tag the current git commit."
private_lane :smf_add_git_tag do |options|

  # Check if the tag isn't already existing. The build job will fail here if it already exists
  smf_verify_git_tag_is_not_already_existing

  tag = smf_construct_default_tag_for_current_project
  add_git_tag(
    tag: tag
    )

  # Return the tag
  tag
end

#################################
### smf_commit_generated_code ###
#################################

desc "Commit generated code"
private_lane :smf_commit_generated_code do |options|

  UI.important("Commit and push generated code")

  # Reset the currently staged files first to make sure only the generated code will be commited
  sh "git reset"
  sh "git ls-files . | grep '\.generated\.' | xargs git add || true"
  sh "git commit -m \"Update generated code\" || true"

end


###############################
### smf_commit_build_number ###
###############################

desc "Commit the build number."
private_lane :smf_commit_build_number do |options|

  UI.important("Commiting build number incrementation")

  project_name = @smf_fastlane_config[:project][:project_name]

  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  commit_version_bump(
    xcodeproj: "#{project_name}.xcodeproj",
    message: "#{smf_increment_build_number_prefix_string}#{version}",
    force: true
    )

end


#################################
### smf_create_github_release ###
#################################

# options: release_name (String), tag (String)

private_lane :smf_create_github_release do |options|

  # Parameter
  release_name = options[:release_name]
  tag = options[:tag]

  git_remote_origin_url = sh "git config --get remote.origin.url"
  github_url_match = git_remote_origin_url.match(/.*github.com:(.*)\.git/)
  # Search fot the https url if the ssh url couldn't be found
  if github_url_match.nil?
    github_url_match = git_remote_origin_url.match(/.*github.com\/(.*)\.git/)
  end

  if github_url_match.nil? or github_url_match.length < 2
    UI.message("The remote orgin doesn't seem to be GitHub. The GitHub Release won't be created.")
    return
  end

  repository_path = github_url_match[1]

  UI.message("Found \"#{repository_path}\" as GitHub project")

  # Create the GitHub release
  set_github_release(
    repository_name: repository_path,
    api_token: ENV[$SMF_GITHUB_TOKEN_ENV_KEY],
    name: release_name.to_s,
    tag_name: tag,
    description: ENV[$SMF_CHANGELOG_ENV_KEY],
    commitish: @smf_git_branch
  )
end

##############
### Helper ###
##############

def smf_construct_default_tag_for_current_project(version = nil)

  project_config = @smf_fastlane_config[:project]
  tag_prefix = (project_config[:tag_prefix].nil? ? smf_default_tag_prefix : project_config[:tag_prefix])
  tag_suffix = (project_config[:tag_suffix].nil? ? "" : project_config[:tag_suffix])

  return smf_construct_tag_for_current_project(tag_prefix, tag_suffix, version)
end

def smf_construct_tag_for_current_project(tag_prefix, tag_suffix, version = nil)

  tag_prefix = (tag_prefix.nil? ? "" : tag_prefix)
  tag_suffix = (tag_suffix.nil? ? "" : tag_suffix)

  # Get the current build number
  if version.nil?
    version = smf_default_tag_version
  end

  return tag_prefix+version+tag_suffix
end

def smf_git_pull
  branch = @smf_git_branch
  branch_name = "#{branch}"
  branch_name.sub!("origin/", "")
  sh "git pull origin #{branch_name}"
end

def smf_default_tag_prefix
  return (smf_is_build_variant_a_pod ? smf_default_pod_tag_prefix : smf_default_app_tag_prefix)
end

def smf_default_tag_version
  if smf_is_build_variant_a_pod 
    podspec_path = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:podspec_path]
    version = read_podspec(path: podspec_path)["version"]
    return version
  else
    build_number = get_build_number(xcodeproj: "#{@smf_fastlane_config[:project][:project_name]}.xcodeproj").to_s
    return build_number
  end
end

def smf_default_app_tag_prefix
  return "build/#{@smf_build_variant}/"
end

def smf_default_pod_tag_prefix
  return "releases/"
end
