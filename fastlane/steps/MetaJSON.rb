# Constants

SLATHER_COVERAGE_REPORT_JSON_NAME = "report.json"
SMF_COVERAGE_REPORT_JSON_NAME = "test_coverage.json"
SLATHER_HTML_OUTPUT_DIR_NAME = "slather_coverage_report"

##############################
### smf_generate_meta_json ###
##############################

# options: build_variants_contains_whitelist (String) [optional]

desc "Create the metaJSON files - applys only for Alpha builds."
private_lane :smf_generate_meta_json do |options|

  # Parameter
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  if (build_variants_contains_whitelist.nil?) || (build_variants_contains_whitelist.any? { |whitelist_item| @smf_build_variant.include?(whitelist_item) })
    desc "Create the meta JSON files"
    # Fetch the MetaJSON scripts repo
    sh "git clone git@github.com:smartmobilefactory/SMF-iOS-MetaJSON.git"
    # Create and commit the MetaJSON files
    sh "cd .. && fastlane/SMF-iOS-MetaJSON/scripts/create-meta-jsons.sh \"#{@smf_fastlane_config[:project][:project_name]}\" \"#{@smf_git_branch}\" || true"
    # Remove the MetaJSON scripts repo
    sh "rm -rf SMF-iOS-MetaJSON"
  end

end

############################
### smf_commit_meta_json ###
############################

desc "Commit the metaJSON files - applys only for Alpha builds."
private_lane :smf_commit_meta_json do |options|

  # Variables
  workspace = smf_workspace_dir

  # Copy additional meta files to MetaJSON directory
  sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then cp -R #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/. #{workspace}/.MetaJSON/; fi"

  # Delete the temporary MetaJSON folder
  sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}; fi"

  # Reset git, add MetaJSON directory and commit
  sh "cd \"#{workspace}\"; git reset && git add \".MetaJSON\" && git commit -m \"Update MetaJSONs\""
end

##############
### Helper ###
##############

def smf_run_linter

  # Variables
  workspace = smf_workspace_dir

  begin
    # Run SwiftLint and save the output as JSON
    system "cd " + workspace + "; Pods/SwiftLint/swiftlint lint --reporter json > build/reports/swiftlint.json"

    # Removes the workspace part
    workspace_regexp = (workspace + '/').gsub(/\//, '\\\\\\\\\/')
    system "sed -i -e 's/#{workspace_regexp}//g' " + workspace + "/build/reports/swiftlint.json"

    # Turns \/ int /
    a = '\\\\\/'
    b = '\/'
    # Convert the abosulte path to a path wich is relative to the project root folder
    system "sed -i -e 's/#{a}/#{b}/g' " + workspace + "/#{$METAJSON_TEMP_FOLDERNAME}/swiftlint.json"
  rescue => e
    UI.error("Failed to run SwiftLint. But the build job will continue.")

    smf_send_hipchat_message(
        title: "Failed to run Swiftlint for #{smf_default_notification_release_title} 😢",
        success: false,
        hipchat_channel: "CI"
      )
  end
end

def smf_run_slather

  # Variables
  workspace = smf_workspace_dir
  scheme = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]
  project_name = @smf_fastlane_config[:project][:project_name]

  # Create the Slather report as html
  system "cd " + workspace + "; slather coverage -v --html --scheme " + scheme + " --workspace " + project_name + ".xcworkspace " + project_name + ".xcodeproj"
  
  # Create the Slather report as json
  system "cd " + workspace + "; slather coverage -v --json --scheme " + scheme + " --workspace " + project_name + ".xcworkspace " + project_name + ".xcodeproj"

  # Analyse the Slather json report and store the result in out format
  if File.file?(workspace + "/#{SLATHER_COVERAGE_REPORT_JSON_NAME}")
    smf_create_json_slather_summary(workspace + "/#{SLATHER_COVERAGE_REPORT_JSON_NAME}")
  end

  # Copy the output into the temporary MetaJSON folder so that the files can be used once the MetaJSON creation is complete
  slather_json_report_path = "#{workspace}/build/reports/#{SMF_COVERAGE_REPORT_JSON_NAME}"
  sh "if [ -f \"#{slather_json_report_path}\" ]; then cp \"#{slather_json_report_path}\" #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/#{SMF_COVERAGE_REPORT_JSON_NAME}; fi"
  slather_html_report_output_path = "#{workspace}/html"
  slather_html_report_path = "#{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/#{SLATHER_HTML_OUTPUT_DIR_NAME}"
  sh "if [ -d \"#{slather_html_report_output_path}\" ]; then cp -r \"#{slather_html_report_output_path}\" \"#{slather_html_report_path}\"; fi"

  # Compress the Slather HTML folder and delete it afterwards
  sh "if [ -d \"#{slather_html_report_path}\" ]; then cd \"#{workspace}/#{$METAJSON_TEMP_FOLDERNAME}\"; zip \"#{slather_html_report_path}.zip\" \"#{slather_html_report_path}\"; fi"
  sh "if [ -f \"#{slather_html_report_path}.zip\" ]; then rm -rf \"#{slather_html_report_path}\"; fi"
end

def smf_create_json_slather_summary(report_file)
  if File.file?(report_file)
    files = JSON.parse(File.read(report_file))

    workspace = smf_workspace_dir

    summary = { }
    summary["files"] = [ ]

    total_covered_loc = 0
    total_relevant_loc = 0
    filenum = 0

    for file in files
        filenum += 1

        covered_loc = 0
        relevant_loc = 0

        for line in file["coverage"]
          if line.to_i > 0
            covered_loc += 1
            relevant_loc += 1
          elsif !line.nil? && line.to_i == 0
            relevant_loc += 1
          end
        end

        percent = (covered_loc.to_f / relevant_loc.to_f) * 100

        entity = { }
        entity["file"] = file["file"]
        entity["coverage"] = percent
        summary["files"] << entity

        total_covered_loc += covered_loc
        total_relevant_loc += relevant_loc
    end

    percent = (total_covered_loc.to_f / total_relevant_loc.to_f) * 100

    summary["total_coverage"] = percent

    File.open(workspace + "/build/reports/#{SMF_COVERAGE_REPORT_JSON_NAME}", "w") do |f|
      f.write(summary.to_json)
    end
  else
    puts "Warning: could not find Slather JSON report with filename \"#{report_file}\""
  end
end
