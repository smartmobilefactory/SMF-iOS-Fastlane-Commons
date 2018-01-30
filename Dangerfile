if github.pr_body.length < 5
  warn "Please provide a summary in the Pull Request description"
end

warn("Please target PRs to `develop` branch") if github.branch_for_base != "develop"
