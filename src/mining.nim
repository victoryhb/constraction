import os, times
import strformat, strutils, sequtils
import myutils
import tables, sets, hashes
import measures
import algorithm
import std/enumerate, sugar
import data_manager
import std/db_sqlite
import json
import nimpy


proc addMerge(self: Sentence, token_ids: seq[int], token_types: seq[TokenType] = @[]) =
    self.merges.add(token_ids)
    var merge_idx = self.merges.len - 1
    # check that not all token_ids have been merged before
    # this is necessary because some positions were not removed in previous merges
    var token_type_len = token_types.len()
    for i, token_id in enumerate(token_ids):
        var token = self.tokens[token_id]
        self.token_id_to_merge_idx[token_id] = merge_idx
        if token_type_len == 2:
            # n of tokens is also 2
            token.chosen_type = token_types[i]
        elif token_type_len == 1 and token.chosen_type == ttNil:
            # i(ndividual) + m(erged); only i's type (==ttNil) needs setting
            token.chosen_type = token_types[0]

proc getFormsByTokenId(self: Sentence, token_id: int, 
        token_type: TokenType = ttLemma): OrderedTable[int, string] =
    var token: Token
    if token_id notin self.token_id_to_merge_idx:
        token = self.tokens[token_id]
        result[token_id] = token.getText(token_type)
    else:
        var merge = self.merges[self.token_id_to_merge_idx[token_id]]
        for tid in merge:
            token = self.tokens[tid]
            result[tid] = token.getText(token.chosen_type)


type Position = ref object
    sent_idx: int
    token_ids: seq[int]

proc hash(self: Position): Hash =
    var h: Hash = 0
    h = h !& hash(self.sent_idx)
    h = h !& hash(self.token_ids)
    result = !$h

proc `==`(self: Position, other: Position): bool =
    self.sent_idx == other.sent_idx and self.token_ids == other.token_ids


type PatternIndexer = ref object
    # copy semantics: p = indexer.pattern_positions; depends on the evaluated value of the right hand side
    pattern_positions: Table[string, HashSet[Position]]
    sent_idx_to_positions: Table[int, seq[Position]]
    pattern_counts: Table[string, int]
    pattern_to_bigrams: Table[string, (string, string)]
    sent_idx_to_pattern_counts: Table[int, Table[string, int]]
    # remember the type of non-lemma tokens; might clash with lemma (e.g.=="DET")
    token_to_type: Table[string, TokenType]
    token_types: seq[TokenType] # token type for enumeration
    allowed_values: TableRef[TokenType, HashSet[string]]
    ignored_values: TableRef[TokenType, HashSet[string]]
    target_tokens: TableRef[string, Table[TokenType, string]]
    isTargetMode: bool
    max_hops: int  # dep distance between two words in a sentence
    merge_adjacent: bool
    corpus: Corpus

proc init(self: PatternIndexer, corpus: Corpus,
        config: JsonNode = parseJson("{}")) =
    self.corpus = corpus
    for elem in config{"token_types"}.getElems():
        self.token_types.add(elem.getStr().toTokenType())
    if self.token_types.len == 0:
        self.token_types = @[ttLemma]

    self.allowed_values = newTable[TokenType, HashSet[string]]()
    for (key, values) in config{"allowed_values"}.getFields().pairs():
        var token_type = key.toTokenType()
        self.allowed_values[token_type] = initHashSet[string]()
        for value in values.getElems():
            self.allowed_values[token_type].incl(value.getStr())
    for key in self.allowed_values.keys.toSeq():
        if key notin self.token_types:
            self.allowed_values.del(key)

    self.ignored_values = newTable[TokenType, HashSet[string]]()
    for (key, values) in config{"ignored_values"}.getFields().pairs():
        var token_type = key.toTokenType()
        self.ignored_values[token_type] = initHashSet[string]()
        for value in values.getElems():
            self.ignored_values[token_type].incl(value.getStr())

    self.target_tokens = newTable[string, Table[TokenType, string]]()
    for (key, values) in config{"target_tokens"}.getFields().pairs():
        self.target_tokens[key] = initTable[TokenType, string]()
        for (token_type_str, value) in values.getFields().pairs():
            var token_type = token_type_str.toTokenType()
            self.target_tokens[key][token_type] = value.getStr()
    self.isTargetMode = self.target_tokens.len > 0

    self.max_hops = 2
    self.merge_adjacent = true

proc addPosition(self: PatternIndexer, pattern: string, position: Position) =
    if pattern notin self.pattern_positions:
        self.pattern_positions[pattern] = HashSet[Position]()
    self.pattern_positions[pattern].incl(position)
    if position.sent_idx notin self.sent_idx_to_positions:
        self.sent_idx_to_positions[position.sent_idx] = @[]
    self.sent_idx_to_positions[position.sent_idx].add(position)
    if pattern notin self.pattern_counts:
        self.pattern_counts[pattern] = 1
    else:
        self.pattern_counts[pattern] += 1
    if position.sent_idx notin self.sent_idx_to_pattern_counts:
        self.sent_idx_to_pattern_counts[position.sent_idx] = initTable[string, int]()
    if pattern notin self.sent_idx_to_pattern_counts[position.sent_idx]:
        self.sent_idx_to_pattern_counts[position.sent_idx][pattern] = 1
    else:
        self.sent_idx_to_pattern_counts[position.sent_idx][pattern] += 1

iterator getPositions(self: PatternIndexer, pattern: string): Position =
    for pos in self.pattern_positions[pattern]:
        yield pos

proc removePositions(self: PatternIndexer, pattern: string) {.inline.} =
    self.pattern_positions.del(pattern)

proc count(self: PatternIndexer, pattern: string): int {.inline.} =
    # with plain objects, copies of used value in PatternIndexer will be made, which is expensive!
    if pattern notin self.pattern_counts:
        echo fmt"counts not found for '{pattern}'"
        return 0
    self.pattern_counts[pattern]

proc isValidTarget(self: PatternIndexer, token: Token): bool =
    if token.lemma in self.target_tokens:
        var requirements = self.target_tokens[token.lemma]
        for token_type, value in requirements.pairs():
            if token.getText(token_type) != value:
                return false
    else:
        return false
    return true

proc indexBigram(self: PatternIndexer, sentence: Sentence, token: Token, 
        token_type: TokenType = ttNil, head: Token, head_type: TokenType = ttNil,
        sentence_cache: var HashSet[(int, TokenType)]): string {.inline.} =
    var token_id_to_forms = sentence.getFormsByTokenId(token.id, token_type = token_type)
    var token_ids = token_id_to_forms.keys().toSeq()
    var token_form = token_id_to_forms.values().toSeq().join("~")
    var token_pos = Position(sent_idx: sentence.id, token_ids: token_ids)
    if token_type != ttNil:
        self.token_to_type[token_form] = token_type
    # if it has not been indexed before; only the first token of a pattern gets indexed
    if (token.id, token_type) notin sentence_cache and token.id == min(token_ids):
        self.addPosition(token_form, token_pos)
        sentence_cache.incl((token.id, token_type))

    if token.id == head.id:
        return
    if token.upos == "PUNCT" or head.upos == "PUNCT":
        return
    var head_id_to_forms = sentence.getFormsByTokenId(head.id, token_type = head_type)
    var head_ids = head_id_to_forms.keys().toSeq()
    var head_form = head_id_to_forms.values().toSeq().join("~")
    if (head_ids.toHashSet() * token_ids.toHashSet()).len > 0: # intersection
        return
    if head_type != ttNil:
        self.token_to_type[head_form] = head_type
    if (head.id, head_type) notin sentence_cache and head.id == min(head_ids):
        var head_pos = Position(sent_idx: sentence.id, token_ids: head_ids)
        self.addPosition(head_form, head_pos)
        sentence_cache.incl((head.id, head_type))

    if self.isTargetMode:
        var has_merged_before = token_type == ttNil or head_type == ttNil
        if not ((self.isValidTarget(token) or self.isValidTarget(head)) or has_merged_before):
            return
    var merged_ids = (token_ids & head_ids).sorted()
    token_id_to_forms.merge(head_id_to_forms)
    var forms: seq[string]
    for id in merged_ids:
        forms.add(token_id_to_forms[id])
    var merged_form = forms.join("~")
    if merged_form notin self.pattern_to_bigrams:  # A~B + C == A + B~C
        self.pattern_to_bigrams[merged_form] = if token_ids[0] < head_ids[0]: 
                (token_form, head_form) else: (head_form, token_form)
    var pattern_pos = Position(sent_idx: sentence.id, token_ids: merged_ids)
    self.addPosition(merged_form, pattern_pos)
    return merged_form

proc isInvalidToken(self: PatternIndexer, token:Token, token_type: TokenType): bool =
    var text = token.getText(token_type)
    (
        token.skipped or text == "" or
        (token_type in self.allowed_values and text notin self.allowed_values[token_type]) or 
        (token_type in self.ignored_values and text in self.ignored_values[token_type])
    )

proc getTokenHeadBigram(self: PatternIndexer, token: Token, 
        head: Token): seq[(Token, TokenType, Token, TokenType)] {.inline.} =
    var token_types: seq[TokenType]
    var head_types: seq[TokenType]
    # when token.chosen_type != ttNil, use the single merged form (indicated using @[ttNil]）
    token_types = if token.chosen_type == ttNil: self.token_types else: @[ttNil]
    head_types = if head.chosen_type == ttNil: self.token_types else: @[ttNil]
    for token_type in token_types:
        if self.isInvalidToken(token, token_type):
            continue
        for head_type in head_types:
            if self.isInvalidToken(head, head_type):
                continue
            result.add((token, token_type, head, head_type))

proc indexSentence(self: PatternIndexer, sentence: Sentence): HashSet[string] =
    # to remember whether a token/pattern has been indexed or not
    var sentence_cache = HashSet[(int, TokenType)]() # [token_idx, token_type]
    var bigrams: seq[(Token, TokenType, Token, TokenType)]
    var bigram_ids: HashSet[(int, int)]  # to prevent duplicated indexing
    for token in sentence.tokens:
        var head = sentence.tokens[token.head_id]
        bigrams &= self.getTokenHeadBigram(token, head)
        bigram_ids.incl((token.id, head.id))  # back get (head)
        bigram_ids.incl((head.id, token.id))  # "get back" should not be indexed again later

    # add adjacent bigrams in the sentence to bigrams if their ids are not in bigram_ids
    if self.merge_adjacent:
        for i, token in enumerate(sentence.tokens):
            if i + 1 < sentence.tokens.len:
                var next_token = sentence.tokens[i + 1]
                if (token.id, next_token.id) notin bigram_ids:
                    bigrams &= self.getTokenHeadBigram(token, next_token)

    for (token, token_type, head, head_type) in bigrams:
        var pattern = self.indexBigram(sentence, token, token_type, head, head_type, sentence_cache)
        if pattern != "":
            result.incl(pattern)

proc unindexSentence(self: PatternIndexer, sent_idx: int) =
    if sent_idx notin self.sent_idx_to_pattern_counts:
        # TODO: why is this necessary after markSentencesWithTargetTokens()?
        return
    for pattern, count in self.sent_idx_to_pattern_counts[sent_idx].pairs():
        self.pattern_counts[pattern] -= count # self.sent_idx_to_positions[sent_idx].len
        for pos in self.sent_idx_to_positions[sent_idx]:
            # pos.disabled = true
            self.pattern_positions[pattern].excl(pos)
    self.sent_idx_to_positions.del(sent_idx)
    self.sent_idx_to_pattern_counts.del(sent_idx)

proc markSkippedTokens(self: PatternIndexer, token_lemma: string, sentence: Sentence) =
    var head_id_to_dep_ids: Table[int, HashSet[int]]
    var relations: Table[int, HashSet[int]] # relations between a token and all connected tokens
    var to_mark: seq[(int, int)]  # token_id, level
    var marked_ids: HashSet[int]
    for token in sentence.tokens:
        var head_id = token.head_id
        if head_id notin head_id_to_dep_ids:
            head_id_to_dep_ids[head_id] = HashSet[int]()
        head_id_to_dep_ids[head_id].incl(token.id)
        for id in [token.id, head_id]:
            if id notin relations:
                relations[id] = HashSet[int]()
        relations[head_id].incl(token.id)
        relations[token.id].incl(head_id)
        if token.lemma == token_lemma:
            to_mark.add((token.id, 1))
            to_mark.add((token.head_id, 2))  # ignore its relations (to some degree)
            if self.merge_adjacent and token.id + 1 < sentence.tokens.len:
                var next_token = sentence.tokens[token.id + 1]
                to_mark.add((next_token.id, 2))  # ignore its relations
        token.skipped = true

    while to_mark.len > 0:
        var (token_id, level) = to_mark.pop()
        if token_id in marked_ids:
            continue
        marked_ids.incl(token_id)
        if level > self.max_hops:  # unproductive
            continue
        sentence.tokens[token_id].skipped = false
        var rel_ids = relations[token_id]
        for rel_id in rel_ids:
            sentence.tokens[rel_id].skipped = false
            if level < self.max_hops:
                to_mark.add((rel_id, level + 1))
                to_mark.add((sentence.tokens[rel_id].head_id, level + 1))

proc markSentencesWithTargetTokens(self: PatternIndexer) =
    if self.isTargetMode and self.max_hops > 0:
        for lemma in self.target_tokens.keys():
            for pos in self.getPositions(lemma):
                self.markSkippedTokens(lemma, self.corpus.sentences[pos.sent_idx])


type ScoredPattern = ref object
    pattern: string
    left: string
    right: string
    score: float64
    count: int
    task_id: int

proc hash(self: ScoredPattern): Hash =
    var h: Hash = 0
    h = h !& hash(self.pattern)
    result = !$h

proc `==`(self: ScoredPattern, other: ScoredPattern): bool =
    self.pattern == other.pattern


type PatternAnalyzer = ref object
    corpus: Corpus
    indexer: PatternIndexer
    candidate_patterns: HashSet[string]
    discarded_patterns: HashSet[string]
    merged_patterns: OrderedSet[ScoredPattern]
    total_token_count: int
    min_score_threshold: float64
    min_pattern_freq: int
    affected_sent_idxes: HashSet[int]
    association_measure: MeasureType
    task_id: int

proc init(self: PatternAnalyzer, config: JsonNode = parseJson("{}")) =
    self.indexer = PatternIndexer()
    self.indexer.init(self.corpus, config=config)
    self.total_token_count = self.corpus.total_token_count
    var min_pattern_freq_per_mill = config{"min_pattern_freq_per_mill"}.getInt()
    min_pattern_freq_per_mill = max(min_pattern_freq_per_mill, 1)
    self.min_pattern_freq = max(int(self.total_token_count * min_pattern_freq_per_mill / 1000000 ), 3)
    # self.min_pattern_freq = min(self.min_pattern_freq, 10)
    var association_measure = config{"association_measure"}.getStr()
    self.association_measure = association_measure.toMeasureType()
    var min_score_threshold = config{"min_score_threshold"}.getFloat()
    if min_score_threshold != 0.0:
        self.min_score_threshold = min_score_threshold
    else:
        self.min_score_threshold = measure_thresholds[self.association_measure]
    debugEcho fmt"{self.association_measure}, {self.min_pattern_freq} {min_pattern_freq_per_mill}, {self.min_score_threshold}"

proc scorePattern(self: PatternAnalyzer, pattern: string): float64 =
    var (token1, token2) = self.indexer.pattern_to_bigrams[pattern]
    var pattern_count = self.indexer.count(pattern)
    var token1_count = self.indexer.count(token1)
    var token2_count = self.indexer.count(token2)
    if token1_count == 0 or token2_count == 0:
        return 0.0
    case self.association_measure:
    of mtLoglikelihood:
        measures.logLikelihood(token1_count, token2_count, pattern_count, self.total_token_count)
    of mtDeltaP:
        max(measures.deltaP(token1_count, token2_count, pattern_count, self.total_token_count))
    of mtPMI, mtPMI2, mtPMI3:
        measures.pmi(@[token1_count, token2_count], pattern_count, 
                        self.total_token_count, ord(self.association_measure) + 1)
    of mtLogDice:
        measures.logDice(token1_count, token2_count, pattern_count, self.total_token_count)

proc mergePattern(self: PatternAnalyzer, pattern: string) =
    self.total_token_count -= self.indexer.count(pattern)
    var token_types: seq[TokenType]
    var (token1, token2) = self.indexer.pattern_to_bigrams[pattern]
    # three possible scenarios for (i)ndividual or (m)erged tokens
    # 1. i + i (2-gram)  2. i + m OR m + i (1-gram)  3. m + m (nothing)
    if "~" notin token1 and "~" notin token2: #  i + i
        # generate the chosen_type of each token to be passed
        if token1 in self.indexer.token_to_type and token2 in self.indexer.token_to_type:
            token_types = @[self.indexer.token_to_type[token1], 
                            self.indexer.token_to_type[token2]]
    elif "~" notin token1: # i + m
        token_types = @[self.indexer.token_to_type[token1]]
    elif "~" notin token2: # m + i
        token_types = @[self.indexer.token_to_type[token2]]
    # For the sentence "A accused B, C of something", 
    # "accuse~of" is counted once, but "accuse~NOUN~of" is counted twice
    # To simplify, we count one pattern per sentence
    for pos in self.indexer.getPositions(pattern):
        var sent = self.corpus.sentences[pos.sent_idx]
        sent.addMerge(pos.token_ids, token_types = token_types)
        self.affected_sent_idxes.incl(pos.sent_idx)

proc mergeTopPatterns(self: PatternAnalyzer, n: int = 100, 
        on_merge: proc (pa: PatternAnalyzer, scored_pattern: ScoredPattern) = nil
    ): OrderedSet[ScoredPattern] =
    var affected_sent_idxes = self.affected_sent_idxes
    self.affected_sent_idxes.clear()
    var candidates: HashSet[string]
    if affected_sent_idxes.len == 0:  # first time
        for sentence in self.corpus.sentences:
            candidates.incl(self.indexer.indexSentence(sentence))
        self.indexer.markSentencesWithTargetTokens()
    else:
        for sent_idx in affected_sent_idxes:
            self.indexer.unindexSentence(sent_idx)
            candidates.incl(self.indexer.indexSentence(self.corpus.sentences[sent_idx]))
    self.candidate_patterns.incl(candidates)
    var scored_patterns: seq[ScoredPattern]
    var score: float64
    self.candidate_patterns.excl(self.discarded_patterns)
    for pattern in self.candidate_patterns:
        if self.indexer.count(pattern) >= self.min_pattern_freq:
            score = self.scorePattern(pattern)
            if score < self.min_score_threshold:
                self.discarded_patterns.incl(pattern)
                continue
            scored_patterns.add(ScoredPattern(pattern: pattern, score: score, count: self.indexer.count(pattern)))
        else:
            self.discarded_patterns.incl(pattern)
    scored_patterns.sort((x, y) => -cmp(x.score, y.score))
    var merged_tokens: seq[string]
    # echo "top 5 patterns: ", scored_patterns.first(5)
    for i, sp in enumerate(scored_patterns):
        var pattern = sp.pattern
        var (token1, token2) = self.indexer.pattern_to_bigrams[pattern]  # Why can't I put .fields here?
        # avoid conflicts of components in bigrams in the same round
        if token1 in merged_tokens or token2 in merged_tokens:
            continue
        merged_tokens.add(token1)
        merged_tokens.add(token2)
        sp.left = token1
        sp.right = token2
        self.mergePattern(pattern)
        if on_merge != nil:
            on_merge(self, sp)
        self.candidate_patterns.excl(pattern)
        if sp in self.merged_patterns:  # sometimes the same pattern is merged twice (A~B+C==A+B~C)
            continue  # so that the number of merged_patterns always changes
        self.merged_patterns.incl(sp)
        result.incl(sp)
        if i >= n - 1:
            break

proc writeResults(file: var File, analyzer: PatternAnalyzer, scored_patterns: OrderedSet[ScoredPattern]) =
    for sp in scored_patterns:
        var pattern = sp.pattern
        var unique_sent_idxes: HashSet[int]
        var count2 = 0
        for pos in analyzer.indexer.getPositions(pattern):
            count2 += 1
            unique_sent_idxes.incl(pos.sent_idx)
        var count3 = unique_sent_idxes.len
        file.writeLine(fmt"{pattern}, {sp.left}, {sp.right}, {sp.score}, {sp.count}#{count2}#{count3}")
    file.flushFile()

proc storePositions(db: DbConn, analyzer: PatternAnalyzer, sp: ScoredPattern) =
    # store the positions of the pattern in a sqlite database
    # TODO: refactor using insertRowsToDB
    var pattern = sp.pattern
    var pattern_id: int64
    var id = db.getValue(sql"SELECT id FROM pattern WHERE form = ? AND task_id = ?", pattern, analyzer.task_id)
    if id != "":
        pattern_id = parseInt(id)
    else:
        pattern_id = db.insertID(
            sql"INSERT INTO pattern (form, left, right, score, count, task_id) VALUES (?, ?, ?, ?, ?, ?)", 
            pattern, sp.left, sp.right, sp.score, sp.count, analyzer.task_id
        )
    db.exec(sql"BEGIN TRANSACTION;")
    for pos in analyzer.indexer.getPositions(pattern):
        db.exec(sql"INSERT INTO position (pattern_id, sentence_id, token_ids) VALUES (?, ?, ?)", 
            pattern_id, pos.sent_idx, pos.token_ids.join(","))
    db.exec(sql"COMMIT;")


proc mine_patterns(json_path: string, output_folder: string, 
        config: JsonNode, store_in_database: bool = false, 
        task_id: int = -1) {.exportpy.} =
    var corpus = loadJson(json_path)
    var db_path = joinPath(output_folder, "db.sqlite3")
    var db: DbConn
    var on_merge: proc (pa: PatternAnalyzer, scored_pattern: ScoredPattern)
    if store_in_database:
        try:
            storeTokensInDatabase(corpus, db_path)
        except:
            let e = getCurrentException()
            let msg = getCurrentExceptionMsg()
            echo "Got exception ", repr(e), " with message ", msg
        db = getDatabase(db_path)
        on_merge = (pa: PatternAnalyzer, scored_pattern: ScoredPattern) => 
            db.storePositions(pa, scored_pattern)
    var analyzer = PatternAnalyzer(corpus: corpus, task_id: task_id)
    analyzer.init(config=config)
    var n_per_round = config{"n_per_round"}.getInt(10)
    if analyzer.indexer.isTargetMode:
        n_per_round = 1
    var n_total_rounds = config{"n_total_rounds"}.getInt(100)
    echo fmt"Total sents: {corpus.sentences.len}; min_score_threshold: {analyzer.min_score_threshold}; min_pattern_freq: {analyzer.min_pattern_freq}; n_per_round: {n_per_round}; n_total_rounds: {n_total_rounds}"
    var file = open(joinPath(output_folder, "temp_output.txt"), fmWrite)
    for i in 1..n_total_rounds:
        var last_pattern_count = analyzer.merged_patterns.len
        var n_sents = if analyzer.affected_sent_idxes.len > 0:
            analyzer.affected_sent_idxes.len else: analyzer.corpus.sentences.len
        echo fmt"Merge round {i}: {last_pattern_count} merged; {n_sents} sents; remaining tokens: {analyzer.total_token_count}"
        var scored_patterns = analyzer.mergeTopPatterns(n = n_per_round, on_merge = on_merge)
        file.writeResults(analyzer, scored_patterns)
        if last_pattern_count == analyzer.merged_patterns.len:
            break
    file = open(joinPath(output_folder, "output.txt"), fmWrite)
    file.writeResults(analyzer, analyzer.merged_patterns)
    if store_in_database:
        db.close()


proc example(input_folder: string, json_basename="corpus.json") =
    var config_str = """
    {
        "association_measure": "pmi2",
        "min_score_threshold_": 6.0,
        "min_pattern_freq_per_mill": 3,
        "token_types": ["lemma", "upos", "xpos", "supersense"],
        "allowed_values": {
            "upos": ["PRON", "NOUN"],
            "xpos": ["WH", "VBG", "VBN"],
            "deprel": ["ccomp"]
        },
        "ignored_values": {
            "lemma": ["'", "a", "an", "the", "he", "his", "she", "her", "my", "our", "they", "their", "erm", "may", "should", "will", "shall", "can", "might", "must", "would", "ought", "could"]
        },
        "target_tokens_": {
            "play": {"upos": "VERB"},
            "note": {},
        },
        "n_total_rounds": 10,
        "n_per_round": 10,
    }
    """
    var config = parseJson(config_str)

    var output_folder = input_folder
    var json_path = joinPath(input_folder, json_basename)
    mine_patterns(json_path, output_folder, config, store_in_database=false)


if isMainModule:
    benchmark "main":
        example("/Users/yan/Downloads/patterns/json_transformed", "merge-dep-supersenses1000.json")