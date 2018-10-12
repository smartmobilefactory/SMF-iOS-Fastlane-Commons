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

  paths_to_simulator_builds = nil
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]

  if build_variant_config[:attach_build_outputs_to_github] == true
    # Zip the release build
    # Upload dmg instead of app if Sparkle is enabled
    path_to_ipa_or_app = smf_path_to_ipa_or_app
    ipa_or_app_filename = File.basename(path_to_ipa_or_app)
    ipa_or_app_directory_path = File.dirname(path_to_ipa_or_app)
    sh "cd \"#{ipa_or_app_directory_path}\"; zip -r \"#{$SMF_DEVICE_RELEASE_APP_ZIP_FILENAME}\" \"#{ipa_or_app_filename}\""

    paths_to_simulator_builds = ["#{ipa_or_app_directory_path}/#{$SMF_DEVICE_RELEASE_APP_ZIP_FILENAME}", "#{smf_workspace_dir}/build/#{$SMF_SIMULATOR_RELEASE_APP_ZIP_FILENAME}"]
  end

  # Create the GitHub release as draft
  set_github_release(
    is_draft: true,
    repository_name: repository_path,
    api_token: ENV[$SMF_GITHUB_TOKEN_ENV_KEY],
    name: release_name.to_s,
    tag_name: tag,
    description: ENV[$SMF_CHANGELOG_ENV_KEY],
    commitish: @smf_git_branch,
    upload_assets: paths_to_simulator_builds
  )

  release_id = smf_get_github_release_id_for_tag(tag, repository_path)

  # Publish the release. We do this after the release was created as the assets are uploaded after the release is created on Github which results in release webhooks which doesn't contain the assets!
  github_api(
   server_url: "https://api.github.com",
    api_token: ENV[$SMF_GITHUB_TOKEN_ENV_KEY],
    http_method: "PATCH",
    path: "/repos/#{repository_path}/releases/#{release_id}",
    body: { 
      "draft": false 
      }
    )
end

##############
### Helper ###
##############

def smf_get_github_release_id_for_tag(tag, repository_path)

  result = github_api(
    server_url: "https://api.github.com",
    api_token: ENV[$SMF_GITHUB_TOKEN_ENV_KEY],
    http_method: "GET",
    path: "/repos/#{repository_path}/releases"
    )

  releases = JSON.parse(result[:body])
  release_id = nil
  for release in releases
    if release["tag_name"] == tag
      release_id = release["id"]
      break
    end
  end

  UI.message("Found id \"#{release_id}\" for release \"#{tag}\"")

  return release_id
end

def smf_download_asset(asset_name, assets, token)

  asset_url = smf_asset_url_from_webhook_event(asset_name, assets)

  sh(
    "curl", "-X", "GET",
    "-H", "Accept: application/octet-stream", 
    "-LJ",
    "-o", asset_name,
    asset_url.gsub("https://", "https://#{token}@")
  )

  unzip_dir = "#{asset_name.downcase}-unzipped"
  sh "mkdir #{unzip_dir}"

  sh "cd #{unzip_dir} && unzip ../#{asset_name}"

  Dir.glob("#{unzip_dir}/*.*").each do |file|
    return file
  end

  raise "Couldn't find a asset download!"
end

def smf_asset_url_from_webhook_event(asset_name, assets)

  assets.each { |asset|
    if asset["name"] == asset_name
      return asset["url"]
    end
  }

  raise "Couldn't find a matching asset with the name \"#{asset_name}\" in \"#{assets}\""
end

# Download release from Github, by tag.
def smf_fetch_release_for_tag(tag, token, project)

  url = "https://#{token}@api.github.com/repos/#{project}/releases/tags/#{tag}"

  return JSON.parse(RestClient.get(url, {:params => {:access_token => token}}))
end

# return assets from the downloaded Asset.
def smf_fetch_assets_for_tag(tag, token, project)
  release = smf_fetch_release_for_tag(tag, token, project)

  return release["assets"]
end
