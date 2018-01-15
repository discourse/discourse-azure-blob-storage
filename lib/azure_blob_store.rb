module FileStore

  class AzureStore < ::FileStore::BaseStore

    def initialize
      Azure.config.storage_account_name = SiteSetting.azure_blob_storage_account_name
      Azure.config.storage_access_key = SiteSetting.azure_blob_storage_access_key
    end

    def store_upload(file, upload, content_type = nil)
      path = get_path_for_upload(upload)
      store_file(file, path, content_type: content_type)
    end

    def store_optimized_image(file, optimized_image, content_type = nil)
      path = get_path_for_optimized_image(optimized_image)
      store_file(file, path, content_type: content_type)
    end

    def store_file(file, path, opts = {})
      options = {
        content_type: opts[:content_type].presence || MiniMime.lookup_by_filename(filename)&.content_type
      }
      blob_service.create_block_blob(azure_blob_container, path, file, options)
      "#{absolute_base_url}/#{azure_blob_container}/#{path}"
    end

    def remove_file(url, path)
      return unless has_been_uploaded?(url)
      source_blob_name = path
      # copy the file in tombstone
      blob_service.copy_blob(
              azure_blob_container,
              "/tombstone/#{path}",
              azure_blob_container,
              source_blob_name,
              metadata: {'removed_at': DateTime.now}
              )
      # delete the file
      blob_service.delete_blob(azure_blob_container, source_blob_name)
    end

    def has_been_uploaded?(url)
      return false if url.blank?
      base_hostname = URI.parse(absolute_base_url).hostname
      return true if url[base_hostname]
    end

    def azure_blob_container
      SiteSetting.azure_blob_storage_container_name
    end

    def absolute_base_url
      storage_account_name = SiteSetting.azure_blob_storage_account_name
      "//#{storage_account_name}.blob.core.windows.net/"
    end

    def blob_service
      Azure::Blob::BlobService.new
    end

    def purge_tombstone(grace_period)
      blob_list = blob_service.list_blobs(azure_blob_container, {prefix: "tombstone"})
      blob_list.each do |blob|
        removal_date = blob_service.get_blob_metadata(azure_blob_container, blob.name).metadata['removed_at']
        age = (Date.today - Date.parse(removal_date)).to_i
        if age > grace_period
          blob_service.delete_blob(azure_blob_container, blob.name)
        end
      end
    end

    def path_for(upload)
      url = upload.try(:url)
      FileStore::LocalStore.new.path_for(upload) if url && url[/^\/[^\/]/]
    end

    def external?
      true
    end

  end
end