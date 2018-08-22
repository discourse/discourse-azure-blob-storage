require "db_helper"
require "digest/sha1"
require "base62"

task "uploads:migrate_to_azure_blob" => :environment do
  require File.expand_path("../../azure_blob_helper.rb", __FILE__)
  require "file_store/local_store"

  ENV["RAILS_DB"] ? migrate_to_azure_blob : migrate_to_azure_blob_all_sites
end

def migrate_to_azure_blob_all_sites
  RailsMultisite::ConnectionManagement.each_connection { migrate_to_azure_blob }
end

def migrate_to_azure_blob
  # make sure azure blob storage is enabled
  if !SiteSetting.azure_blob_storage_enabled
    puts "You must enable discourse-azure-blob-storage plugin before running this task"
    return
  end

  db = RailsMultisite::ConnectionManagement.current_db

  puts "Migrating uploads to Azure Blob Storage for '#{db}'..."

  azure_blob_store = FileStore::AzureStore.new
  local = FileStore::LocalStore.new

  # Migrate all uploads
  Upload.where.not(sha1: nil)
    .where("url NOT LIKE '#{azure_blob_store.absolute_base_url}%'")
    .find_each do |upload|
    # remove invalid uploads
    if upload.url.blank?
      upload.destroy!
      next
    end
    # store the old url
    from = upload.url
    # retrieve the path to the local file
    path = local.path_for(upload)
    # make sure the file exists locally
    if !path || !File.exists?(path)
      putc "X"
      next
    end

    begin
      file = File.open(path)
      content_type = `file --mime-type -b #{path}`.strip
      to = azure_blob_store.store_upload(file, upload, content_type)
    rescue
      putc "X"
      next
    ensure
      file.try(:close!) rescue nil
    end

    # remap the URL
    DbHelper.remap(from, to)

    putc "."
  end
end
