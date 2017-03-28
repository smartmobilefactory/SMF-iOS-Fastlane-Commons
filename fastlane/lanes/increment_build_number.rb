
desc "Increment Build Version Code and Push tags."
private_lane :increment_build_number do |options|

  buildVariant = options[:buildVariant]
  branch = options[:branch]

  UI.important("Increment Build Version Code")

  clean_build_artifacts

  version = get_build_number(xcodeproj: "#{PROJECT_NAME}.xcodeproj")
  puts version

  commit_version_bump(
    xcodeproj: "#{PROJECT_NAME}.xcodeproj",
    message: "Increment build number to #{version}"
    )

    # Tag the increment build number commit
    if git_tag_exists(tag: "build/"+buildVariant+"_b"+version)
      UI.message("Git tag already existed")
    else
      add_git_tag(
        tag: "build/"+buildVariant+"_b"+version
        )
    end
    
    push_to_git_remote(
      remote: 'origin',
      local_branch: branch,
      remote_branch: branch,
      force: false,
      tags: true
      )

    clean_build_artifacts

  end


