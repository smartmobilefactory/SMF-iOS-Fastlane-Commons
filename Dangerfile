############################
###### General config ######
############################

if system("test -f fastlane/BuildVariants.json")
  config = JSON.parse(File.read('fastlane/BuildVariants.json'))
  project_config = config["project"]
  target_config = config["targets"]["alpha"] # TODO: Make multi target compatible
  config_parsed = true
else
  warn "No BuildVariants.json found in ./fastlane"
end

#####################
###### General ######
#####################

if github.pr_body.length < 5
  warn "Please provide a summary in the Pull Request description"
end

if github.branch_for_base != "develop"
  warn("Please target PRs to `develop` branch")
end

if github.pr_title.include? "[WIP]"
  warn("PR is classed as Work in Progress") 
end

###################
###### Xcode ######
###################

xcode_summary.report 'build/reports/errors.json'

#####################
###### Slather ######
#####################

  if config_parsed == true
    slather.configure(project_config["project_name"] + ".xcodeproj", target_config["scheme"], options: {
    workspace: project_config["project_name"] + ".xcworkspace"
  })

  slather.notify_if_coverage_is_less_than(minimum_coverage: 40)
  slather.notify_if_modified_file_is_less_than(minimum_coverage: 50)
  slather.show_coverage
else
  warn("Slather not run: BuildVariants.json wasn't parsed")
end
