require 'rubygems'
require 'find'
require 'logger'
require 'sequel'
require 'audioinfo'
require 'dimensions' #image size

# TODO: add diskid calculation for albums: http://src.gnu-darwin.org/ports/audio/ruby-audiofile/work/example/cddb.rb
# TODO: add dupe finder (using diskid from the previous todo as well as individual files checksuming)
MUSIC_DIR = '/WD15EARS/webdav/share/mp3'

DB = Sequel.sqlite($0 + '.db')
LOG = Logger.new(STDOUT)
#DB.loggers << LOG
IMAGES = %w(jpg jpeg png gif)

def init_db
    [:tags, :dirs, :files].each do |t|
        return if DB.table_exists? t
    end

    DB.create_table :dirs do
        primary_key :id
        String :path, :unique => true, :null => false
        String :diskid, :
    end

    DB.create_table :files do
        primary_key :id
        foreign_key :dir_id, :dirs, :index
        String :name, :null => false, :size => 64
        String :ext, :size => 8
        boolean :is_music
        boolean :is_image
        DateTime :mtime
        integer :size, :index
    end

    DB.create_table :tags do
        primary_key :id
        foreign_key :file_id, :files, :index
        String :k, :null => false, :size => 32
        String :v
    end
end


def walk_dirs(p)
    begin
        dirs = DB[:dirs]
        files = DB[:files]
        tags = DB[:tags]

        Find.find(MUSIC_DIR) do |path|
        begin
            next unless FileTest.directory?(path)
            LOG.info(path)

            DB.transaction do
                dir_id = dirs.insert(:path => path)
                Dir.entries(path).each do |de|
                    full_path = File.join(path, de)
                    fstat = File.stat(full_path)
                    next unless fstat.file?
                    ext = File.extname(de).downcase[1..-1]
                    is_music = AudioInfo::SUPPORTED_EXTENSIONS.include? ext
                    is_image = IMAGES.include? ext
                    file_id = files.insert(
                        :dir_id => dir_id,
                        :name => de,
                        :ext => ext,
                        :is_music => is_music,
                        :is_image => is_image,
                        :mtime => fstat.mtime,
                        :size => fstat.size
                    )
                    if is_music
                        begin
                            AudioInfo.open(full_path) do |info|
                                info.to_h.each do |k,v|
                                    tags.insert(:file_id => file_id, :k => k, :v => v)
                                end
                                info.musicbrainz_infos.each do |k,v|
                                    tags.insert(:file_id => file_id, :k => 'MB: ' + k, :v => v)
                                end
                            end
                        rescue AudioInfoError
                            LOG.error($!)
                        end
                    elsif is_image
                        begin
                            wh = Dimensions.dimensions(full_path)
                            tags.insert(:file_id => file_id, :k => 'width', :v => wh[0])
                            tags.insert(:file_id => file_id, :k => 'height', :v => wh[1])
                        rescue
                            LOG.error($!)
                        end
                    end
                end
            end
            rescue Sequel::DatabaseError
                LOG.info("skipping #{path}")
            end
        end
    rescue
        LOG.error($!)
    end
end


init_db
walk_dirs(MUSIC_DIR)
