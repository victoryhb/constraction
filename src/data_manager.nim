import std/db_sqlite
import strformat, strutils
import sequtils
import tables
import jsony
import json
import std/enumerate


type TokenType* = enum
    ttNil, ttLemma, ttUpos, ttXpos, ttDeprel, ttText, ttSupersense

proc toTokenType*(str: string): TokenType =
    case str.toLower():
    of "lemma": ttLemma
    of "upos": ttUpos
    of "xpos": ttXpos
    of "deprel": ttDeprel
    of "text": ttText
    of "supersense": ttSupersense
    else: ttNil

# almost every custom type should be a ref object to simulate Python behavior
type Token* = ref object
    id*: int
    text*: string
    lemma*: string
    upos*: string
    xpos*: string
    deprel*: string
    head_id*: int
    supersense*: string
    chosen_type*: TokenType
    skipped*: bool

proc getText*(self: Token, token_type: TokenType): string =
    case token_type:
    of ttNil: self.lemma
    of ttLemma: self.lemma
    of ttUpos: self.upos
    of ttXpos: self.xpos
    of ttDeprel: self.deprel
    of ttSupersense: self.supersense
    of ttText: self.text.toLower()


type JsonSent = object
    file_name: string
    tokens: seq[Token]


type JsonSents = seq[JsonSent]


type Sentence* = ref object
    id*: int
    file_name*: string
    tokens*: seq[Token]
    merges*: seq[seq[int]]
    token_id_to_merge_idx*: Table[int, int]


type Corpus* = ref object
    sentences*: seq[Sentence]
    total_token_count*: int


proc loadJson*(json_path: string): Corpus =
    result = Corpus() # ref objects need to be initialized first
    let all_sents = readFile(json_path).fromJson(JsonSents)
    for sent_idx, j_sent in enumerate(all_sents):
        var sentence = Sentence(id: sent_idx, tokens: j_sent.tokens, file_name: j_sent.file_name)
        result.sentences.add(sentence)
        result.total_token_count += sentence.tokens.len


proc getDatabase*(db_path: string): DbConn =
    # var db_path = output_folder & "db.sqlite3"
    result = open(db_path, "", "", "")

proc storeTokensInDatabase*(corpus: Corpus, db_path: string) =
    var db = getDatabase(db_path)
    try:
        db.exec(sql"BEGIN TRANSACTION;")
        for sentence in corpus.sentences:
            db.exec(sql"INSERT INTO sentence (id, file_name) VALUES (?,?);", sentence.id, sentence.file_name)
            for token in sentence.tokens:
                var cmd = sql"INSERT INTO token (id, sentence_id, text, lemma, upos, xpos, deprel, supersense, head_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                db.exec(cmd, token.id, sentence.id, token.text, token.lemma, token.upos, token.xpos, token.deprel, token.supersense, token.head_id)
        db.exec(sql"COMMIT;")
    except:
        db.close()
        raise

proc getTableCreationSQL(table_name: string, row: JsonNode): string =
    var table_info = ""
    var row_keys = row.keys.toSeq()
    for i, key in enumerate(row_keys):
        var kind = if row[key].kind == JInt: "INTEGER" else: "TEXT"
        table_info &= fmt"{key} {kind}"
        if i != row_keys.len - 1:
            table_info &= ", "
    if "id" notin row:
        table_info = "id INTEGER PRIMARY KEY, " & table_info
    var cmd = fmt"CREATE TABLE IF NOT EXISTS {table_name} ({table_info})"
    return cmd

proc insertRowsToDB*(db: DbConn, table_name: string, rows: seq[JsonNode],
        auto_create_table: bool = true) =
    # create a table named table_name if it does not exist with the field names being the keys of the first row
    var jrows = %*(rows) # convert to JsonNode (seq of JObjects)
    var cmd: string
    if auto_create_table:
        cmd = getTableCreationSQL(table_name, jrows[0])
        db.exec(sql(cmd))

    db.exec(sql"BEGIN TRANSACTION;")
    for row in jrows:
        var inserted_cols = ""
        var inserted_vals = ""
        var row_keys = row.keys.toSeq()
        for i, key in enumerate(row_keys):
            var val = row[key]
            var strVal: string
            if val.kind == JString:
                strVal = fmt"'{($val)[1..^2]}'" # change double quotes to single quotes
            else:
                strVal = $val
            var comma = if i != row_keys.len - 1: ", " else: ""
            inserted_cols &= key & comma
            inserted_vals &= strVal & comma
        cmd = fmt"INSERT INTO {table_name} ({inserted_cols}) VALUES ({inserted_vals})"
        echo cmd
        db.exec(sql(cmd))
    db.exec(sql"COMMIT;")

# proc test(db: DbConn) =
#     var rows = @[%*{"a": 1, "b": 2, "c": 3}]
#     insertRowsToDB(db, "test", rows)
#     var row2 = @[%*({"a": 123, "b": "test", "c": "order", "d": ""})]
#     insertRowsToDB(db, "test2", row2)


when isMainModule:
    import times
    # time the following code
    var start = times.epochTime()
    # removeFile(db_path)
    # corpus.storeTokensInDatabase(db_path)
    # db.close()
    echo "Time: ", (times.epochTime() - start).formatFloat(precision=3)
