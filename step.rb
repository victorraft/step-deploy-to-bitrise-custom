require 'optparse'
require 'tempfile'
require_relative 'zip_file_generator'
require_relative 'uploaders/file_uploader'
require_relative 'uploaders/ipa_uploader'
require_relative 'uploaders/apk_uploader'

# ----------------------------
# --- Options

def fail_with_message(message)
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

options = {
    build_url: nil,
    api_token: nil,
    is_compress: false,
    deploy_path: nil,
    notify_user_groups: nil,
    notify_email_list: nil,
    is_enable_public_page: true
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-u', '--buildurl URL', 'Build URL') { |u| options[:build_url] = u unless u.to_s == '' }
  opts.on('-t', '--apitoken TOKEN', 'API Token') { |t| options[:api_token] = t unless t.to_s == '' }
  opts.on('-c', '--compress BOOL', 'Is Compress') { |c| options[:is_compress] = true if c.to_s == 'true' }
  opts.on('-d', '--deploypath PATH', 'Deploy Path') { |d| options[:deploy_path] = d unless d.to_s == '' }
  opts.on('-g', '--usergroups ARRAY', 'Notify User Groups') { |g| options[:notify_user_groups] = g unless g.to_s == '' }
  opts.on('-e', '--emaillist ARRAY', 'Notify Email List') { |e| options[:notify_email_list] = e unless e.to_s == '' }
  opts.on('-p', '--publicpage BOOL', 'Enable Public Page') { |p| options[:is_enable_public_page] = false if p.to_s == 'false' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No build_url provided') unless options[:build_url]
fail_with_message('No api_token provided') unless options[:api_token]
fail_with_message('No deploy_path provided') unless options[:deploy_path]

options[:deploy_path] = File.absolute_path(options[:deploy_path])

if !Dir.exist?(options[:deploy_path]) && !File.exist?(options[:deploy_path])
  fail_with_message('Deploy source path does not exist at the provided path: ' + options[:deploy_path])
end

puts
puts '========== Configs =========='
puts " * Build URL: #{options[:build_url]}"
puts " * Build's API Token: #{options[:api_token]}"
puts " * is_compress: #{options[:is_compress]}"
puts " * deploy_path: #{options[:deploy_path]}"
puts " * notify_user_groups: #{options[:notify_user_groups]}"
puts " * notify_email_list: #{options[:notify_email_list]}"
puts " * is_enable_public_page: #{options[:is_enable_public_page]}"

# -----------------------
# --- functions
# -----------------------

def compress_and_upload(path, build_url, api_token)
  puts
  puts '## Compressing the Deploy directory'
  tempfile = Tempfile.new(::File.basename(path))
  begin
    zip_archive_path = tempfile.path + '.zip'
    puts " (i) zip_archive_path: #{zip_archive_path}"
    zip_gen = ZipFileGenerator.new(path, zip_archive_path)
    zip_gen.write
    tempfile.close

    fail 'Failed to create compressed ZIP file' unless File.exist?(zip_archive_path)

    deploy_file_to_bitrise(zip_archive_path, build_url, api_token)

    fail 'Failed to export BITRISE_ZIPPED_APKS_PATH' unless system("envman add --key BITRISE_ZIPPED_APKS_PATH --value '#{zip_archive_path}'")
  rescue => ex
    raise ex
  ensure
    tempfile.close
    tempfile.unlink
  end
end

# ----------------------------
# --- Main

begin
  public_page_url = ''
  dic = {}

  puts
  puts '## Uploading the content of the Deploy directory separately'
  entries = Dir.entries(options[:deploy_path])
  entries.delete('.')
  entries.delete('..')

  entries = entries
                .map { |e| File.join(options[:deploy_path], e) }
                .select { |e| !File.directory?(e) }

  puts
  puts '======= List of files ======='
  puts ' No files found to deploy' if entries.length == 0
  entries.each { |filepth| puts " * #{filepth}" }
  puts '============================='
  puts

  all_public_urls = ''
  entries.each do |filepth|
    disk_file_path = filepth

    a_public_page_url = ''
    if disk_file_path.match('.*.ipa')
      a_public_page_url = deploy_ipa_to_bitrise(
          disk_file_path,
          options[:build_url],
          options[:api_token],
          options[:notify_user_groups],
          options[:notify_email_list],
          options[:is_enable_public_page]
      )
    elsif disk_file_path.match('.*.apk')
      a_public_page_url = deploy_apk_to_bitrise(disk_file_path,
                                                options[:build_url],
                                                options[:api_token],
                                                options[:notify_user_groups],
                                                options[:notify_email_list],
                                                options[:is_enable_public_page]
      )
    else
      a_public_page_url = deploy_file_to_bitrise(disk_file_path,
                                                 options[:build_url],
                                                 options[:api_token]
      )
    end

    filename = File.basename(disk_file_path)
    filename_array = filename.split('-')
    station = filename
    if filename_array.count > 2
      station = filename_array[1]
    end

    if dic[station] == nil
      dic[station] = "\n"
    end
    a_public_page_url = a_public_page_url.strip! || a_public_page_url
    dic[station] = dic[station] + a_public_page_url + "\n"

    all_public_urls = all_public_urls + File.basename(disk_file_path) + " " + a_public_page_url + "\n"
    puts "(i) Public install page url: #{File.basename(disk_file_path)} (#{a_public_page_url})"

    public_page_url = a_public_page_url if public_page_url == '' && !a_public_page_url.nil? && a_public_page_url != ''
  end

  compress_and_upload(options[:deploy_path], options[:build_url], options[:api_token])
  # if options[:is_compress]
  # end

  all_public_urls = dic.sort.map { |k, v| "*#{k.upcase}*: #{v}" }.join

  # - Success
  fail 'Failed to export BITRISE_PUBLIC_INSTALL_PAGE_URL' unless system("envman add --key BITRISE_PUBLIC_INSTALL_PAGE_URL --value '#{public_page_url}'")
  fail 'Failed to export BITRISE_PUBLIC_INSTALL_PAGE_URLS' unless system("envman add --key BITRISE_PUBLIC_INSTALL_PAGE_URLS --value '#{all_public_urls}'")

  puts
  puts '## Success'
  puts "(i) You can find the Artifact on Bitrise, on the [Build's page](#{options[:build_url]})"
  puts "(i) Public instal page urls: \n#{all_public_urls}"
rescue => ex
  fail_with_message(ex)
end

exit 0