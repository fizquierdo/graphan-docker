require 'csv'

# Print content of a HSK file
# Read rows with multiple meanings and different pronountiations are printed as multiple words

def validate_row(pinyin, pinyin_tonemarks, eng)
	raise "Wrong separation" if pinyin.count(',') != eng.count('|')
	if pinyin.include?(',') && pinyin.count(',') != pinyin_tonemarks.count(',')
		raise "Wrong separation" 
	end
end

def print_word(fields)
	puts fields.join("\t")
end

level = ARGV[0]
filename = "data/hsk/hsk#{level}.txt"
words =  CSV.read(filename,'r:bom|utf-8', headers: false, skip_blanks: true, col_sep:"\t")

print_word %w(simp trad hsk pinyin pinyin_tonemarks eng)
words.each do |word|
	simp, trad, pinyin, pinyin_tonemarks, english = word
	if pinyin.count(',') > 0 or english.count('|') > 0
		# multiple words (different meanings with different pronuntiations)
		validate_row(pinyin, pinyin_tonemarks, english)
		pin_list			 = pinyin.split(',')
		pin_marks_list = pinyin_tonemarks.split(',')
		eng_list			 = english.split('|')
		pin_list.zip(pin_marks_list, eng_list) do |pin, pin_marks, eng|
			print_word([simp, trad, level, pin.strip, pin_marks.strip, eng.strip])
		end
	else
		print_word([simp, trad, level, pinyin, pinyin_tonemarks, english])
	end
end
