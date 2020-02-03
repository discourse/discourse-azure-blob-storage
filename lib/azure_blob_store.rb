module FileStore

  class AzureStore < ::FileStore::BaseStore

    def store_upload(file, upload, content_type = nil)
      path = get_path_for_upload(upload)
      store_file(file, path, content_type: content_type, filename: upload.original_filename, cache_locally: true)
    end

    def store_optimized_image(file, optimized_image, content_type = nil, secure: false)
      path = get_path_for_optimized_image(optimized_image)
      store_file(file, path, content_type: content_type)
    end

    def store_file(file, path, opts = {})
      filename = opts[:filename].presence || File.basename(path)
      cache_file(file, File.basename(path)) if opts[:cache_locally]
      options = {
        content_type: opts[:content_type].presence || MiniMime.lookup_by_filename(filename)&.content_type
      }
      options[:content_disposition] = "attachment; filename*=UTF-8''#{URI.encode(filename)}" unless FileHelper.is_supported_image?(filename)
      blob_service.create_block_blob(azure_blob_container, path, file, options)
      "#{absolute_base_url}/#{azure_blob_container}/#{path}"
    rescue StandardError => exception
      Rails.logger.error("Blob can not be stored: #{exception}\nUrl: #{absolute_base_url}/#{azure_blob_container}/#{path}")
    end

    def remove_file(url, path)
      return unless has_been_uploaded?(url)
      source_blob_name = path
      # copy the file in tombstone
      blob_service.copy_blob(
              azure_blob_container,
              "/tombstone/#{path}",
              azure_blob_container,
              source_blob_name)
      # delete the file
      blob_service.delete_blob(azure_blob_container, source_blob_name)
    rescue StandardError => exception
      Rails.logger.warn("Blob can not be moved to tombstone: #{exception}\nUrl: #{url}\nBlob: #{source_blob_name}")
    end

    def has_been_uploaded?(url)
      return false if url.blank?
      base_hostname = URI.parse(absolute_base_url).hostname
      return true if url[base_hostname]

      return false if SiteSetting.azure_cdn_url.blank?
      cdn_hostname = URI.parse(SiteSetting.azure_cdn_url || "").hostname
      cdn_hostname.presence && url[cdn_hostname]
    end

    def azure_blob_container
      SiteSetting.azure_blob_storage_container_name
    end

    def absolute_base_url
      @absolute_base_url ||= SiteSetting.Upload.absolute_base_url
    end

    def blob_service
      Azure::Storage::Blob::BlobService.create(storage_account_name: SiteSetting.azure_blob_storage_account_name, storage_access_key: SiteSetting.azure_blob_storage_access_key)
    end

    def purge_tombstone(grace_period)
      blob_list = blob_service.list_blobs(azure_blob_container, {prefix: "tombstone"})
      blob_list.each do |blob|
        last_modified_diff = ((Time.now.utc - Time.parse(blob.properties[:last_modified])) / 1.day).round
        blob_service.delete_blob(azure_blob_container, blob.name) if last_modified_diff > grace_period
      end
    end

    def path_for(upload)
      url = upload.try(:url)
      FileStore::LocalStore.new.path_for(upload) if url && url[/^\/[^\/]/]
    end

    def cdn_url(url)
      return url if SiteSetting.azure_cdn_url.blank?
      schema = url[/^(https?:)?\/\//, 1]
      url.sub("#{schema}#{absolute_base_url}", SiteSetting.azure_cdn_url)
    end

    def url_for(upload, force_download: false)
      upload.url
    end
    
    def download_url(upload)
      return unless upload
      "#{upload.short_path}"
    end
    
    def external?
      true
    end

  end
end
