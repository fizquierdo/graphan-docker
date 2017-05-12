#!/bin/sh

# Merge all HSK files into a single
HSKFILE=data/hsk_words.tsv
rm -f $HSKFILE

for LEVEL in 1 2 #3 4 5 6
do
	ruby scripts/preprocessing/read_hsk_sources.rb ${LEVEL} >> $HSKFILE
done

# TODO Now that all have been merged we can invoke the decomposition
#ruby scripts/scrapping/decomposer.rb ${LEVEL} > data/hsk${LEVEL}_radicals.csv
