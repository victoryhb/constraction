def get_ngrams(path):
    for line in open(path):
        yield line.split()[0]

old_ngrams = list(get_ngrams("/Users/yan/Downloads/patterns/json_transformed/vary/output copy.txt"))
new_ngrams = list(get_ngrams("/Users/yan/Downloads/patterns/json_transformed/vary/output.txt"))
all_ngrams = {}
for ngram in old_ngrams:
    if ngram not in all_ngrams:
        all_ngrams[ngram] = 1
for ngram in new_ngrams:
    if ngram not in all_ngrams:
        all_ngrams[ngram] = 1
all_ngrams = list(all_ngrams.keys())

new_ngrams_pos = {n:p for p, n in enumerate(new_ngrams)}
old_ngrams_pos = {n:p for p, n in enumerate(old_ngrams)}

both_groups = []
old_only = []
new_only = []

# compare the position of each element in new_ngrams_pos and old_ngrams_pos and print the difference
for n in all_ngrams:
    if n in new_ngrams_pos and n in old_ngrams_pos:
        both_groups.append((n, new_ngrams_pos[n] - old_ngrams_pos[n]))
    if n not in new_ngrams_pos:
        old_only.append(n)
    if n not in old_ngrams_pos:
        new_only.append(n)


print("Both", len(both_groups), sorted(both_groups, key=lambda x: abs(x[1])))
print("Old only", len(old_only), old_only)
print("New only", len(new_only), new_only)
    


