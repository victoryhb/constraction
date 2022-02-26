
import math, sequtils, tables

type MeasureType* = enum
    mtPMI, mtPMI2, mtPMI3, mtLogLikelihood, mtDeltaP, mtLogDice

proc toMeasureType*(str: string): MeasureType =
    case str:
    of "pmi": mtPMI
    of "pmi2": mtPMI2
    of "pmi3": mtPMI3
    of "loglikelihood": mtLogLikelihood
    of "delta-p": mtDeltaP
    of "logdice": mtLogDice
    else: mtPMI

var measure_thresholds* = {
    mtPMI: 3.0,
    mtPMI2: 6.0,
    mtPMI3: 9.0,
    mtLogLikelihood: 6.6,
    mtDeltaP: 0.05,
    mtLogDice: 3.0
}.newTable()

var SMALL = 1e-20
var N_PLACES = 3

proc product(numbers: seq[int]): int =
    result = 1
    for n in numbers:
        result *= n

proc log2(x: float64): float64 =
    return math.log(x, 2.0)

proc pmi*(word_counts: seq[int], ngram_count: int, summed_all_ngram_counts: int, coefficient: int = 1): float64 =
    # Scores ngrams by pointwise mutual information, as in Manning and Schutze 5.4.
    var val = ngram_count ^ coefficient * summed_all_ngram_counts ^ (len(word_counts) - 1)
    var score = log2(val.float64 / product(word_counts).float64)
    return round(score, N_PLACES)

proc getBigramContingency(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): array[4, int] =
    var a = ngram_count
    var b = word_count1 - a
    var c = word_count2 - a
    var d = summed_all_ngram_counts - (a + b + c)
    return [a, b, c, d]

proc expectedValues(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): seq[float64] =
    var n = 2
    var bits: seq[int]
    for i in 0..<n:
        bits.add(1 shl i)
    var cont = getBigramContingency(word_count1, word_count2, ngram_count, summed_all_ngram_counts)
    # For each contingency table cell
    var summed: int
    for i in 0..<cont.len:
        var sums: seq[int] = @[]
        for j in bits:
            summed = 0
            for x in 0..<(2 ^ n):
                if (x and j) == (i and j):
                    summed += cont[x]
            sums.add(summed)

        var product = product(sums)
        result.add(
            product / (summed_all_ngram_counts ^ (n - 1))
        )

proc logLikelihood*(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): float64 =
    var n = 2
    var cont = getBigramContingency(word_count1, word_count2, ngram_count, summed_all_ngram_counts)
    var expected_values = expectedValues(word_count1, word_count2, ngram_count, summed_all_ngram_counts)
    var total: float64
    for (obs, exp) in zip(cont, expected_values):
        total += float64(obs) * math.log(float64(obs) / (float64(exp) + SMALL) + SMALL, math.E)
    var score = float64(n) * total
    return round(score, N_PLACES)

proc deltaP*(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): array[2, float64] =
    var a, b, c, d: int
    (a, b, c, d) = getBigramContingency(word_count1, word_count2, ngram_count, summed_all_ngram_counts)
    # return "LR", "RL"
    return [ a / (a + c) - b / (b + d), a / (a + b) - c / (c + d) ]

proc dice*(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): float64 =
    return 2 * (ngram_count) / (word_count1 + word_count2)

proc log_dice*(word_count1: int, word_count2: int, ngram_count: int, summed_all_ngram_counts: int): float64 =
    var diced = dice(word_count1, word_count2, ngram_count, summed_all_ngram_counts)
    return 14 + log2(diced)

when isMainModule:
    assert pmi(@[10, 30], 5, 3000, 3) == 10.288
    assert getBigramContingency(10, 30, 5, 3000) == [5, 5, 25, 2965]
    assert logLikelihood(10, 30, 5, 3000) == 33.148
    assert dice(10, 30, 5, 3000) == 0.25
    assert log_dice(10, 30, 5, 3000) == 12.0
    # import benchy
    # timeIt "pmi":
    #     var v = pmi(@[10, 30], 5, 3000, 3)
    # timeIt "ll":
    #     var v = logLikelihood(10, 30, 5, 3000)