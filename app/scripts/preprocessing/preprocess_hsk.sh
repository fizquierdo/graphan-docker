#!/bin/sh


# Merge all HSK files into a single
HSKFILE=data/hsk_words.tsv
HSK_RADICALS_FILE=data/hsk_radicals.csv
rm -f $HSKFILE
rm -f $HSK_RADICALS_FILE

echo "Merging words"
for LEVEL in 1 2 3 4 5 6
do
	ruby scripts/preprocessing/read_hsk_sources.rb ${LEVEL} >> $HSKFILE
done

echo "Extracting radicals from words"
ruby scripts/preprocessing/extract_radicals.rb ${HSKFILE} > ${HSK_RADICALS_FILE}
