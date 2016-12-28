require 'json'
require 'ipa_analyzer'
require_relative 'common'

# -----------------------
# --- upload ipa
# -----------------------

def export_method(mobileprovision_content)
  # if ProvisionedDevices: !nil & "get-task-allow": true -> development
  # if ProvisionedDevices: !nil & "get-task-allow": false -> ad-hoc
  # if ProvisionedDevices: nil & "ProvisionsAllDevices": "true" -> enterprise
  # if ProvisionedDevices: nil & ProvisionsAllDevices: nil -> app-store
  if mobileprovision_content['ProvisionedDevices'].nil?
    return 'enterprise' if !mobileprovision_content['ProvisionsAllDevices'].nil? && (mobileprovision_content['ProvisionsAllDevices'] == true || mobileprovision_content['ProvisionsAllDevices'] == 'true')
    return 'app-store'
  else
    unless mobileprovision_content['Entitlements'].nil?
      entitlements = mobileprovision_content['Entitlements']
      return 'development' if !entitlements['get-task-allow'].nil? && (entitlements['get-task-allow'] == true || entitlements['get-task-allow'] == 'true')
      return 'ad-hoc'
    end
  end
  return 'development'
end

def deploy_ipa_to_bitrise(ipa_path, build_url, api_token, notify_user_groups, notify_emails, is_enable_public_page)
  puts
  puts
  puts "# Deploying ipa file: #{ipa_path}"

  # - Analyze the IPA / collect infos from IPA
  puts '--> Analyze the IPA'

  ipa_export_method = ''
  parsed_ipa_infos = {
    mobileprovision: nil,
    info_plist: nil
  }
  ipa_analyzer = IpaAnalyzer::Analyzer.new(ipa_path)
  begin
    puts '  => Opening the IPA'
    ipa_analyzer.open!

    puts '  => Collecting Provisioning Profile information'
    parsed_ipa_infos[:mobileprovision] = ipa_analyzer.collect_provision_info
    fail 'Failed to collect Provisioning Profile information' if parsed_ipa_infos[:mobileprovision].nil?

    ipa_export_method = export_method(parsed_ipa_infos[:mobileprovision][:content])
    if ipa_export_method == 'app-store'
      if is_enable_public_page
        puts
        puts ' (!) is_enable_public_page is set, but public download isn\'t allowed for app-store distributions'
        puts ' (!) setting is_enable_public_page to false ...'
        puts
        is_enable_public_page = false
      end
    end

    puts '  => Collecting Info.plist information'
    parsed_ipa_infos[:info_plist] = ipa_analyzer.collect_info_plist_info
    fail 'Failed to collect Info.plist information' if parsed_ipa_infos[:info_plist].nil?
  rescue => ex
    puts
    puts "Failed: #{ex}"
    puts
    raise ex
  ensure
    puts '  => Closing the IPA'
    ipa_analyzer.close
  end
  puts
  puts '  (i) Parsed IPA infos:'
  puts parsed_ipa_infos
  puts

  ipa_file_size = File.size(ipa_path)

  info_plist_content = parsed_ipa_infos[:info_plist][:content]
  mobileprovision_content = parsed_ipa_infos[:mobileprovision][:content]
  ipa_info_hsh = {
    file_size_bytes: ipa_file_size,
    app_info: {
      app_title: info_plist_content['CFBundleName'],
      bundle_id: info_plist_content['CFBundleIdentifier'],
      version: info_plist_content['CFBundleShortVersionString'],
      build_number: info_plist_content['CFBundleVersion'],
      min_OS_version: info_plist_content['MinimumOSVersion'],
      device_family_list: info_plist_content['UIDeviceFamily']
    },
    provisioning_info: {
      creation_date: mobileprovision_content['CreationDate'],
      expire_date: mobileprovision_content['ExpirationDate'],
      device_UDID_list: mobileprovision_content['ProvisionedDevices'],
      team_name: mobileprovision_content['TeamName'],
      profile_name: mobileprovision_content['Name'],
      provisions_all_devices: mobileprovision_content['ProvisionsAllDevices'],
      ipa_export_method: ipa_export_method
    }
  }
  puts "  (i) ipa_info_hsh: #{ipa_info_hsh}"

  # - Create a Build Artifact on Bitrise
  puts
  puts '--> Create a Build Artifact on Bitrise'
  upload_url, artifact_id = create_artifact(build_url, api_token, ipa_path, 'ios-ipa')
  fail 'No upload_url provided for the artifact' if upload_url.nil?
  fail 'No artifact_id provided for the artifact' if artifact_id.nil?

  # - Upload the IPA
  puts '--> Upload the ipa'
  upload_file(upload_url, ipa_path)

  # - Finish the Artifact creation
  puts '--> Finish the Artifact creation'
  return finish_artifact(build_url,
                         api_token,
                         artifact_id,
                         JSON.dump(ipa_info_hsh),
                         notify_user_groups,
                         notify_emails,
                         is_enable_public_page
                        )
end
