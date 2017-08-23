module Fastlane
  module Actions
    class DeleteAppVersionOnHockeyAction < Action
      def self.run(params)

      UI.success("Starting deleting app version.")

        command = []
        command << "curl"
        command += upload_options(params[:api_token])    
        command << upload_url(params)

        shell_command = command.join(' ')
        result = Helper.is_test? ? shell_command : `#{shell_command}`
        fail_on_error(result)
        result

      end

      def self.fail_on_error(result)
        if result.include?("error")
          UI.error "Server error, failed to delete the version"
        end
      end

      def self.upload_url(params)

        "https://rink.hockeyapp.net/api/2/apps/#{params[:public_identifier]}/app_versions/#{params[:version_id]}"

      end

      def self.upload_options(api_token)

        options = []
         options << "-X DELETE"
         options << "-H 'X-HockeyAppToken:#{api_token}'"
         options

      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Delete the specified app version on HockeyApp"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "FL_HOCKEY_API_TOKEN",
                                       description: "API Token for Hockey Access",
                                       optional: false),

          FastlaneCore::ConfigItem.new(key: :public_identifier,
                                       env_name: "FL_HOCKEY_PUBLIC_IDENTIFIER",
                                       description: "Public identifier of the app you are targeting",
                                       optional: true),

          FastlaneCore::ConfigItem.new(key: :version_id,
                                       env_name: "FL_HOCKEY_VERSION_IDENTIFIER",
                                       description: "Version of the app you are targeting",
                                       optional: true)

        ]
      end

      def self.authors
        ["HansSeiffert"]
      end

      def self.is_supported?(platform)
        [:ios, :mac, :android].include? platform
      end
    end
  end
end
