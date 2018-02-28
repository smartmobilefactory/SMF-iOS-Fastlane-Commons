#############################
### smf_collect_changelog ###
#############################

# options: build_variant (String)

desc "Collect git commit messages and author mail adresses into a changelog and store them as environmental varibles."
private_lane :smf_collect_changelog do |options|

  UI.important("collect commits back to the last tag")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_platform = options[:project_config]["platform"]

  matching_pattern = (options[:tag_prefix].nil? ? "#{build_variant}" : options[:tag_prefix])

  NO_GIT_TAG_FAILURE = "NO_GIT_TAG_FAILURE"

  # Get last tag for the current branch
  last_tag = sh("git describe --tags --match \"*#{matching_pattern}*\" --abbrev=0 HEAD --first-parent || echo #{NO_GIT_TAG_FAILURE}").to_s

  # Use the initial commit if there is no matching tag yet
  if last_tag.include? NO_GIT_TAG_FAILURE
    last_tag = sh("git rev-list --max-parents=0 HEAD").to_s
  end

  last_tag = last_tag.strip

  if ["patch", "minor", "major", "current"].any? { |item| build_variant.downcase.include?(item) }
    ENV["SMF_CHANGELOG"] =  changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '- (%an) %s')
    ENV["SMF_CHANGELOG_EMAILS"] = changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '%ae')
  else
    ENV["SMF_CHANGELOG"] =  changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '- (%an) %s')
    ENV["SMF_CHANGELOG_EMAILS"] = changelog_from_git_commits(between:[last_tag,"HEAD"],include_merges: false, pretty: '%ae')
  end

  if (!project_platform.nil?) && (project_platform.eql? "mac")

   File.open("changelog.properties", 'w') { |file| file.write("SMF_CHANGELOG='#{ENV["SMF_CHANGELOG"]}'") }
   File.open("emails.properties", 'w') { |file| file.write("SMF_CHANGELOG_EMAILS='#{ENV["SMF_CHANGELOG_EMAILS"]}'") }

  end

end

#############################
#####   smf_check_tag   #####
#############################

# options: build_variant (String)

desc "Check if the tag exist after incrementation of the build number"
private_lane :smf_check_tag do |options|

  UI.important("check if the Incremented Tag exist")

  # Read options parameter
  build_variant = options[:build_variant].downcase
  project_name = options[:project_config]["project_name"]

  tag_prefix = (options[:tag_prefix].nil? ? "build/#{build_variant}/" : options[:tag_prefix])
  tag_suffix = (options[:tag_suffix].nil? ? "" : options[:tag_suffix])

  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")

  # Use the incremented build number only if it should be incremented. Also pass the former default prefix.
  tag_prefixes = [tag_prefix, "build/#{build_variant}_b"]
  if smf_should_build_number_be_incremented(tag_prefixes)
    version = smf_get_incremented_build_number(version)
  end

  # Check if the tag already exists. Check also for the former default tag prefix
  if git_tag_exists(tag: tag_prefix+version.to_s+tag_suffix) or git_tag_exists(tag: "build/#{build_variant}_b"+version.to_s+tag_suffix)
    raise "Git tag already existed".red
  end

end


#######################
### smf_add_git_tag ###
#######################

# options: project_config (Hash), tag_prefix (String), tag_suffix (String) [optional], branch (String) [optional]

desc "Tag the current git commit."
private_lane :smf_add_git_tag do |options|

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  tag_prefix = (options[:tag_prefix].nil? ? "" : options[:tag_prefix])
  tag_suffix = (options[:tag_suffix].nil? ? "" : options[:tag_suffix])
  branch = options[:branch]

  UI.important("Tag the current commit")
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  version = version.to_s

  # Tag the current commit
  tag = tag_prefix+version+tag_suffix
  if git_tag_exists(tag: tag_prefix+version+tag_suffix)
    UI.message("Git tag already existed")
  else
    add_git_tag(
      tag: tag
      )
  end

  # Return the tag
  tag
end

#################################
### smf_commit_generated_code ###
#################################

# options: branch (String)

desc "Commit generated code"
private_lane :smf_commit_generated_code do |options|

  UI.important("Commit and push generated code")
    # Read options parameter
    branch = options[:branch]

    # Reset the currently staged files first to make sure only the generated code will be commited
    sh "git reset"
    sh "git add ../Generated/ || true"
    sh "git commit -m \"Update generated code\" || true"

end


###############################
### smf_commit_build_number ###
###############################

# options: project_config (Hash), branch (String)

desc "Commit the build number."
private_lane :smf_commit_build_number do |options|

  # Read options parameter
  project_name = options[:project_config]["project_name"]
  branch = options[:branch]

  UI.important("Increment Build Version Code")
  version = get_build_number(xcodeproj: "#{project_name}.xcodeproj")
  puts version

  commit_version_bump(
    xcodeproj: "#{project_name}.xcodeproj",
    message: "#{smf_increment_build_number_prefix_string}#{version}",
    force: true
    )

end


#################################
### smf_create_github_release ###
#################################

# options: release_name (String), tag (String), branch (String)

private_lane :smf_create_github_release do |options|

  release_name = options[:release_name]
  tag = options[:tag]
  branch = options[:branch]
  ignore_existing_release = (options[:ignore_existing_release].nil? ? false : options[:ignore_existing_release])

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

  UI.message("Found #{repository_path} as GitHub repo name")

  if get_github_release(url: repository_path, version: tag) and ignore_existing_release == false
    raise "Git release already existed".red
  end

  UI.message("Found #{repository_path} as GitHub repo name")

  # Create the GitHub release
  set_github_release(
    repository_name: repository_path,
    api_token: ENV['GITHUB_TOKEN'],
    name: release_name.to_s,
    tag_name: tag,
    description: ENV["SMF_CHANGELOG"],
    commitish: branch
  )
end

##############
### Helper ###
##############

def smf_git_pull
  branch = git_branch
  branch_name = "#{branch}"
  branch_name.sub!("origin/", "")
  sh "git pull origin #{branch_name}"
end
