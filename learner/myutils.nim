import hashes
import tables


template benchmark*(benchmarkName: string, code: untyped) =
  block:
    let t0 = epochTime()
    code
    let elapsed = epochTime() - t0
    let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 3)
    echo "CPU Time [", benchmarkName, "] ", elapsedStr, "s"

proc autohash*[T: tuple|object](o: T): Hash =
  var h: Hash = 0
  for f in o.fields: h = h !& f.hash
  !$h

proc merge*[A, B] (table1: var Table[A, B], table2: var Table[A, B]) =
  for key, val in table2.pairs():
    table1[key] = val

proc merge*[A, B] (table1: var OrderedTable[A, B], table2: var OrderedTable[A, B]) =
  for key, val in table2.pairs():
    table1[key] = val

proc merged*[A, B] (table1: var Table[A, B], table2: var Table[A, B]): Table[A, B] =
  # slower than merge()
  var merged_table: Table[A, B]
  for table in [table1, table2]:
    for key, val in table.pairs():
      merged_table[key] = val
  return merged_table

iterator first*[A, B] (table: var OrderedTable[A, B], n: int): (A, B) =
    var i = 0
    for key, val in table.pairs():
        if i < n:
            yield (key, val)
        else:
            break
        i += 1

proc toOrderedTable*[A, B] (table: Table[A, B]): OrderedTable[A, B] =
    var ordered_table: OrderedTable[A, B](table.len)
    for key, val in table.pairs():
        ordered_table[key] = val
    return ordered_table

