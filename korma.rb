require 'rubygems'
require 'redcloth'
require "builder"
require "fileutils"
require "erb"
require 'digest/md5'
require "pathname"
require "time"

KORMA_DIR = File.expand_path(File.dirname(__FILE__))

module Korma
  module  Blog

    include FileUtils

    class Entry 
      def initialize(file, author="")
        entry_data = Blog.parse_entry(file.read)

        @filename        = "#{file.basename}.html"
        @author          = Blog.authors[author]
        @title           = entry_data[:title]
        @description     = entry_data[:description]
        @entry           = entry_data[:entry] 
        @published_date  = entry_data[:timestamp]
        @url             = "/#{@author.base_path}#{@filename}"
      end

      attr_reader :title, :description, :entry, :published_date, :url, :author, :filename 

      private

    end

    class Author

      def initialize(account, name, email)
        @account, @name, @email = account, name, email
      end
     
      attr_reader :account, :name, :email

      def base_path
        "posts/#{account}/"
      end

      def index_uri
        "/#{base_path}index.html"
      end

      def bio_uri
        "/about/#{account}.html"
      end

      def feed_uri
        "/feed/#{account}.xml"
      end

      def gravatar(size=80)
        "http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}?s=#{size}"
      end

    end

    extend self 
    attr_accessor :repository, :www_dir, :title, :domain, :description
    attr_reader :authors

    def authors=(data)
      @authors = {}

      data.each do |k,v|
        @authors[k] = Author.new(k, v['name'], v['email'])
      end
    end

    def normalize_path(path)
      path.gsub(%r{/+},"/")
    end
    
    def parse_entry(entry)
      entry =~ /=title(.*)=timestamp(.*)=description(.*)=entry(.*)/m   
      { :title => $1.strip, :description => $3.strip, 
        :entry => $4.strip, :timestamp => Time.parse($2) }
    end

    def author_names
      authors.keys
    end

    def all_entries
      entries = []
      author_names.each do |a|
        entries += entries_for_author(a)
      end
      entries.sort { |a,b| b.published_date <=> a.published_date }
    end

    def site_feed
      to_rss(all_entries)
    end

    def entries_for_author(author)
      tree = Pathname.glob "#{repository}posts/#{author}/*"
      return [] unless tree
      tree.map { |e| Entry.new(e, author)  } 
    end

    def feed(author)
      to_rss entries_for_author(author).sort { |a,b| b.published_date <=> a.published_date }     
    end

    def author_index(author)
      @author  = authors[author]
      @entries = entries_for_author(author).sort { |a,b| b.published_date <=> a.published_date }
      erb :author_index
    end

    def site_index
      @entries = Korma::Blog.all_entries
      erb :index
    end

    def bio(author)
      @author = Korma::Blog.authors[author]
      file = repository + "about/#{author}"

      layout { RedCloth.new(ERB.new(file.read).result(binding)).to_html }
    end

    def update_stylesheet
      file = repository + "styles.css"

      if file.exist?
        write "styles.css", file.read
      end
    end

    def layout
      file = repository + "layout.erb"

      if file.exist?
        ERB.new(file.read).result(binding)
      else
        yield
      end
    end

    def generate_static_files
      # fix relative path names
      self.repository = File.absolute_path(repository) + "/"

      mkdir_p www_dir
      cd www_dir
      write "feed.xml", site_feed
      
      write 'index.html', site_index

      mkdir_p "feed"
      mkdir_p "about"

      about = repository + "about/index"

      if about.exist?
        write "about/index.html", layout { RedCloth.new(about.read).to_html }
      end

      update_stylesheet

      author_names.each do |author|
        write "feed/#{author}.xml", feed(author)
        mkdir_p "posts/#{author}"
        write "posts/#{author}/index.html", author_index(author)
        entries_for_author(author).each do |e|
          @post = e
          @author  = authors[author]
          @contents = RedCloth.new(e.entry).to_html
          write "posts/#{author}/#{e.filename}", erb(:post)
        end
        write "about/#{author}.html", bio(author)
      end

    end

    def write(file, contents)
      File.open(file, "w") { |f| f << contents }
    end

    def erb(file)
      file = repository + "views/#{file}.erb"
      
      if File.exist? file
        engine = ERB.new(file.read)
        layout { engine.result(binding) }
      else
        raise "File not found #{file}"
      end
    end

    def to_rss(entries)
      xml = Builder::XmlMarkup.new
      xml.instruct!
      xml.rss :version => "2.0" do
        xml.channel do
          xml.title       title
          xml.link        "http://#{domain}/"
          xml.description  description
          xml.language    "en-us"

          entries.each do |entry|
            xml.item do
              xml.title       entry.title.gsub( %r{</?[^>]+?>}, '' )
              xml.description  RedCloth.new(entry.entry).to_html
              xml.author      "#{entry.author.email} (#{entry.author.name})"
              xml.pubDate     entry.published_date.rfc822
              xml.link        "http://#{domain}#{entry.url}"
              xml.guid        "http://#{domain}#{entry.url}"
            end
          end
        end
      end
    end 

  end
end

Korma::Blog.repository   = Pathname.new(ARGV[0])
config =  YAML.load((Korma::Blog.repository + "korma_config.yml").read)

Korma::Blog.title  = config['title']
Korma::Blog.domain = config['domain']
Korma::Blog.description = config['description']
Korma::Blog.authors = config['authors']
Korma::Blog.www_dir  = ARGV[1] || "www"

Korma::Blog.generate_static_files
