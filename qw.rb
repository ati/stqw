require 'rubygems'
require 'logger'
require 'sequel'

DB = Sequel.sqlite('st.rb.db')
DB.pragma_set('case_sensitive_like', 0)

# select distinct dir_id from files where ext = f
def all_disks
    DB["select distinct d.path, d.id from dirs d
        join files f on d.id = f.dir_id
        where f.is_music = 't'"]
end


all_disks.each do |r|
    tags = []
    files = DB[:files]
    tags << DB["select distinct ext from files where is_music = 't' and dir_id = ?", r[:id]].map(:ext)
    tags << 'noimage' if 
        files.filter(:dir_id => r[:id], :is_image => true).count == 0
    tags << 'nocover' if 
        !tags.include?('noimage') &&
        DB["select id from files where is_music = 't' and dir_id = ? and ((name like 'cover.%') or (name like 'folder.%'))", r[:id]].count == 0

    # disk contain files tagged by 'unknown artist' and 'unknown album'
    tags << 'untags' if 
        DB["select f.id from files f
        join tags t on f.id = t.file_id
        where
        f.dir_id = ?
        and
        (
            (t.k = 'artist' and t.v like 'unknown%')
            or (t.k = 'album' and t.v like 'unknown%')
        )
        group by f.id
        having count(*) = 2", r[:id]].count > 1 

    tags << 'notags' if
        !tags.include?('untags') &&
        DB["select distinct f.id from files f
        left outer join tags t on f.id = t.file_id
        where
        f.is_music = 't'
        and f.dir_id = ?
        and t.id is null
        and f.is_music = 't'", r[:id]].count > 0

    tags << 'onefile' if
        files.filter(:dir_id => r[:id], :is_music => true).count == 1

    prefix = tags.empty?? '' : '#' + tags.join(',#')
    puts [prefix, r[:path]].join(' ')
end

