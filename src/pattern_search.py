import json

path = "/Users/yan/Downloads/patterns/json_transformed/merge-dep-baby1000.json"
sentences = json.load(open(path))


count = 0
targets = [("go", "lemma"), ("to", "lemma"), ("VERB", "upos")]
targets = [("go", "lemma"), None, ("to", "lemma")]
targets = [("award", "lemma")]
modals = set()
for sentence in sentences:
    tokens = sentence['tokens']
    for i, token in enumerate(tokens):
        if token['xpos'] == "MD":
            modals.add(token['lemma'])
        if i + len(targets) - 1 >= len(tokens):
            continue
        is_match = True
        for j in range(len(targets)):
            if not targets[j]:  # None
                continue
            text, feature = targets[j]
            if tokens[i + j][feature] != text:
                is_match = False
                break
        if is_match:
            print([(t['lemma'], t['xpos']) for t in tokens])
            count += 1
print(count)
print(modals)