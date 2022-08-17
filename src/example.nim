import mining
import myutils
import times
import strutils


var config_str = """
{
    "association_measure": "pmi2",
    "min_score_threshold": 6.0,
    "min_pattern_freq_per_mill": 3,
    "token_types": ["lemma", "upos", "xpos", "supersense"],
    "token_types": ["lemma"],
    "allowed_values": {
        "upos": ["PRON", "NOUN"],
        "xpos": ["WH", "VBG", "VBN"],
        "deprel": ["ccomp"]
    },
    "ignored_values": {
        "lemma": ["'", "a", "an", "the", "he", "his", "she", "her", "my", "our", "they", "their", "erm", "may", "should", "will", "shall", "can", "might", "must", "would", "ought", "could"]
    },
    "target_tokens": {
        "play": {"upos": "VERB"},
        "note": {},
    },
    "n_total_rounds": 10,
    "n_per_round": 10,
}
"""

benchmark "minePatterns":
    processCorpus("/Users/yan/Downloads/patterns/json_transformed/merge-dep-supersenses1000.json", config_str=config_str)
# benchmark "extractByRules":
    # extractPatternsByRules("/Users/yan/Downloads/patterns/json_transformed/merge-dep-supersenses1000.json", "/Users/yan/Downloads/patterns/json_transformed/output.txt", config_str=config_str)
