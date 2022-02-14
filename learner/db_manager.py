import os
import sys
from collections import defaultdict
from sqlmodel import Field, Session, SQLModel, create_engine, select


class Pattern(SQLModel, table=True):
    id: int = Field(primary_key=True, index=True)
    form: str
    left: str  # the left component of the form
    right: str  # the right component of the form
    count: int
    score: float


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
        self.engine = create_engine(f"sqlite:///{db_path}")

    def create_database(self):
        SQLModel.metadata.create_all(self.engine)

    def query_pattern(self, pattern):
        print("pattern:", pattern, end="; ")
        # using sqlmodel, select all rows from table "position" where pattern_id = (the id from the table pattern where form = pattern)
        parts = pattern.split("~")
        with Session(self.engine) as session:
            statement = (select(Token, Position)
                         .where(Position.pattern_id == Pattern.id)
                         .where(Pattern.form == pattern)
                         .where(Token.sentence_id == Position.sentence_id))
            # print(statement)
            sent_idx_to_tokens = defaultdict(list)
            # print(session.exec(statement).all())
            for token, pos in session.exec(statement):
                # if token.sentence_id not in sent_idx_to_token_ids:  # avoid repeated effort
                token_ids = tuple(int(i) for i in pos.token_ids.split(","))
                pos_ids = (token.sentence_id,) + token_ids
                sent_idx_to_tokens[pos_ids].append(token)
        print("sent count:", len(sent_idx_to_tokens))
        results = []
        for pos_ids, tokens in sent_idx_to_tokens.items():
            sent_idx, token_ids = pos_ids[0], pos_ids[1:]
            # token_ids = sent_idx_to_token_ids[sent_idx]
            texts = []
            match_idx = 0
            for token in tokens:
                if token.id in token_ids:
                    # if token.text == parts[match_idx]:
                    #     text = (token.text, "#")
                    # else:
                        # text = (token.text, parts[match_idx])
                    text = (token.text, parts[match_idx])
                    match_idx += 1
                else:
                    text = (token.text, None)
                texts.append(text)
            rs = {
                "sent_idx": sent_idx,
                "token_ids": token_ids,
                "tokens": texts
            }
            results.append(rs)
        # print(list(sent_idx_to_tokens.keys()))
        return results


if __name__ == "__main__":
    output_folder = "/Users/yan/Downloads/patterns/1000/"
    if sys.platform == "linux":
        output_folder = "/home/victor/code/corpus/cxgnet/nim/patterns/"
    db_path = os.path.join(output_folder, "db.sqlite3")

    manager = DBManager(db_path)
    manager.create_database()

    pattern = "NOUN~NOUN~have~VBN"
    print(manager.query_pattern(pattern))
