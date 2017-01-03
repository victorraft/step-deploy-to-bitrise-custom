require_relative 'common'

# -----------------------
# --- upload file
# -----------------------

def deploy_file_to_bitrise(file_path, build_url, api_token)
  puts
  puts
  puts "# Deploying file: #{file_path}"

  file_size = File.size(file_path)

  file_info_hsh = {
      file_size_bytes: file_size,
      app_info: {
          app_name: file_path,
          package_name: 0,
          version_code: 0,
          version_name: 0,
          min_sdk_version: 0
      }
  }
  puts "  (i) file_info_hsh: #{file_info_hsh}"

  # - Create a Build Artifact on Bitrise
  puts '--> Create a Build Artifact on Bitrise'
  upload_url, artifact_id = create_artifact(build_url, api_token, file_path, 'file')
  fail 'No upload_url provided for the artifact' if upload_url.nil?
  fail 'No artifact_id provided for the artifact' if artifact_id.nil?

  # - Upload the file
  puts '--> Upload the file'
  upload_file(upload_url, file_path)

  # - Finish the Artifact creation
  puts '--> Finish the Artifact creation'
  return finish_artifact(build_url,
                         api_token,
                         artifact_id,
                         JSON.dump(file_info_hsh),
                         '',
                         '',
                         true
                         )
end