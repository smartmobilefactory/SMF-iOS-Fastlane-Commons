

  desc "Collect git commit messages into a changelog."
  private_lane :collect_changelog do |options|

    buildVariant = options[:buildVariant]

    UI.important("collect commits back to the last tag")

    case buildVariant 
    when "Alpha"
      ENV["CHANGELOG"] =  changelog_from_git_commits(include_merges: false, pretty: '- (%an) %s')
      ENV["EMAIL"] = changelog_from_git_commits( include_merges: false, pretty: '%ae')
    else
      if TARGETS_DICT.key?(buildVariant)
        ENV["CHANGELOG"] =  changelog_from_git_commits(tag_match_pattern: '*#{buildVariant}*',include_merges: false, pretty: '- (%an) %s')
        ENV["EMAIL"] = changelog_from_git_commits(tag_match_pattern: '*#{buildVariant}*',include_merges: false, pretty: '%ae')
      else
        puts "No valid target"
      end
    end

  end
