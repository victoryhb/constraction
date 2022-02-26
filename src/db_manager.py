import os
import sys
import json
import datetime
from collections import defaultdict, Counter
import sqlmodel
from sqlmodel import Field, Session, SQLModel, create_engine, select
import pandas as pd

SQLModel.metadata.clear()


class Task(SQLModel, table=True):
    id: int = Field(primary_key=True, index=True)
    name: str
    config: str
    time_added: datetime.datetime = Field(sa_column=sqlmodel.Column(sqlmodel.DateTime(timezone=True), nullable=True))


class Pattern(SQLModel, table=True):
    id: int = Field(primary_key=True, index=True)
    form: str
    left: str  # the left component of the form
    right: str  # the right component of the form
    count: int
    score: float
    task_id: int = Field(index=True, foreign_key=Task.id)


class Sentence(SQLModel, table=True):
    id: int = Field(primary_key=True, index=True)
    file_name: str


class Position(SQLModel, table=True):
    id: int = Field(primary_key=True)
    pattern_id: int = Field(index=True, foreign_key=Pattern.id)
    sentence_id: int = Field(index=True)
    token_ids: str


class Token(SQLModel, table=True):
    id: int = Field(primary_key=True)
    sentence_id: int = Field(primary_key=True, index=True)
    text: str
    lemma: str
    upos: str
    xpos: str
    head_id: int
    deprel: str
    supersense: str


class DBManager:
    def __init__(self, db_path) -> None:
        self.db_path = db_path
        self.engine = None
        self.set_engine()

    def set_engine(self):
        if self.engine:
            self.engine.dispose()
        self.engine = create_engine(f"sqlite:///{self.db_path}")

    def create_database(self, on_exist="fail"):
        if os.path.exists(self.db_path):
            if on_exist == "ignore":
                return
            elif on_exist == "fail":
                print("Database already exists.")
                return
            elif on_exist == "overwrite":
                os.remove(self.db_path)
        SQLModel.metadata.create_all(self.engine)

    def new_task(self, name, config):
        with Session(self.engine) as session:
            task = Task(name=name, config=json.dumps(config), 
                    time_added=datetime.datetime.now())
            session.add(task)
            session.commit()
            return task.id

    def get_all_tasks(self):
        with Session(self.engine) as session:
            query = session.query(Task)
            return [dict(task) for task in query.all()]

    def query_pattern(self, pattern, limit=None):
        # using sqlmodel, select all rows from table "position" where pattern_id = (the id from the table pattern where form = pattern)
        parts = pattern.split("~")
        with Session(self.engine) as session:
            statement = (select(Token, Position)
                         .where(Position.pattern_id == Pattern.id)
                         .where(Pattern.form == pattern)
                         .where(Token.sentence_id == Position.sentence_id))
            sent_idx_to_tokens = defaultdict(list)
            # print(session.exec(statement).all())
            for token, pos in session.exec(statement):
                # if token.sentence_id not in sent_idx_to_token_ids:  # avoid repeated effort
                token_ids = tuple(int(i) for i in pos.token_ids.split(","))
                pos_ids = (token.sentence_id,) + token_ids
                sent_idx_to_tokens[pos_ids].append(token)
        results = {}
        results['data'] = []
        label_to_text = defaultdict(Counter)
        for pos_ids, tokens in sent_idx_to_tokens.items():
            sent_idx, token_ids = pos_ids[0], pos_ids[1:]
            # token_ids = sent_idx_to_token_ids[sent_idx]
            texts_n_labels = []
            match_idx = 0
            for token in tokens:
                if token.id in token_ids:
                    try:
                        label = parts[match_idx]
                        text_n_label = (token.text, label)
                        label_to_text[label][token.text.lower()] += 1
                        match_idx += 1
                    except:
                        break
                else:
                    text_n_label = (token.text, None)
                texts_n_labels.append(text_n_label)
            rs = {
                "sent_idx": sent_idx,
                "token_ids": token_ids,
                "tokens": texts_n_labels,
            }
            results['data'].append(rs)
        token_stats = {}
        # calculate the percenage of each text in each label
        for label, text_counter in label_to_text.items():
            token_stats[label] = {}
            sum_count = sum(text_counter.values())
            for text, count in text_counter.most_common(10):
                token_stats[label][text] = {"count": count, "percent": round(count / sum_count * 100, 2)}
        results["token_stats"] = token_stats
        return results

    def get_pattern_df(self, task_id=None, limit=None):
        def transform_pattern_form(form):
            parts = form.split("~")
            for i, part in enumerate(parts):
                if "." in part or (len(part) > 1 and all(c.isupper() for c in part)):
                    parts[i] = "<" + part.lower() + ">"
            return " ".join(parts)
        values = []
        with Session(self.engine) as session:
            query = session.query(Pattern)
            if task_id:
                query = query.where(Pattern.task_id == task_id)
            if limit is not None:
                query = query.limit(limit)
            for pattern in query.all():
                values.append(dict(pattern))
        df = pd.DataFrame(values).drop(["_sa_instance_state", "id"], axis=1).reset_index()
        df['form'] = df['form'].apply(transform_pattern_form)
        df['index'] += 1
        cols = ['index', 'form', 'left', 'right', 'count', 'score']
        return df.reindex(columns=cols)

if __name__ == "__main__":
    output_folder = "/Users/yan/Downloads/patterns/1000/"
    if sys.platform == "linux":
        output_folder = "/home/victor/code/corpus/cxgnet/nim/patterns/"
    db_path = os.path.join(output_folder, "db.sqlite3")

    manager = DBManager(db_path)
    manager.create_database()

    pattern = "NOUN~NOUN~have~VBN"
    print(manager.query_pattern(pattern))
