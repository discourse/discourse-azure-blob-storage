require 'azure/storage/blob'
require 'azure/storage/common'
require './plugins/discourse-azure-blob-storage/lib/azure_blob_helper'

def azure_helper
  @azure_helper ||= AzureBlobHelper.new
end

def upload_asset(path, remote_path, content_type, content_encoding = nil)
  options = {
    cache_control: 'max-age=31556952, public, immutable',
    content_type: content_type,
    blob_content_type: content_type
  }

  if content_encoding
    options[:content_encoding] = content_encoding
    options[:blob_content_encoding] = content_encoding
  end

  puts "Uploading: #{remote_path}"
  azure_helper.upload(remote_path, IO.binread(File.path(path)), options)
end

def ensure_azure_storage_configured!
  unless GlobalSetting.use_azure?
    STDERR.puts "ERROR: Ensure Azure Storage is configured in config/discourse.conf of environment vars"
    exit 1
  end
end

task 'azure:upload_assets' => :environment do
  ensure_azure_storage_configured!
  azure_helper.ensure_cors!

  assets.each do |asset|
    upload_asset(*asset)
  end
end
