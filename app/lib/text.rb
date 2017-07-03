####
# Annotated texts
# Given an input text, and a set of words from the user
# it annotates the text based on user knowledge and word level
# Returns a score for the text and colors the words according to knowledge

class AnnotatedText

	attr_reader :words, :avg_score, :hsk_words, :total_words, :known_proportion

	def initialize(text, records)
		# records are words existing in the system for a given user 
		# (rel is the relationship of a given user with this word)
		# records = [{simp: str, level: str, pinyin: str, rel: str}, ]
		@punct_regex = /[\. 、。，:：?"“”!！\s]/
		@text = text
		@records = records
		annotate
	end

	def annotate
		@scores = []
		@words = []
		@words_known = 0
		# Segment and calculate avg_score
		segment
		@avg_score = @scores.inject{ |sum, el| sum + el }.to_f / @scores.size
		@hsk_words = @words.select{|w| w[:type] == :hsk_word}.size
		@total_words = @words.select{|w| w[:type] != :punctuation}.size
		@known_proportion = @words_known.to_f / @total_words.to_f
	end

	private
	def segment
		# A very naive segmentation strategy
		# For each position in the text:
		#  if on the the next words of size [1,4] is a known HSK word we consider this a word,
		#  otherwise we consider it an uknown word-character of size one 
		#  or a punctuation mark if it is included in the punct_regex
		simps = @records.map{|w| w[:simp]}
		i = 0
		while i < @text.size
			len = 4 
			found = false
			while not found and len > 0
				w =  @text[i...i+len]
				if simps.include? w
					found = true
					break
				end
				len -= 1
			end
			@words << add_word(found, w)
			i += w.size 
		end
	end

	def add_word(found, w)
			# Identify word as hsk, char (hanzi but not hsk word) or punctuation mark
			if found
				fw = @records.select{|this_word| this_word[:simp] == w}[0]
				word = {type: :hsk_word, text: w, word: fw}
				@scores << fw[:level].to_f
				@words_known += 1 if fw[:rel] == "KNOWS"
			else
				word = {text: w, word: nil}
				if w.match(@punct_regex).nil?
					word[:type] = :char 
				else
					word[:type] = :punctuation 
				end
			end
			word
	end

end
