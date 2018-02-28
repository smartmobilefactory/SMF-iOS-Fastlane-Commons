##############################
### smf_generate_meta_json ###
##############################

# options: branch (String), build_variant (String) and build_variants_contains_whitelist (String) [optional]

desc "Create the metaJSON files - applys only for Alpha builds."
private_lane :smf_generate_meta_json do |options|

  # Read options parameter
  branch = options[:branch]
  build_variant = options[:build_variant].downcase
  project_name = options[:project_config]["project_name"]
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  if (build_variants_contains_whitelist.nil?) || (build_variants_contains_whitelist.any? { |whitelist_item| build_variant.include?(whitelist_item) })
    desc "Create the meta JSON files"
    # Fetch the MetaJSON scripts repo
    sh "git clone git@github.com:smartmobilefactory/SMF-iOS-MetaJSON.git"
    # Create and commit the MetaJSON files
    sh "cd .. && fastlane/SMF-iOS-MetaJSON/scripts/create-meta-jsons.sh \"#{project_name}\" \"#{branch}\" || true"
    # Remove the MetaJSON scripts repo
    sh "rm -rf SMF-iOS-MetaJSON"
  end

end

############################
### smf_commit_meta_json ###
############################

# options: branch (String)

desc "Commit the metaJSON files - applys only for Alpha builds."
private_lane :smf_commit_meta_json do |options|
  branch = options[:branch]

  workspace = ENV["WORKSPACE"]

  desc "Commit the meta JSON files"

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
  workspace = ENV["WORKSPACE"]

  system "cd " + workspace + "; Pods/SwiftLint/swiftlint lint --reporter json > build/reports/swiftlint.json"

  # Removes the workspace part
  workspace_regexp = (workspace + '/').gsub(/\//, '\\\\\\\\\/')
  system "sed -i -e 's/#{workspace_regexp}//g' " + workspace + "/build/reports/swiftlint.json"

  # Turns \/ int /
  a = '\\\\\/'
  b = '\/'
  system "sed -i -e 's/#{a}/#{b}/g' " + workspace + "/#{$METAJSON_TEMP_FOLDERNAME}/swiftlint.json"

end

def smf_run_slather(scheme, projectName)
  workspace = ENV["WORKSPACE"]

  system "cd " + workspace + "; slather coverage -v --html --scheme " + scheme + " --workspace " + projectName + ".xcworkspace " + projectName + ".xcodeproj"
  system "cd " + workspace + "; slather coverage -v --json --scheme " + scheme + " --workspace " + projectName + ".xcworkspace " + projectName + ".xcodeproj"

  if File.file?(workspace + '/report.json')
    smf_create_json_slather_summary(workspace + '/report.json')
  end

  sh "if [ -f #{workspace}/build/reports/test_coverage.json ]; then cp #{workspace}/build/reports/test_coverage.json #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/test_coverage.json; fi"
  sh "if [ -d #{workspace}/html ]; then cp -r #{workspace}/html #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
  # Compress the Slather HTML folder and delete it afterwards
  sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report ]; then zip #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report.zip #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
  sh "if [ -f #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report.zip ]; then rm -rf #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/slather_coverage_report; fi"
end

def smf_create_json_slather_summary(report_file)
  if File.file?(report_file)
    files = JSON.parse(File.read(report_file))

    workspace = ENV["WORKSPACE"]

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
        #puts "Covered lines in " + file["file"] + ": " + covered_loc.to_s + " of " + relevant_loc.to_s  + " relevant lines of code (" + percent.round(3).to_s + "%)"

        entity = { }
        entity["file"] = file["file"]
        entity["coverage"] = percent
        summary["files"] << entity

        total_covered_loc += covered_loc
        total_relevant_loc += relevant_loc
    end

    percent = (total_covered_loc.to_f / total_relevant_loc.to_f) * 100
    #puts "Tested " + files.length.to_s + " files. Total coverage: " + percent.to_s  + "%"

    summary["total_coverage"] = percent

    File.open(workspace + "/build/reports/test_coverage.json", "w") do |f|
      f.write(summary.to_json)
    end
  else
    puts "Sorry, could not find file: " + report_file
  end
end
