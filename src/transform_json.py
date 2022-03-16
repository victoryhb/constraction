import json
import os
import time

substitutions = {
    "upos": {"PROPN": "NOUN", "PRON": "NOUN"},
    "xpos": {"WDT": "WH", "WP": "WH", "WP$": "WH", "WRB": "WH"},
    "lemma": {
        "m": "be", "an": "a", "n't": "not", "'ll": "will", "wo": "will", "ca": "can", "sha": "shall",
        "ve": "have",
        "myself": "oneself", "yourself": "oneself", "herself": "oneself",
        "himself": "oneself", "itself": "oneself", "ourselves": "oneself", "themselves": "oneself",
        "my": "one's", "your": "one's", "her": "one's", "his": "one's", "its": "one's", "our": "one's", "their": "one's"
    },
}


def load_and_transform(json_path):
    sentences = json.load(open(json_path))
    for sentence in sentences:
        for token in sentence["tokens"]:
            for key, value in substitutions.items():
                if token[key] in value:
                    token[key] = value[token[key]]
    return sentences

# TODO: transform the json file, and slice it into several segments


in_json_path = "~/Downloads/patterns/json/merge-dep-supersenses.json"
out_data_folder = "~/Downloads/patterns/json_transformed/"
os.makedirs(out_data_folder, exist_ok=True)

out_files = {
    "": None,
    "1000": 1000,
    "10000": 10000,
    "100000": 100000,
}

# time the elapsed time for running the function
start = time.time()
sentences = load_and_transform(in_json_path)
for file_name, max_sentences in out_files.items():
    if max_sentences is None:
        max_sentences = len(sentences)
    out_json_path = os.path.join(out_data_folder, os.path.basename(in_json_path)[:-5] + file_name + ".json")
    print("Saving to ", out_json_path)
    json.dump(sentences[:max_sentences], open(out_json_path, "w"))
print("elapsed time:", time.time() - start)
