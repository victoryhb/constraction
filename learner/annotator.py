import os
import glob
import json
import pandas as pd
import numpy as np
import sys
from booknlp.booknlp import BookNLP


def annotate_folder(input_folder, output_folder):
    model_params = {
        "pipeline": "entity,supersense",
        "model": "small",
        "spacy_model": "en_core_web_sm"
    }
    booknlp = BookNLP("en", model_params)

    for path in glob.glob(os.path.join(input_folder, "*.txt")):
        book_id = os.path.basename(path)[:-4]
        if os.path.exists(os.path.join(output_folder, f"{book_id}.tokens")):
            print("skipped", book_id)
            continue
        print("processing", book_id)
        booknlp.process(path, output_folder, book_id)


def annotations_to_csv(input_folder, output_folder):
    os.makedirs(output_folder, exist_ok=True)
    for file_name in os.listdir(input_folder):
        if not file_name.endswith(".tokens"):
            continue
        print("processing", file_name)
        token_path = os.path.join(input_folder, file_name)

        file_id = os.path.basename(token_path).split(".")[0]
        csv_path = os.path.join(output_folder, file_id + ".csv")
        if os.path.exists(csv_path):
            print("already processed", file_id, ", skipping")
            continue
        df = pd.read_csv(token_path, sep="\t", quotechar='非')
        mapping = {"sentence_ID": "sent_id", "token_ID_within_sentence": "id", "word": "text", "POS_tag": "upos",
                   "fine_POS_tag": "xpos", "dependency_relation": "deprel", "syntactic_head_ID": "head_id"}
        df.rename(mapping, axis=1, inplace=True)

        supersenses = pd.read_csv(os.path.join(input_folder, file_id + ".supersense"),
                                  sep="\t").to_dict(orient="records")
        rows = []
        for sense in supersenses:
            for i in range(sense['start_token'], sense['end_token'] + 1):
                rows.append({"id": i, "supersense": sense['supersense_category']})
        df['supersense'] = df.join(pd.DataFrame(rows).set_index("id")).apply(lambda x: x.supersense if pd.isnull(
            x.supersense) or x.supersense.split(".")[0][0].upper() == x.xpos[0] else np.nan, axis=1)
            
        df[list(mapping.values()) + ['lemma', 'supersense']].to_csv(csv_path)


def csv_to_json(input_folder, output_path):
    def process_sent(df_sent, file_name):
        dic_list = df_sent.to_dict(orient="records")
        for d in dic_list:
            del d['sent_id']
        all_sents.append({"file_name": file_name, "tokens": dic_list})

    all_sents = []
    paths = glob.glob(os.path.join(input_folder, "*.csv"))
    for path in paths:
        print("converting", path)
        fn = os.path.basename(path).split(".")[0]
        df = pd.read_csv(path, index_col=0).fillna("")
        df.groupby("sent_id").apply(lambda df_sent: process_sent(df_sent, fn))

    json.dump(all_sents, open(output_path, "w"))


def process_folder(input_folder, output_path):
    annotation_folder = os.path.join(input_folder, "annotations")
    annotate_folder(input_folder, annotation_folder)
    csv_folder = os.path.join(input_folder, "csv")
    annotations_to_csv(annotation_folder, csv_folder)
    csv_to_json(csv_folder, output_path)


if __name__ == "__main__":
    # process the data from first argument and output to second argument
    process_folder(sys.argv[1], sys.argv[2])
    # process_folder("data", "data/patterns.json")