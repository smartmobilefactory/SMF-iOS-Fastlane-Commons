############################
###### General config ######
############################

build_variant = ENV['BUILD_VARIANT']
message( "Running danger for build variant: " + build_variant )

if File.file?('fastlane/BuildVariants.json')
  config = JSON.parse(File.read('fastlane/BuildVariants.json'))
  project_config = config["project"]
  target_config = config["targets"][build_variant]
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

#######################
###### Swiftlint ######
#######################

swiftlint.lint_files

#####################
###### Slather ######
#####################

if config_parsed == true
  if config["targets"][build_variant]["perform_unit_tests"]
    slather.configure(project_config["project_name"] + ".xcodeproj", target_config["scheme"], options: {
      workspace: project_config["project_name"] + ".xcworkspace"
    })

    slather.notify_if_coverage_is_less_than(minimum_coverage: 30)
    slather.notify_if_modified_file_is_less_than(minimum_coverage: 50)
    slather.show_coverage
  else
    message( "Skipping slather (code coverage) for: " + build_variant + ". Not enabled in BuildVariants.json.")
  end
else
  warn("Slather not run: BuildVariants.json wasn't parsed")
end
