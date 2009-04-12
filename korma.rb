require 'rubygems'
require 'grit'
require 'redcloth'
require "builder"
require "fileutils"
require "erb"
require 'digest/md5'

KORMA_DIR = File.expand_path(File.dirname(__FILE__))

module Korma
  module  Blog

    include FileUtils

    class Entry 
      def initialize(blob, author="")
        entry_data = Blog.parse_entry(blob.data)

        @filename        = "#{blob.name}.html"
        @author          = Blog.authors[author]
        @title           = entry_data[:title]
        @description     = entry_data[:description]
        @entry           = entry_data[:entry] 
        @published_date  = commit_date(blob, @author.base_path)
        @url             = "/#{@author.base_path}#{@filename}"
      end

      attr_reader :title, :description, :entry, :published_date, :url, :author, :filename 

      private

      def commit_date(blob, base_path)
        repo = Korma::Blog.repository
        Grit::Blob.blame(repo, repo.head.commit, "#{base_path}#{blob.name}")[0][0].date
      end

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
        "/#{base_path}"
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
      entry =~ /=title(.*)=description(.*)=entry(.*)/m   
      { :title => $1.strip, :description => $2.strip, :entry => $3.strip }
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
      tree = repository.tree / "posts/#{author}"
      return [] unless tree
      tree.contents.map { |e| Entry.new(e, author)  } 
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
      node = (Korma::Blog.repository.tree / "about/#{author}")

      layout { RedCloth.new(ERB.new(node.data).result(binding)).to_html }
    end

    def update_stylesheet
      if css = repository.tree / "styles.css"
        write "styles.css", css.data
      end
    end

    def layout
      if layout = repository.tree / "layout.erb"
        ERB.new(layout.data).result(binding)
      else
        yield
      end
    end

    def generate_static_files
      mkdir_p www_dir
      cd www_dir
      write "feed.xml", site_feed
      
      write 'index.html', site_index

      mkdir_p "feed"
      mkdir_p "about"

      if about = repository.tree / "about/index"
        write "about/index.html", layout { RedCloth.new(about.data).to_html }
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
      if blob = repository.tree / "views/#{file}.erb"
        engine = ERB.new(blob.data)
        layout { engine.result(binding) }
      else
        raise "File not found #{file}.erb"
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
              xml.title       entry.title
              xml.description entry.description
              xml.author      "#{entry.author.name} via rubybestpractices.com"
              xml.pubDate     entry.published_date
              xml.link        entry.url
              xml.guid        entry.url
            end
          end
        end
      end
    end 

  end
end

Korma::Blog.repository   = Grit::Repo.new(ARGV[0])
config =  YAML.load((Korma::Blog.repository.tree / "korma_config.yml").data)

Korma::Blog.title  = config['title']
Korma::Blog.domain = config['domain']
Korma::Blog.description = config['description']
Korma::Blog.authors = config['authors']
Korma::Blog.www_dir  = ARGV[1] || "www"
Korma::Blog.generate_static_files
