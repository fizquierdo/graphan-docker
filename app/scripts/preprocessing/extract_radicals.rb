require "csv"
require 'nokogiri'
require 'open-uri'

def decompose(character, list_id = 0)
	url = 'http://www.hanzicraft.com/character/' + character.to_s
	url = URI.encode url
	html = open(url)
	page = Nokogiri::HTML(html.read)
	decompositions = []
	page.css("div.decompbox").each_with_index do |box, i|
		# 0 decomposes in pairs
		# 1 decomposes in radicals
		# 2 decomposes following some graphical pattern
		begin
			_, decomp = box.text.delete("\n").to_s.split('=>')
			decompositions[i] = decomp.strip.split(',').map{|n|n.strip}
		rescue
			decompositions[i] = []
		end
	end
	decompositions[list_id]
end

# Input tsv file with words in a column with header "simp"
filename = ARGV[0]

characters = []
words =  CSV.read(filename, headers: true, skip_blanks: true, col_sep: "\t")
words.each do |word|
	simp = word["simp"]
	simp.split('').each do |ch|
		characters << ch unless characters.include? ch
	end
end

puts "character,radicals"
characters.each do |ch|
	radicals = decompose(ch, 1).map{|rad| rad.split('(').first}.join(";")
	puts ch + ',' + radicals
end
